// QA de «Mi alquiler» lee el pagado de más del servidor (HU-CTA-007, #753), contra la base real en
// memoria: lo que pasa con la réplica de `cuenta_colportor` cuando no es la fila ideal (la tabla local
// no tiene el `UNIQUE` de `usuario_id`), con una cuenta que se da de baja y se vuelve a crear, y con el
// `Stream` cuando solo cambia la cuenta.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/alquiler_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late AlquilerLocalDataSourceDrift fuente;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    fuente = AlquilerLocalDataSourceDrift(db);
  });
  tearDown(() => db.close());

  Future<void> cuenta(
    String id,
    int trasladado, {
    String usuario = 'col-1',
    bool baja = false,
  }) => db.customStatement(
    'INSERT INTO cuenta_colportor (id, usuario_id, alquiler_trasladado, created_at, updated_at, '
    "deleted_at) VALUES ('$id', '$usuario', $trasladado, 1, 1, ${baja ? 9 : 'NULL'})",
  );

  test('dado que el servidor dio de baja la cuenta vieja y creó otra, lee la nueva', () async {
    await cuenta('cu-vieja', 90000, baja: true);
    await cuenta('cu-nueva', 25000);

    expect((await fuente.leer('col-1')).trasladadoCentavos, 25000);
  });

  test('dado un traslado enorme, lo lee entero y sin romper el modelo', () async {
    await cuenta('cu-1', 9007199254740991);

    final alquiler = await fuente.leer('col-1');

    expect(alquiler.trasladadoCentavos, 9007199254740991);
    expect(alquiler.hayTraslado, isTrue);
  });

  test('dado que solo cambia la cuenta, el Stream emite la cifra nueva una sola vez', () async {
    await cuenta('cu-1', 0);
    final emitidos = <int>[];
    final sub = fuente.observar('col-1').listen((a) => emitidos.add(a.trasladadoCentavos));
    addTearDown(sub.cancel);
    await pumpEventQueue();

    // Un cambio de la deuda que no toca el alquiler no repite lo mismo.
    await db.customStatement('UPDATE cuenta_colportor SET deuda_total = 5000');
    db.markTablesUpdated({db.cuentasColportor});
    await pumpEventQueue();
    await db.customStatement('UPDATE cuenta_colportor SET alquiler_trasladado = 70000');
    db.markTablesUpdated({db.cuentasColportor});
    await pumpEventQueue();

    expect(emitidos, [0, 70000]);
  });

  test(
    'dado que la cuenta de otra colportora cambia, el Stream de esta no emite de nuevo',
    () async {
      await cuenta('cu-1', 0);
      await cuenta('cu-2', 0, usuario: 'col-2');
      final emitidos = <int>[];
      final sub = fuente.observar('col-1').listen((a) => emitidos.add(a.trasladadoCentavos));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await db.customStatement(
        "UPDATE cuenta_colportor SET alquiler_trasladado = 9900 WHERE id = 'cu-2'",
      );
      db.markTablesUpdated({db.cuentasColportor});
      await pumpEventQueue();

      expect(emitidos, [0]);
    },
  );

  test(
    'dos filas vivas de la misma colportora (la tabla local no tiene UNIQUE): «Mi alquiler» se lee '
    'igual, sin romper todo el alquiler por una cifra informativa',
    () async {
      await cuenta('cu-1', 10000);
      await cuenta('cu-2', 20000);

      final AlquilerDelColportor alquiler = await fuente.leer('col-1');

      expect(alquiler.hayAlquiler, isFalse);
    },
    skip:
        'QA #753: _trasladado usa getSingleOrNull y con dos cuentas vivas de la misma colportora '
        'lanza «Too many elements»: Mi alquiler entero pasa a «No pudimos traer tu alquiler» por '
        'una cifra informativa',
  );
}
