// QA de la tanda 6 de #537 (#626, PR #731): el tope de unidades por producto de «Entregar ahora».
// El PR hace que `entregarAhora` rechace lo que falta de un producto si pasa de 99.999
// (`EntregaCantidadInvalidaException`) y que `RegistrarVentaUseCase` no deje registrar una venta así.
// Acá se mira el borde de lo que el PR no cierra: la venta que pasa del tope por dos renglones del mismo
// producto (lo que deja «Venta crece», que valida solo lo que suma) y el borde justo en 99.999.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/entrega_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/repositories/entrega_repository_impl.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/entregar_ahora_use_case.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late EntregaRepositoryImpl repositorio;
  late VentaLocalDataSourceDrift ventas;
  var n = 0;

  setUp(() async {
    n = 0;
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    final encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    final local = EntregaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    repositorio = EntregaRepositoryImpl(
      local,
      logger: AppLogger(logger: Logger(level: Level.off)),
    );
    ventas = VentaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Future<bool> entregar(String venta) async {
    final r = await EntregarAhoraUseCase(
      repositorio,
      generarId: () => 'e-${++n}',
      ahora: () => DateTime.utc(2026, 11, 20, 12),
    )(EntregarAhoraParams(ventaId: venta, colportorId: 'col-1'));
    return r.isRight();
  }

  Future<void> vender(String id, List<VentaItem> items) async {
    final total = items.fold<int>(0, (a, i) => a + i.subtotalCentavos);
    await ventas.registrar(ventaDe(id, monto: total, talonario: 'T-$id'), items);
  }

  test(
    'dado 99.999 unidades de un producto en un solo renglón, entrega ahora las entrega',
    () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 99999, precio: 1)]);

      expect(await entregar('v-1'), isTrue);
    },
  );

  test(
    'dado 100.000 unidades de un producto en un solo renglón, entrega ahora no escribe nada',
    () async {
      await vender('v-1', [itemDe('i-1', 'v-1', cantidad: 100000, precio: 1)]);

      expect(await entregar('v-1'), isFalse);
      final filas = await db.select(db.entregas).get();
      expect(filas, isEmpty, reason: 'una entrega rechazada no deja filas a medias');
    },
  );

  test(
    'dado una venta que creció (99.999 + 1 del mismo producto en dos renglones), entrega ahora entrega',
    () async {
      await vender('v-1', [
        itemDe('i-1', 'v-1', cantidad: 99999, precio: 1),
        itemDe('i-2', 'v-1', cantidad: 1, precio: 1),
      ]);

      expect(
        await entregar('v-1'),
        isTrue,
        reason:
            '«Venta crece» deja sumar 1 a una venta con 99.999 del mismo producto y después '
            '«Entregar ahora» la rechaza para siempre, sin un aviso que diga qué hacer',
      );
    },
    skip:
        'QA #626: «Venta crece» no mira lo ya vendido del producto y «Entregar ahora» rechaza el total (> 99.999) sin salida',
  );
}
