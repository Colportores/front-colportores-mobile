import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/models/venta_model.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/venta_repository_impl.dart';
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
  late VentaRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    salida = _Capturador();
    repo = VentaRepositoryImpl(
      VentaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      ),
      logger: AppLogger(output: salida),
    );
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  test('guarda y devuelve la venta con sus ítems', () async {
    final r = await repo.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);

    final guardada = r.getOrElse(() => throw StateError('falló'));
    expect(guardada.venta.id, 'v-1');
    expect(guardada.items.single.id, 'i-1');
  });

  test(
    'un talonario repetido es FailureTalonarioRepetido con el texto del canvas (27A·11)',
    () async {
      await repo.registrar(ventaDe('v-1', talonario: '0042'), [itemDe('i-1', 'v-1')]);

      final r = await repo.registrar(
        ventaDe('v-2', talonario: '0042', fecha: t0.add(const Duration(days: 1))),
        [itemDe('i-2', 'v-2')],
      );

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureTalonarioRepetido>());
      expect(
        falla!.mensaje,
        'Ya usaste el talonario 0042 este año (venta del 23/10). Revisá el número.',
      );
    },
  );

  test('la persona ausente es un FailureValidacion del campo persona', () async {
    final r = await repo.registrar(ventaDe('v-1', vinculo: 'ep-x'), [itemDe('i-1', 'v-1')]);

    final falla = r.fold((f) => f, (_) => null) as FailureValidacion;
    expect(falla.campos.keys, ['persona']);
  });

  test(
    'cualquier otra falla es «No pudimos guardar la venta» y no filtra el dato al log',
    () async {
      encolador.fallarCon = StateError('INSERT INTO venta ... numero_talonario = SECRETO-77');

      final r = await repo.registrar(
        ventaDe('v-1', talonario: 'SECRETO-77', motivo: 'dato del cliente'),
        [itemDe('i-1', 'v-1')],
      );

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureVentaNoGuardada>());
      expect(falla!.mensaje, startsWith('No pudimos guardar la venta en tu teléfono.'));
      final todo = salida.lineas.join('\n');
      expect(todo, contains('VENTA_ALTA_FAIL'));
      expect(todo, isNot(contains('SECRETO-77')));
      expect(todo, isNot(contains('dato del cliente')));
      expect('$falla', isNot(contains('SECRETO-77')));
    },
  );

  test('tras una falla se puede reintentar y la venta entra una sola vez', () async {
    encolador.fallarCon = StateError('motor apagado');
    final fallo = await repo.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);
    expect(fallo.isLeft(), isTrue);

    encolador.fallarCon = null;
    final primero = await repo.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);
    final segundo = await repo.registrar(ventaDe('v-1'), [itemDe('i-1', 'v-1')]);

    expect(primero.isRight(), isTrue);
    expect(segundo.getOrElse(() => throw StateError('falló')).yaEstaba, isTrue);
    expect(await db.select(db.ventas).get(), hasLength(1));
  });

  test('talonarioUsado devuelve la venta que lo tiene, o null', () async {
    await repo.registrar(ventaDe('v-1', talonario: '0042'), [itemDe('i-1', 'v-1')]);

    final usado = await repo.talonarioUsado(colportorId: 'col-1', numero: '0042', fecha: t0);
    final libre = await repo.talonarioUsado(colportorId: 'col-1', numero: '0001', fecha: t0);

    expect(usado.getOrElse(() => null)!.ventaId, 'v-1');
    expect(libre.getOrElse(() => throw StateError('falló')), isNull);
  });

  group('lo que sube (VentaModel)', () {
    test(
      'las claves de venta y venta_item son exactamente las columnas de la tabla local',
      () async {
        final columnasVenta = db.ventas.$columns.map((c) => c.name).toSet();
        final columnasItem = db.ventaItems.$columns.map((c) => c.name).toSet();

        expect(VentaModel.toJson(ventaDe('v-1')).keys.toSet(), columnasVenta);
        expect(VentaItemModel.toJson(itemDe('i-1', 'v-1')).keys.toSet(), columnasItem);
      },
    );

    test('el JSON de una venta con un combo vuelve igual desde la fila local', () async {
      await repo.registrar(ventaDe('v-1', motivo: 'm'), [itemDe('i-1', 'v-1')]);
      final guardada = (await repo.registrar(ventaDe('v-1'), [
        itemDe('i-1', 'v-1'),
      ])).getOrElse(() => throw StateError('falló'));

      expect(VentaModel.toJson(guardada.venta), encolador.encolados.first.payload);
      expect(VentaItemModel.toJson(guardada.items.single), encolador.encolados[1].payload);
    });
  });
}
