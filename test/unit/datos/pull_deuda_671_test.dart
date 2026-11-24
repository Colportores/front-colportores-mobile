// La deuda con la casa editora baja con la sincronización (#671; backend-supabase 0179, #254) de punta a
// punta, con el código real de los dos lados de la frontera: el motor baja el delta de un servidor falso,
// lo que baja entra por `DriftLocalStore` a las tablas de la app y el repositorio cuenta la deuda con ellas.
//
// Los casos son los de `supabase/tests/0179_…` de backend-supabase (los de #235 calculados sobre lo que
// baja): el resultado esperado de cada colportora es el mismo texto que ahí compara contra
// `mi_deuda_con_la_casa_editora()`, que es la referencia.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/deuda_con_la_casa_local_data_source.dart';
import 'package:colportores_mobile/features/cuenta/data/repositories/deuda_con_la_casa_repository_impl.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

/// «Hoy» de los tests: los historiales se cuentan hacia atrás desde acá.
final _ahora = DateTime.utc(2026, 11, 12, 12);

String _iso(DateTime t) => t.toUtc().toIso8601String().replaceFirst('Z', '+00:00');

Map<String, Object?> _auditoria([int version = 1]) => {
  'created_at': '2026-10-01T10:00:00+00:00',
  'updated_at': '2026-10-01T10:00:00+00:00',
  'created_by': null,
  'deleted_at': null,
  'sync_version': version,
};

// Las filas, como las arma `sync.pull` con las columnas de cada tabla del servidor.
Map<String, Object?> _cuenta(String usuario, int deuda, {bool deBaja = false}) => {
  'id': 'cu-$usuario',
  'usuario_id': usuario,
  'deuda_total': deuda,
  'dinero_depositado': 0,
  'dinero_en_mano': 0,
  'dinero_por_cobrar': 0,
  'deuda_alquiler': 0,
  'alquiler_trasladado': 0,
  'actualizado_en': '2026-10-01T10:00:00+00:00',
  ..._auditoria(),
  if (deBaja) 'deleted_at': '2026-11-01T10:00:00+00:00',
  'xmin_w': '1',
};

Map<String, Object?> _historial(String id, String usuario, int deuda, Duration haceCuanto) => {
  'id': id,
  'usuario_id': usuario,
  'deuda': deuda,
  'desde': _iso(_ahora.subtract(haceCuanto)),
  ..._auditoria(),
  'xmin_w': '1',
};

Map<String, Object?> _pedido(
  String id,
  String usuario,
  String estado,
  int total, {
  int? autorizado,
  required int numero,
  required String fecha,
  String origen = 'COLPORTOR',
  bool deBaja = false,
}) => {
  'id': id,
  'colportor_id': usuario,
  'coordinador_id': null,
  'fecha_pedido': fecha,
  'estado': estado,
  'monto_total': total,
  'origen': origen,
  'excede_limite': false,
  'monto_autorizado': autorizado,
  'decidido_por': null,
  'decidido_en': null,
  'motivo_rechazo': null,
  'numero': numero,
  ..._auditoria(),
  if (deBaja) 'deleted_at': '2026-11-01T10:00:00+00:00',
  'xmin_w': '1',
};

Map<String, Object?> _linea(
  String pedido,
  String usuario,
  String producto,
  int cantidad, {
  int? autorizada,
  bool deBaja = false,
}) => {
  'id': 'li-$pedido-$producto',
  'pedido_id': pedido,
  'producto_id': producto,
  'cantidad': cantidad,
  'precio_unitario': 1500,
  'cantidad_recibida': null,
  'colportor_id': usuario,
  'cantidad_autorizada': autorizada,
  ..._auditoria(),
  if (deBaja) 'deleted_at': '2026-11-01T10:00:00+00:00',
  'xmin_w': '1',
};

Map<String, Object?> _producto(String id, String nombre) => {
  'id': id,
  'nombre': nombre,
  'descripcion': null,
  'tipo': 'LIBRO',
  'categoria': 'ESPIRITUALES',
  'es_bonificable': true,
  'es_misionero': false,
  'precio_base_compra': 1500,
  'casa_editora': null,
  'imagen_url': null,
  ..._auditoria(),
};

Map<String, Object?> _deposito(
  String id,
  int monto, {
  String? validadoEn,
  String concepto = 'CASA_EDITORA',
  String? rechazadoEn,
  bool deBaja = false,
}) => {
  'id': id,
  'colportor_id': 'col-1',
  'monto': monto,
  'fecha': '2026-10-10T12:00:00+00:00',
  'destino': 'RETIRO_COORDINADOR',
  'concepto': concepto,
  // El alquiler siempre es de una campaña (CHECK del servidor y de la tabla local).
  'campania_id': concepto == 'ALQUILER' ? 'camp-1' : null,
  'ticket_id': null,
  'validado_en': validadoEn,
  'validado_por': validadoEn == null ? null : 'coord-1',
  'rechazado_en': rechazadoEn,
  'rechazado_por': rechazadoEn == null ? null : 'coord-1',
  'motivo_rechazo': rechazadoEn == null ? null : 'No llegó el efectivo',
  ..._auditoria(),
  if (deBaja) 'deleted_at': '2026-11-01T10:00:00+00:00',
};

Map<String, Object?> _ticket(String id, String tipo, String estado, int monto) => {
  'id': id,
  'usuario_id': 'col-1',
  'tipo': tipo,
  'url_cloud': null,
  'subido_en': null,
  'revisado_por': null,
  'revisado_en': null,
  'monto': monto,
  'fecha': '2026-10-12T12:00:00+00:00',
  'numero_autorizacion': null,
  'tarjeta_tipo': null,
  'tarjeta_marca': null,
  'estado': estado,
  'motivo_rechazo': null,
  'campania_validadora_id': null,
  ..._auditoria(),
};

/// «deuda|hace 7 días|suma de saldos|depósitos|pedidos», el mismo formato de `supabase/tests/0179_…`
/// (sin las tarjetas): cada pedido «sufijo:monto/pagado/saldo[líneas]», del más viejo al más nuevo.
String _texto(DeudaConLaCasa d) {
  final pedidos = d.pedidos.isEmpty
      ? '-'
      : d.pedidos
            .map(
              (p) =>
                  '${p.pedidoId}:${p.montoCentavos}/${p.pagadoCentavos}/${p.saldoCentavos}'
                  '[${p.lineas.map((l) => '${l.nombre} x${l.cantidad}').join(', ')}]',
            )
            .join(', ');
  return '${d.deudaTotalCentavos}|${d.deudaHace7DiasCentavos ?? 'n'}|${d.sumaDeSaldosCentavos}|'
      '${d.depositosValidadosCentavos}|$pedidos';
}

/// Una lectura que falla, como una base que no se puede abrir.
final class _BaseIlegible implements DeudaConLaCasaLocalDataSource {
  @override
  Stream<void> get cambios => const Stream.empty();

  @override
  Future<BajadaDeLaDeuda?> leer(String colportorId) => Future.error(StateError('base ilegible'));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeConnectivityPort red;
  late SyncEngine motor;
  late DeudaConLaCasaRepositoryImpl repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    red = FakeConnectivityPort();
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
      meta: DriftSyncMeta(db),
      connectivity: red,
    );
    repo = DeudaConLaCasaRepositoryImpl(
      DeudaConLaCasaLocalDrift(db),
      ahora: () => _ahora,
      logger: loggerMudo(),
    );
  });
  tearDown(() async {
    await motor.dispose();
    await red.dispose();
    await db.close();
  });

  /// Lo que contaría el teléfono de [usuario] tras sincronizar: el texto de la deuda.
  Future<String> deudaDe(String usuario) async {
    final lectura = (await repo.leer(usuario)).getOrElse(() => null);
    expect(lectura, isNotNull, reason: 'ya sincronizó: tiene que haber lectura');
    return _texto(lectura!.deuda);
  }

  group('el catálogo del motor', () {
    test('la cuenta y su historial son réplicas de solo lectura, sin Realtime', () {
      for (final entidad in ['cuenta_colportor', 'cuenta_deuda_historial']) {
        final spec = specsDeLaApp.singleWhere((s) => s.entity == entidad);
        expect(spec.policy, SyncPolicy.pull, reason: entidad);
        expect(spec.realtime, isFalse, reason: entidad);
        expect(entidadesQueEscribeElMotor, contains(entidad));
        expect(entidadesDelBackup, isNot(contains(entidad)), reason: 'el pull la reconstruye');
      }
    });

    test(
      'el pedido y sus líneas son push con pull de lo propio, el pedido antes que sus líneas',
      () {
        final pedido = specsDeLaApp.singleWhere((s) => s.entity == 'pedido_casa_editora');
        final linea = specsDeLaApp.singleWhere((s) => s.entity == 'pedido_item');
        for (final spec in [pedido, linea]) {
          expect(spec.policy, SyncPolicy.push);
          expect(spec.alsoPull, isTrue);
        }
        expect(specsDeLaApp.indexOf(pedido), lessThan(specsDeLaApp.indexOf(linea)));
      },
    );

    test(
      'las tablas tienen la forma del cloud: toda columna local viene en la fila del servidor',
      () {
        final filas = {
          'cuenta_colportor': _cuenta('col-1', 0),
          'cuenta_deuda_historial': _historial('h-1', 'col-1', 0, Duration.zero),
          'pedido_casa_editora': _pedido(
            'p-1',
            'col-1',
            'AUTORIZADO',
            0,
            numero: 1,
            fecha: '2026-10-01T10:00:00+00:00',
          ),
          'pedido_item': _linea('p-1', 'col-1', 'pro-1', 1),
        };
        for (final e in filas.entries) {
          final tabla = db.allTables.singleWhere((t) => t.actualTableName == e.key);
          final locales = tabla.$columns.map((c) => c.name).toSet();
          expect(e.value.keys.toSet().containsAll(locales), isTrue, reason: 'faltan en ${e.key}');
          expect(e.value.keys.toSet().difference(locales), {'xmin_w'}, reason: e.key);
        }
      },
    );
  });

  group('sin haber sincronizado nunca', () {
    test('no sabe nada de la deuda: Right(null), no «no debés nada»', () async {
      expect(await repo.leer('col-1'), const Right<Failure, LecturaDeLaDeuda?>(null));
    });

    test('con filas pero sin hora de bajada tampoco afirma nada', () async {
      await db.customStatement(
        'INSERT INTO cuenta_colportor (id, usuario_id, deuda_total, created_at, updated_at) '
        "VALUES ('cu-1', 'col-1', 500, 1, 1)",
      );
      expect(await repo.leer('col-1'), const Right<Failure, LecturaDeLaDeuda?>(null));
    });

    test('una base ilegible es FailureDeudaNoDisponible, nunca un cero', () async {
      final rota = DeudaConLaCasaRepositoryImpl(
        _BaseIlegible(),
        ahora: () => _ahora,
        logger: loggerMudo(),
      );

      final r = await rota.leer('col-1');

      expect(
        r.swap().getOrElse(() => throw StateError('debía fallar')),
        isA<FailureDeudaNoDisponible>(),
      );
    });
  });

  group('colportora con pedidos y pagos (b1 de supabase/tests/0179)', () {
    setUp(() {
      servidor
        ..seed('cuenta_colportor', [_cuenta('col-1', 1500000)])
        ..seed('cuenta_deuda_historial', [
          _historial('h-1', 'col-1', 1500000, const Duration(days: 3)),
          _historial('h-2', 'col-1', 900000, const Duration(days: 10)),
        ])
        ..seed('pedido_casa_editora', [
          _pedido(
            'a1',
            'col-1',
            'AUTORIZADO',
            2600000,
            autorizado: 1400000,
            numero: 1,
            fecha: '2026-10-02T10:00:00+00:00',
          ),
          _pedido(
            'a2',
            'col-1',
            'DESPACHADO',
            1000000,
            autorizado: 1000000,
            numero: 2,
            fecha: '2026-10-15T10:00:00+00:00',
          ),
          _pedido(
            'a3',
            'col-1',
            'AUTORIZADO',
            500000,
            numero: 3,
            fecha: '2026-10-15T10:00:00+00:00',
            origen: 'COORDINADOR',
          ),
          _pedido(
            'a4',
            'col-1',
            'RECIBIDO',
            300000,
            autorizado: 300000,
            numero: 4,
            fecha: '2026-10-20T10:00:00+00:00',
          ),
          // No cargan la deuda: por autorizar, rechazado, cancelado, borrador y uno dado de baja.
          _pedido(
            'a5',
            'col-1',
            'PENDIENTE_AUTORIZACION',
            700000,
            numero: 5,
            fecha: '2026-10-01T10:00:00+00:00',
          ),
          _pedido(
            'a6',
            'col-1',
            'RECHAZADO',
            300000,
            numero: 6,
            fecha: '2026-10-01T11:00:00+00:00',
          ),
          _pedido(
            'a7',
            'col-1',
            'CANCELADO',
            100000,
            numero: 7,
            fecha: '2026-10-01T12:00:00+00:00',
          ),
          _pedido(
            'a8',
            'col-1',
            'BORRADOR',
            200000,
            numero: 8,
            fecha: '2026-10-01T13:00:00+00:00',
            origen: 'COORDINADOR',
          ),
          _pedido(
            'a9',
            'col-1',
            'AUTORIZADO',
            900000,
            autorizado: 900000,
            numero: 9,
            fecha: '2026-10-01T14:00:00+00:00',
            deBaja: true,
          ),
        ])
        ..seed('deposito', [
          _deposito('d-1', 1200000, validadoEn: '2026-10-11T12:00:00+00:00'),
          _deposito('d-2', 900000, validadoEn: '2026-10-18T12:00:00+00:00'),
          // No pagan: por validar, rechazado, validado pero dado de baja y uno de otro concepto.
          _deposito('d-3', 500000),
          _deposito('d-4', 300000, rechazadoEn: '2026-10-21T08:00:00+00:00'),
          _deposito('d-5', 100000, validadoEn: '2026-10-25T12:00:00+00:00', deBaja: true),
          _deposito('d-6', 800000, validadoEn: '2026-10-26T12:00:00+00:00', concepto: 'ALQUILER'),
        ])
        ..seed('ticket', [
          _ticket('t-1', 'COBRO_TARJETA', 'VALIDADO', 200000),
          _ticket('t-2', 'COBRO_TARJETA', 'PENDIENTE', 700000),
          _ticket('t-3', 'COBRO_TARJETA', 'RECHAZADO', 300000),
          _ticket('t-4', 'DEPOSITO', 'VALIDADO', 900000),
        ]);
    });

    test('23000 pagados (21000 en depósitos y 2000 de tarjeta): el reparto del servidor', () async {
      final r = await motor.syncNow();
      expect(r.ok, isTrue);

      expect(
        await deudaDe('col-1'),
        '1500000|900000|900000|2100000|a2:1000000/900000/100000[], a3:500000/0/500000[], a4:300000/0/300000[]',
      );
    });

    test('la hora de lo que muestra es la de la última bajada', () async {
      await motor.syncNow();

      final lectura = (await repo.leer('col-1')).getOrElse(() => null)!;
      final bajada = (await DriftSyncMeta(db).read()).lastPullAt!;
      expect(lectura.leidaEn, bajada.toUtc());
    });

    test(
      'otro depósito validado y el que estaba por validar: cubren todo y no se lista ningún pedido',
      () async {
        await motor.syncNow();
        servidor.seed('deposito', [
          {..._deposito('d-3', 500000, validadoEn: '2026-10-28T12:00:00+00:00'), 'sync_version': 2},
          _deposito('d-7', 400000, validadoEn: '2026-10-27T12:00:00+00:00'),
        ]);
        await motor.syncNow();

        expect(await deudaDe('col-1'), '1500000|900000|0|3000000|-');
      },
    );

    test('la cuenta cambia (el servidor movió la deuda) y el delta lo trae', () async {
      await motor.syncNow();
      servidor.seed('cuenta_colportor', [
        {..._cuenta('col-1', 1200000), 'sync_version': 2},
      ]);
      await motor.syncNow();

      expect((await deudaDe('col-1')).startsWith('1200000|'), isTrue);
    });

    test('cambiar de cuenta en el mismo teléfono no mezcla la cuenta ni los pedidos', () async {
      await motor.syncNow();

      final otra = (await repo.leer('col-2')).getOrElse(() => null)!.deuda;
      expect(otra.deudaTotalCentavos, 0, reason: 'sin cuenta no debe nada');
      expect(otra.pedidos, isEmpty);
      expect(otra.deudaHace7DiasCentavos, isNull);
    });
  });

  group('los otros casos del servidor', () {
    test('pagó de más: la deuda queda a favor y no se lista el pedido (b3)', () async {
      servidor
        ..seed('cuenta_colportor', [_cuenta('b3', -50000)])
        ..seed('pedido_casa_editora', [
          _pedido(
            'b3',
            'b3',
            'RECIBIDO',
            400000,
            autorizado: 400000,
            numero: 1,
            fecha: '2026-10-05T10:00:00+00:00',
          ),
        ])
        ..seed('deposito', [_deposito('d-1', 450000, validadoEn: '2026-10-13T12:00:00+00:00')]);
      await motor.syncNow();

      expect(await deudaDe('b3'), '-50000|n|0|450000|-');
    });

    test('una cuenta dada de baja no debe nada (b4)', () async {
      servidor.seed('cuenta_colportor', [_cuenta('b4', 77700, deBaja: true)]);
      await motor.syncNow();

      expect(await deudaDe('b4'), '0|n|0|0|-');
    });

    test('sin cuenta el total es 0 y el pedido sale con su saldo (b2)', () async {
      servidor
        ..seed('pedido_casa_editora', [
          _pedido(
            'b2',
            'b2',
            'AUTORIZADO',
            800000,
            autorizado: 800000,
            numero: 1,
            fecha: '2026-10-05T10:00:00+00:00',
          ),
        ])
        ..seed('deposito', [_deposito('d-1', 200000, validadoEn: '2026-10-13T12:00:00+00:00')]);
      await motor.syncNow();

      expect(await deudaDe('b2'), '0|n|600000|200000|b2:800000/200000/600000[]');
    });

    test(
      'las líneas: cantidad autorizada, sin las de cero ni las de baja, por nombre (b7)',
      () async {
        servidor
          ..seed('producto', [
            _producto('p-91', 'Libro Uno 179'),
            _producto('p-92', 'Libro Dos 179'),
            _producto('p-93', 'Revista Uno 179'),
          ])
          ..seed('pedido_casa_editora', [
            _pedido(
              'd1',
              'b7',
              'AUTORIZADO',
              2600000,
              autorizado: 1400000,
              numero: 1,
              fecha: '2026-10-02T10:00:00+00:00',
            ),
            _pedido(
              'd2',
              'b7',
              'DESPACHADO',
              1000000,
              autorizado: 1000000,
              numero: 2,
              fecha: '2026-10-15T10:00:00+00:00',
            ),
            _pedido(
              'd3',
              'b7',
              'AUTORIZADO',
              500000,
              numero: 3,
              fecha: '2026-10-15T10:00:00+00:00',
              origen: 'COORDINADOR',
            ),
            _pedido(
              'd4',
              'b7',
              'RECIBIDO',
              300000,
              autorizado: 300000,
              numero: 4,
              fecha: '2026-10-20T10:00:00+00:00',
            ),
          ])
          ..seed('pedido_item', [
            _linea('d1', 'b7', 'p-92', 4, autorizada: 2),
            _linea('d1', 'b7', 'p-93', 5, autorizada: 0),
            _linea('d1', 'b7', 'p-91', 10, autorizada: 6),
            _linea('d2', 'b7', 'p-92', 4),
            _linea('d2', 'b7', 'p-91', 3, deBaja: true),
            _linea('d3', 'b7', 'p-93', 25),
            _linea('d4', 'b7', 'p-91', 2),
            // Un producto que todavía no bajó: la línea no se lista (como el join de la RPC).
            _linea('d4', 'b7', 'p-sin-bajar', 9),
          ]);
        await motor.syncNow();

        expect(
          await deudaDe('b7'),
          '0|n|3200000|0|d1:1400000/0/1400000[Libro Dos 179 x2, Libro Uno 179 x6], '
          'd2:1000000/0/1000000[Libro Dos 179 x4], d3:500000/0/500000[Revista Uno 179 x25], '
          'd4:300000/0/300000[Libro Uno 179 x2]',
        );
      },
    );
  });

  group('el aviso de cambios', () {
    test(
      'cuando la sincronización trae algo que la cuenta usa, avisa para volver a leer',
      () async {
        final avisos = <void>[];
        final sub = repo.cambios.listen(avisos.add);
        addTearDown(sub.cancel);

        servidor.seed('cuenta_colportor', [_cuenta('col-1', 1000)]);
        await motor.syncNow();
        await Future<void>.delayed(Duration.zero);

        expect(avisos, isNotEmpty);
      },
    );
  });
}
