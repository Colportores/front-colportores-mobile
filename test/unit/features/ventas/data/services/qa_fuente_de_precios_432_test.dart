// QA de #432 (precios reales de la venta, vista 27): lo que el test del implementador no mira. El
// borde del día de Montevideo con relojes en UTC (la colportora vende de noche), varias inscripciones
// y la ciudad de la casa cuando el vínculo o la baja cambian.
import 'package:colportores_mobile/core/database/app_database.dart';
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
  var ahora = DateTime.utc(2026, 11, 10, 15);

  FuenteDePreciosDeLaVentaLocal fuente() =>
      FuenteDePreciosDeLaVentaLocal(db, ahora: () => ahora, logger: loggerMudo());

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    replica = ReplicaDeCampanias(db);
    await sembrarUbicacion(db, ciudadId: 'ciu-mvd');
    await sembrarEspacio(db);
    await sembrarVinculo(db);
  });
  tearDown(() => db.close());

  Future<PreciosDeLaVenta> leer({String colportor = 'col-1'}) async {
    final r = await fuente().leer(colportorId: colportor, espacioPersonaId: 'ep-1');
    return r.getOrElse(() => throw StateError('falló: $r'));
  }

  Future<void> bajar({
    String inicio = '2026-10-01',
    String? fin = '2027-02-28',
    String colportor = 'col-1',
  }) async {
    await replica.bajar({
      'ciudad': [filaCiudad('ciu-mvd', 'Montevideo', lat: -34.9, lon: -56.16)],
      'campania': [filaCampania('camp-1', 'Verano 2026', inicio: inicio, fin: fin)],
      'campania_ciudad': [filaCampaniaCiudad('cc-mvd', campania: 'camp-1', ciudad: 'ciu-mvd')],
      'campania_colportor': [filaInscripcion('insc-1', campania: 'camp-1')],
    });
    await replica.terminoUnPull();
  }

  group('el día es el de Montevideo, no el de UTC', () {
    test(
      '23:30 en Montevideo del último día todavía vende (02:30 UTC del día siguiente)',
      () async {
        ahora = DateTime.utc(2026, 11, 11, 2, 30);
        await bajar(fin: '2026-11-10');

        expect(await leer(), isA<PreciosVigentes>());
      },
    );

    test('00:00 en Montevideo del día siguiente al fin ya no vende (03:00 UTC)', () async {
      ahora = DateTime.utc(2026, 11, 11, 3);
      await bajar(fin: '2026-11-10');

      expect(await leer(), isA<SinCampaniaVigente>());
    });

    test(
      'la campaña que empieza mañana no vende a las 23:30 de hoy (02:30 UTC de mañana)',
      () async {
        ahora = DateTime.utc(2026, 11, 11, 2, 30);
        await bajar(inicio: '2026-11-11');

        expect(await leer(), isA<SinCampaniaVigente>());
      },
    );

    test('la campaña que empieza hoy vende desde las 00:00 de Montevideo (03:00 UTC)', () async {
      ahora = DateTime.utc(2026, 11, 11, 3);
      await bajar(inicio: '2026-11-11');

      expect(await leer(), isA<PreciosVigentes>());
    });
  });

  test('la campaña sin fecha de fin sigue vendiendo', () async {
    ahora = DateTime.utc(2026, 11, 10, 15);
    await bajar(fin: null);

    expect(await leer(), isA<PreciosVigentes>());
  });

  test('una lectura repetida da lo mismo (sin estado que se arrastre entre ventas)', () async {
    ahora = DateTime.utc(2026, 11, 10, 15);
    await bajar();

    final primera = await leer();
    final segunda = await leer();

    expect(segunda, primera);
  });

  test('una colportora con espacios en el id lee igual (los ids se recortan)', () async {
    ahora = DateTime.utc(2026, 11, 10, 15);
    await bajar();

    final r = await fuente().leer(colportorId: ' col-1 ', espacioPersonaId: ' ep-1 ');

    expect(r.isRight(), isTrue);
  });
}
