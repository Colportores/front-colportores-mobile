// El repositorio de entregas traduce todo a un Failure y no filtra datos al log (HU-VEN-002, #430).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/entrega_repository_impl.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

class _Capturador extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late _Capturador salida;
  late EntregaRepositoryImpl repo;
  var n = 0;
  String generar() => 'e-${++n}';

  setUp(() async {
    n = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    salida = _Capturador();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    repo = EntregaRepositoryImpl(
      EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas),
      logger: AppLogger(output: salida),
    );
    await sembrarCasa(db);
    await VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    ).registrar(ventaDe('v-1', talonario: 'SECRETO-77'), [itemDe('i-1', 'v-1')]);
    encolador.encolados.clear();
  });
  tearDown(() => db.close());

  test('dado una venta, cuando entrega ahora, devuelve la entrega con sus filas', () async {
    final r = await repo.entregarAhora('v-1', colportorId: 'col-1', ahora: t0, generarId: generar);

    final entrega = r.getOrElse(() => throw StateError('falló'));
    expect(entrega.entregas.single.cantidad, 3);
    expect(entrega.yaEstaba, isFalse);
  });

  test('dado una venta ausente, cuando entrega ahora, es FailureEntregaNoGuardada y se loguea sin '
      'datos', () async {
    final r = await repo.entregarAhora('v-x', colportorId: 'col-1', ahora: t0, generarId: generar);

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureEntregaNoGuardada>());
    expect(falla!.mensaje, contains('No se registró nada'));
    expect(salida.lineas.join('\n'), contains('ENTREGA_ALTA_RECHAZADA'));
  });

  test('dado una falla cualquiera, cuando entrega ahora, es «No pudimos guardar la entrega» y no '
      'filtra el dato al log ni a la falla', () async {
    encolador.fallarCon = StateError('INSERT INTO entrega ... numero_talonario = SECRETO-77');

    final r = await repo.entregarAhora('v-1', colportorId: 'col-1', ahora: t0, generarId: generar);

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureEntregaNoGuardada>());
    expect(falla!.mensaje, startsWith('No pudimos guardar la entrega en tu teléfono.'));
    expect((falla as FailureEntregaNoGuardada).causa, 'StateError');
    final todo = salida.lineas.join('\n');
    expect(todo, contains('ENTREGA_ALTA_FAIL'));
    expect(todo, isNot(contains('SECRETO-77')));
    expect('$falla', isNot(contains('SECRETO-77')));
  });

  test('dado que falló, cuando se reintenta, entrega una sola vez', () async {
    encolador.fallarCon = StateError('motor apagado');
    final fallo = await repo.entregarAhora(
      'v-1',
      colportorId: 'col-1',
      ahora: t0,
      generarId: generar,
    );
    expect(fallo.isLeft(), isTrue);
    encolador.fallarCon = null;

    final primero = await repo.entregarAhora(
      'v-1',
      colportorId: 'col-1',
      ahora: t0,
      generarId: generar,
    );
    final segundo = await repo.entregarAhora(
      'v-1',
      colportorId: 'col-1',
      ahora: t0,
      generarId: generar,
    );

    expect(primero.isRight(), isTrue);
    expect(segundo.getOrElse(() => throw StateError('falló')).yaEstaba, isTrue);
    expect(await db.select(db.entregas).get(), hasLength(1));
  });

  test('dado una venta sin entregas, cuando se lee, es una lista vacía', () async {
    final r = await repo.deLaVenta('v-1');

    expect(r.getOrElse(() => throw StateError('falló')), isEmpty);
  });

  test('dado que la base no se puede leer, cuando se lee, es FailureEntregaNoDisponible y no «nada '
      'entregado»', () async {
    await db.close();

    final r = await repo.deLaVenta('v-1');

    final falla = r.fold((f) => f, (_) => null);
    expect(falla, isA<FailureEntregaNoDisponible>());
    expect(falla!.mensaje, contains('Probá de nuevo'));
    expect(salida.lineas.join('\n'), contains('ENTREGA_LECTURA_FAIL'));
  });
}
