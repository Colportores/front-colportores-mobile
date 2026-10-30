// Las ciudades de las campañas de la colportora para consultar precios (HU-CAT-006, vista 26, #421),
// leídas de las réplicas locales: sin red, con las filas entrando por el mismo `DriftLocalStore` del
// pull de catálogos.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/data/datasources/ciudades_para_precios_local_data_source.dart';
import 'package:colportores_mobile/features/catalogo/data/repositories/fuente_de_ciudades_para_precios_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/replica_de_campanias.dart';

const _colportor = 'col-1';

const _mvd = CiudadConsultable(
  campaniaCiudadId: 'cc-mvd',
  ciudadId: 'ciu-mvd',
  nombre: 'Montevideo',
  campaniaNombre: 'Verano 2026',
);
const _can = CiudadConsultable(
  campaniaCiudadId: 'cc-can',
  ciudadId: 'ciu-can',
  nombre: 'Canelones',
  campaniaNombre: 'Verano 2026',
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ReplicaDeCampanias replica;

  // «Hoy» es el 27/10/2026 al mediodía en Montevideo (15:00 UTC).
  var ahora = DateTime.utc(2026, 10, 27, 15);

  FuenteDeCiudadesParaPreciosLocal crear() => FuenteDeCiudadesParaPreciosLocal(
    CiudadesParaPreciosLocalDataSource(db),
    ahora: () => ahora,
    logger: loggerMudo(),
  );

  setUp(() {
    ahora = DateTime.utc(2026, 10, 27, 15);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
  });
  tearDown(() => db.close());

  Map<String, List<Map<String, Object?>>> catalogo() => {
    'ciudad': [
      filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9011, lon: -56.1645),
      filaCiudad('ciu-can', 'Canelones', lat: -34.5228, lon: -56.2778),
      filaCiudad('ciu-sal', 'Salto', lat: -31.38, lon: -57.96),
    ],
  };

  Map<String, Object?> zona(String id, String campaniaCiudad, {bool baja = false}) => filaZona(
    id,
    'Zona $id',
    campaniaCiudad: campaniaCiudad,
    latSur: -34.92,
    latNorte: -34.88,
    lonOeste: -56.20,
    lonEste: -56.15,
    deBaja: baja,
  );

  /// Verano 2026, en curso, con Montevideo y Canelones; [zonaAsignada] es la zona de la inscripción.
  Map<String, List<Map<String, Object?>>> verano({String? zonaAsignada}) => {
    'campania': [filaCampania('camp-1', 'Verano 2026')],
    'campania_ciudad': [
      filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
      filaCampaniaCiudad('cc-can', campania: 'camp-1', ciudad: 'ciu-can'),
    ],
    'zona': [zona('z-mvd', 'cc-mvd'), zona('z-can', 'cc-can')],
    'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1', zona: zonaAsignada)],
  };

  Future<void> bajar(Map<String, List<Map<String, Object?>>> filas, {bool pull = true}) async {
    await replica.bajar({...catalogo(), ...filas});
    if (pull) await replica.terminoUnPull();
  }

  Future<ContextoDeCiudades> leer() async {
    final r = await crear().leer(_colportor);
    return r.getOrElse(() => throw StateError('falló: $r'));
  }

  Future<void> debeNoSaber() async {
    final r = await crear().leer(_colportor);
    expect(r.isLeft(), isTrue, reason: 'no se sabe: nunca "no tenés campañas"');
    expect(r.swap().getOrElse(() => throw StateError('')), isA<FailurePreciosNoDisponibles>());
  }

  group('las ciudades de sus campañas', () {
    test(
      'Escenario básico: una campaña en curso da sus ciudades, con la campaña, por nombre',
      () async {
        await bajar(verano());

        final contexto = await leer();

        expect(contexto.ciudades, [_can, _mvd]);
        expect(contexto.ciudadDeMiZonaId, isNull);
        expect(contexto.campaniaTerminada, isNull);
      },
    );

    test('la ciudad de su zona asignada es la de esa zona', () async {
      await bajar(verano(zonaAsignada: 'z-can'));

      expect((await leer()).ciudadDeMiZonaId, 'ciu-can');
    });

    test('una zona dada de baja no cuenta: sin zona no se inventa una', () async {
      final mundo = verano(zonaAsignada: 'z-mvd');
      mundo['zona'] = [zona('z-mvd', 'cc-mvd', baja: true), zona('z-can', 'cc-can')];
      await bajar(mundo);

      expect((await leer()).ciudadDeMiZonaId, isNull);
    });

    test('una zona de otra campaña no es la de esta inscripción', () async {
      final mundo = verano(zonaAsignada: 'z-otra');
      mundo['campania'] = [
        filaCampania('camp-1', 'Verano 2026'),
        filaCampania('camp-2', 'Otoño 2026'),
      ];
      mundo['campania_ciudad'] = [
        ...mundo['campania_ciudad']!,
        filaCampaniaCiudad('cc-sal', campania: 'camp-2', ciudad: 'ciu-sal'),
      ];
      mundo['zona'] = [...mundo['zona']!, zona('z-otra', 'cc-sal')];
      await bajar(mundo);

      // La inscripción de camp-1 apunta a una zona de camp-2: dato roto, no hay ciudad de zona.
      expect((await leer()).ciudadDeMiZonaId, isNull);
    });

    test('con zonas en dos ciudades distintas no hay "la" ciudad de su zona', () async {
      final mundo = verano(zonaAsignada: 'z-mvd');
      mundo['campania'] = [
        filaCampania('camp-1', 'Verano 2026'),
        filaCampania('camp-2', 'Otoño 2026', inicio: '2026-11-01'),
      ];
      mundo['campania_ciudad'] = [
        ...mundo['campania_ciudad']!,
        filaCampaniaCiudad('cc-sal', campania: 'camp-2', ciudad: 'ciu-sal'),
      ];
      mundo['zona'] = [...mundo['zona']!, zona('z-sal', 'cc-sal')];
      mundo['campania_colportor'] = [
        filaInscripcion('insc-1', campania: 'camp-1', zona: 'z-mvd'),
        filaInscripcion('insc-2', campania: 'camp-2', zona: 'z-sal'),
      ];
      await bajar(mundo);

      final contexto = await leer();
      expect(contexto.ciudades.map((c) => c.nombre), ['Canelones', 'Montevideo', 'Salto']);
      expect(contexto.ciudadDeMiZonaId, isNull);
    });

    test('la misma ciudad en dos campañas son dos ciudades consultables', () async {
      final mundo = verano();
      mundo['campania'] = [
        filaCampania('camp-1', 'Verano 2026'),
        filaCampania('camp-2', 'Otoño 2026', inicio: '2026-11-01'),
      ];
      mundo['campania_ciudad'] = [
        filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
        filaCampaniaCiudad('cc-mvd2', campania: 'camp-2', ciudad: 'ciu-mvd'),
      ];
      mundo['campania_colportor'] = [
        filaInscripcion('insc-1', campania: 'camp-1'),
        filaInscripcion('insc-2', campania: 'camp-2'),
      ];
      await bajar(mundo);

      final contexto = await leer();
      expect(contexto.ciudades.map((c) => (c.campaniaCiudadId, c.campaniaNombre)), [
        ('cc-mvd2', 'Otoño 2026'),
        ('cc-mvd', 'Verano 2026'),
      ]);
      expect(contexto.ciudades.map((c) => c.ciudadId).toSet(), {'ciu-mvd'});
    });

    test('una campaña por empezar ya cuenta', () async {
      final mundo = verano();
      mundo['campania'] = [filaCampania('camp-1', 'Verano 2026', inicio: '2026-12-01')];
      await bajar(mundo);

      expect((await leer()).ciudades, [_can, _mvd]);
    });

    test('una campaña sin fecha de fin sigue en curso', () async {
      final mundo = verano();
      mundo['campania'] = [filaCampania('camp-1', 'Verano 2026', fin: null)];
      await bajar(mundo);

      expect((await leer()).ciudades, [_can, _mvd]);
    });

    test('lo dado de baja y lo ajeno no cuenta: inscripción, campaña, vínculo y ciudad', () async {
      final mundo = verano();
      mundo['campania'] = [
        filaCampania('camp-1', 'Verano 2026'),
        filaCampania('camp-baja', 'Campaña vieja', deBaja: true),
        filaCampania('camp-ajena', 'De otra'),
        filaCampania('camp-insc-baja', 'Me desinscribieron'),
      ];
      mundo['campania_ciudad'] = [
        filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd'),
        filaCampaniaCiudad('cc-can', campania: 'camp-1', ciudad: 'ciu-can', deBaja: true),
        filaCampaniaCiudad('cc-sal', campania: 'camp-1', ciudad: 'ciu-sal'),
        filaCampaniaCiudad('cc-ajena', campania: 'camp-ajena', ciudad: 'ciu-can'),
        filaCampaniaCiudad('cc-ib', campania: 'camp-insc-baja', ciudad: 'ciu-can'),
      ];
      mundo['ciudad'] = [
        filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9, lon: -56.16),
        filaCiudad('ciu-can', 'Canelones', lat: -34.5, lon: -56.27),
        filaCiudad('ciu-sal', 'Salto', lat: -31.38, lon: -57.96, deBaja: true),
      ];
      mundo['campania_colportor'] = [
        filaInscripcion('insc-1', campania: 'camp-1'),
        filaInscripcion('insc-baja', campania: 'camp-baja'),
        filaInscripcion('insc-ajena', campania: 'camp-ajena', usuario: 'otra-colportora'),
        filaInscripcion('insc-ib', campania: 'camp-insc-baja', deBaja: true),
      ];
      await bajar(mundo);

      expect((await leer()).ciudades, [_mvd]);
    });
  });

  group('campaña terminada (26·11)', () {
    Map<String, List<Map<String, Object?>>> terminada({String fin = '2026-10-26'}) => {
      'campania': [filaCampania('camp-1', 'Primavera 2026', fin: fin)],
      'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd')],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
    };

    test('solo una campaña que terminó: sin ciudades y con su nombre y su último día', () async {
      await bajar(terminada());

      final contexto = await leer();

      expect(contexto.ciudades, isEmpty);
      expect(
        contexto.campaniaTerminada,
        CampaniaTerminada(nombre: 'Primavera 2026', terminoEl: DateTime(2026, 10, 26)),
      );
    });

    test('el último día todavía es de la campaña; al día siguiente ya no', () async {
      await bajar(terminada(fin: '2026-10-27'));
      expect((await leer()).ciudades, [
        const CiudadConsultable(
          campaniaCiudadId: 'cc-mvd',
          ciudadId: 'ciu-mvd',
          nombre: 'Montevideo',
          campaniaNombre: 'Primavera 2026',
        ),
      ]);

      // 28/10 00:30 en Montevideo (03:30 UTC).
      ahora = DateTime.utc(2026, 10, 28, 3, 30);
      expect((await leer()).ciudades, isEmpty);
    });

    test(
      'a las 23:30 de Montevideo (02:30 UTC del día siguiente) sigue siendo el mismo día',
      () async {
        await bajar(terminada(fin: '2026-10-27'));
        ahora = DateTime.utc(2026, 10, 28, 2, 30);

        expect((await leer()).ciudades, hasLength(1));
      },
    );

    test('con una terminada y otra en curso: las ciudades son las de la vigente', () async {
      final mundo = verano();
      mundo['campania'] = [
        filaCampania('camp-1', 'Verano 2026'),
        filaCampania('camp-0', 'Invierno 2026', inicio: '2026-05-01', fin: '2026-08-31'),
      ];
      mundo['campania_ciudad'] = [
        ...mundo['campania_ciudad']!,
        filaCampaniaCiudad('cc-sal', campania: 'camp-0', ciudad: 'ciu-sal'),
      ];
      mundo['campania_colportor'] = [
        filaInscripcion('insc-1', campania: 'camp-1'),
        filaInscripcion('insc-0', campania: 'camp-0'),
      ];
      await bajar(mundo);

      final contexto = await leer();
      expect(contexto.ciudades, [_can, _mvd]);
      expect(contexto.campaniaTerminada?.nombre, 'Invierno 2026');
    });

    test('con varias terminadas informa la que terminó más tarde', () async {
      final mundo = terminada(fin: '2026-08-31');
      mundo['campania'] = [
        filaCampania('camp-1', 'Invierno 2026', fin: '2026-08-31'),
        filaCampania('camp-2', 'Primavera 2026', fin: '2026-10-15'),
      ];
      mundo['campania_colportor'] = [
        filaInscripcion('insc-1', campania: 'camp-1'),
        filaInscripcion('insc-2', campania: 'camp-2'),
      ];
      await bajar(mundo);

      expect((await leer()).campaniaTerminada?.nombre, 'Primavera 2026');
    });
  });

  group('sin campañas', () {
    test('se leyó y no está inscripta en ninguna: contexto vacío, sin campaña terminada', () async {
      await bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026')],
      });

      final contexto = await leer();

      expect(contexto.ciudades, isEmpty);
      expect(contexto.campaniaTerminada, isNull);
    });

    test('inscripta en una campaña dada de baja: vacío y sin campaña terminada', () async {
      await bajar({
        'campania': [filaCampania('camp-1', 'Verano 2026', deBaja: true)],
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });

      final contexto = await leer();
      expect(contexto.ciudades, isEmpty);
      expect(contexto.campaniaTerminada, isNull);
    });
  });

  group('"no sé" nunca se dice "no tenés" (26·10)', () {
    test('ningún pull terminó: la réplica está vacía porque no bajó', () async {
      await bajar(verano(), pull: false);

      await debeNoSaber();
    });

    test('a una inscripción le falta su campaña en la réplica', () async {
      await bajar({
        'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
      });

      await debeNoSaber();
    });

    test('a un vínculo le falta su ciudad en la réplica', () async {
      final mundo = verano();
      mundo['campania_ciudad'] = [
        filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-que-no-bajo'),
      ];
      await bajar(mundo);

      await debeNoSaber();
    });

    test('la base no se puede leer: falla de lectura, no una excepción', () async {
      await bajar(verano());
      await db.close();

      await debeNoSaber();
    });

    test('una falla a mitad de camino no deja nada trabado: leer de nuevo anda', () async {
      await bajar(verano(), pull: false);
      await debeNoSaber();

      await replica.terminoUnPull();
      expect((await leer()).ciudades, [_can, _mvd]);
    });
  });
}
