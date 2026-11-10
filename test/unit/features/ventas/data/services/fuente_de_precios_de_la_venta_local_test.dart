// Con qué precios se vende (HU-VEN-001, vista 27, decisión P4 de #158): la ciudad de la casa del
// cliente en la campaña en curso de la colportora, leída del teléfono (la casa y las réplicas del pull
// de catálogos), sin red. Es lo que destraba «Nueva venta» (antes siempre daba el error de precios).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:colportores_mobile/features/ventas/data/services/fuente_de_precios_de_la_venta_local.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/precios_de_la_venta.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/replica_de_campanias.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;

  // «Hoy» es el 10/11/2026 al mediodía en Montevideo (15:00 UTC).
  var ahora = DateTime.utc(2026, 11, 10, 15);

  FuenteDePreciosDeLaVentaLocal fuente() =>
      FuenteDePreciosDeLaVentaLocal(db, ahora: () => ahora, logger: loggerMudo());

  setUp(() async {
    ahora = DateTime.utc(2026, 11, 10, 15);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    // La casa de María está en Montevideo: ub-1 → esp-1 → ep-1.
    await sembrarUbicacion(db, ciudadId: 'ciu-mvd');
    await sembrarEspacio(db);
    await sembrarVinculo(db);
  });
  tearDown(() => db.close());

  Map<String, List<Map<String, Object?>>> ciudades() => {
    'ciudad': [
      filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9, lon: -56.16),
      filaCiudad('ciu-sal', 'Salto', lat: -31.38, lon: -57.96),
    ],
  };

  Future<void> bajar(Map<String, List<Map<String, Object?>>> filas, {bool pull = true}) async {
    await replica.bajar({...ciudades(), ...filas});
    if (pull) await replica.terminoUnPull();
  }

  Future<PreciosDeLaVenta> leer({String colportor = 'col-1', String vinculo = 'ep-1'}) async {
    final r = await fuente().leer(colportorId: colportor, espacioPersonaId: vinculo);
    return r.getOrElse(() => throw StateError('falló: $r'));
  }

  Future<void> debeNoSaber({String vinculo = 'ep-1'}) async {
    final r = await fuente().leer(colportorId: 'col-1', espacioPersonaId: vinculo);
    expect(r.isLeft(), isTrue, reason: 'no se sabe: nunca "no tenés precios"');
    expect(r.swap().getOrElse(() => throw StateError('')), isA<FailurePreciosNoDisponibles>());
  }

  /// Verano 2026 en curso (01/10 al 28/02) con Montevideo y Salto, y la colportora inscripta.
  Map<String, List<Map<String, Object?>>> verano({
    String? fin = '2027-02-28',
    String inicio = '2026-10-01',
  }) => {
    'campania': [filaCampania('camp-1', 'Verano 2026', inicio: inicio, fin: fin)],
    'campania_ciudad': [
      filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
      filaCampaniaCiudad('cc-sal', campania: 'camp-1', ciudad: 'ciu-sal'),
    ],
    'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
  };

  test(
    'Escenario básico: la casa en Montevideo vende con los precios de Montevideo de la campaña en '
    'curso',
    () async {
      await bajar(verano());

      expect(
        await leer(),
        const PreciosVigentes(
          CiudadConsultable(
            campaniaCiudadId: 'cc-mvd',
            ciudadId: 'ciu-mvd',
            nombre: 'Montevideo',
            campaniaNombre: 'Verano 2026',
          ),
        ),
      );
    },
  );

  test('la ciudad es la de la casa, no otra de la campaña', () async {
    await sembrarUbicacion(db, id: 'ub-2', ciudadId: 'ciu-sal');
    await sembrarEspacio(db, id: 'esp-2', ubicacionId: 'ub-2');
    await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
    await bajar(verano());

    final precios = await leer(vinculo: 'ep-2');

    expect((precios as PreciosVigentes).ciudad.campaniaCiudadId, 'cc-sal');
  });

  test('27A·10: la campaña de la ciudad terminó → sin precios, con el nombre y el fin', () async {
    await bajar(verano(inicio: '2026-06-01', fin: '2026-10-31'));

    expect(
      await leer(),
      SinCampaniaVigente(
        terminada: CampaniaTerminada(nombre: 'Verano 2026', terminoEl: DateTime(2026, 10, 31)),
      ),
    );
  });

  test('el último día de la campaña todavía se vende', () async {
    await bajar(verano(fin: '2026-11-10'));

    expect(await leer(), isA<PreciosVigentes>());
  });

  test(
    'una campaña que todavía no empezó no da precios (el servidor rechazaría la venta)',
    () async {
      await bajar(verano(inicio: '2026-11-11'));

      expect(await leer(), const SinCampaniaVigente());
    },
  );

  test('con una terminada y otra en curso en la misma ciudad, se usa la en curso', () async {
    await bajar({
      'campania': [
        filaCampania('camp-0', 'Primavera 2026', inicio: '2026-06-01', fin: '2026-10-15'),
        filaCampania('camp-1', 'Verano 2026'),
      ],
      'campania_ciudad': [
        filaCampaniaCiudad('cc-vieja', campania: 'camp-0', ciudad: 'ciu-mvd'),
        filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
      ],
      'campania_colportor': [
        filaInscripcion('insc-0', campania: 'camp-0'),
        filaInscripcion('insc-1', campania: 'camp-1'),
      ],
    });

    expect((await leer() as PreciosVigentes).ciudad.campaniaCiudadId, 'cc-mvd');
  });

  test('la casa en una ciudad que no es de sus campañas → sin precios (no un error)', () async {
    await bajar({
      'campania': [filaCampania('camp-1', 'Verano 2026')],
      'campania_ciudad': [filaCampaniaCiudad('cc-sal', campania: 'camp-1', ciudad: 'ciu-sal')],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
    });

    expect(await leer(), const SinCampaniaVigente());
  });

  test('sin ninguna inscripción viva → sin precios', () async {
    final mundo = verano();
    mundo['campania_colportor'] = [filaInscripcion('insc-1', campania: 'camp-1', deBaja: true)];
    await bajar(mundo);

    expect(await leer(), const SinCampaniaVigente());
  });

  test('la inscripción de otra colportora no cuenta', () async {
    final mundo = verano();
    mundo['campania_colportor'] = [filaInscripcion('insc-1', campania: 'camp-1', usuario: 'col-2')];
    await bajar(mundo);

    expect(await leer(), const SinCampaniaVigente());
  });

  test('una ciudad quitada de la campaña no cuenta', () async {
    final mundo = verano();
    mundo['campania_ciudad'] = [
      filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd', deBaja: true),
    ];
    await bajar(mundo);

    expect(await leer(), const SinCampaniaVigente());
  });

  group('no se sabe (error con «Reintentar», nunca «no tenés precios»)', () {
    test('ningún pull terminó todavía', () async {
      await bajar(verano(), pull: false);

      await debeNoSaber();
    });

    test('la persona no está en el teléfono', () async {
      await bajar(verano());

      await debeNoSaber(vinculo: 'ep-no-esta');
    });

    test('falta la campaña a la que apunta la inscripción', () async {
      final mundo = verano();
      mundo['campania'] = [];
      await bajar(mundo);

      await debeNoSaber();
    });

    test('falta la ciudad de la casa en la réplica', () async {
      await replica.bajar(verano());
      await replica.terminoUnPull();

      await debeNoSaber();
    });
  });
}
