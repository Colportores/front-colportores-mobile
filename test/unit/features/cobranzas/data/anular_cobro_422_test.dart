// Anular un cobro contra las tablas reales (HU-COB-006, #422): AppDatabase en memoria, mismo esquema y
// mismos CHECK que en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/models/cobranza_model.dart';
import 'package:colportores_mobile/features/cobranzas/data/repositories/anulacion_de_cobro_repository_impl.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/audit_log_table.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/venta_falsos.dart';

Cobranza cobroDe(String id, int monto, {DateTime? fecha, MedioCobranza? medio}) => Cobranza(
  id: id,
  ventaId: 'v-1',
  montoCentavos: monto,
  medio: medio ?? MedioCobranza.efectivo,
  fecha: fecha ?? t0,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift local;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    await sembrarCasa(db);
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(
            id: 'per-1',
            nombre: 'María',
            apellido: const Value('Fernández'),
            createdAt: t0,
            updatedAt: t0,
          ),
        );
    await VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: casas,
    ).registrar(ventaDe('v-1', monto: 150000), [itemDe('i-1', 'v-1', cantidad: 1, precio: 150000)]);
    await local.registrar(cobroDe('c-1', 60000));
    encolador.encolados.clear();
  });
  tearDown(() => db.close());

  Future<CobranzaFila> fila([String id = 'c-1']) =>
      (db.select(db.cobranzas)..where((c) => c.id.equals(id))).getSingle();
  Future<List<AuditLogFila>> auditoria() => db.select(db.auditLogLocal).get();

  Future<AnulacionHecha> anular({
    String id = 'c-1',
    MotivoDeAnulacion motivo = MotivoDeAnulacion.montoEquivocado,
    String colportor = 'col-1',
    DateTime? ahora,
    String? justificacion,
  }) => local.anular(
    cobranzaId: id,
    motivo: motivo,
    colportorId: colportor,
    ahora: ahora ?? t0.add(const Duration(hours: 1)),
    justificacion: justificacion,
  );

  group('anular', () {
    test(
      'marca el cobro con la hora del teléfono y el motivo, y el saldo de la venta vuelve',
      () async {
        expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 90000);
        final hora = t0.add(const Duration(hours: 1));

        final r = await anular(ahora: hora);

        expect(r.yaEstaba, isFalse);
        final f = await fila();
        expect(f.anuladoAt, hora);
        expect(f.motivoAnulacion, 'Monto equivocado');
        expect(f.updatedAt, hora);
        expect(f.deletedAt, isNull, reason: 'anular no es dar de baja');
        expect(r.detalle.cobranza.estaAnulado, isTrue);
        expect(r.detalle.venta.saldoCentavos, 150000);
        expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 150000);
      },
    );

    test('encola el cobro entero como update con la marca y el motivo de la lista', () async {
      await anular(motivo: MotivoDeAnulacion.registreDosVeces);

      final c = encolador.encolados.single;
      expect([c.entidad, c.operacion.name], ['cobranza', 'update']);
      expect(c.payload['id'], 'c-1');
      expect(c.payload['monto'], 60000);
      expect(c.payload['anulado_at'], t0.add(const Duration(hours: 1)).toIso8601String());
      expect(c.payload['motivo_anulacion'], 'Lo registré dos veces');
    });

    test('con «Otro» sube «Otro» y lo que escribió queda solo en el audit_log local', () async {
      await anular(motivo: MotivoDeAnulacion.otro, justificacion: 'Pagó con transferencia');

      expect((await fila()).motivoAnulacion, 'Otro');
      final payload = encolador.encolados.single.payload;
      expect(payload['motivo_anulacion'], 'Otro');
      expect(payload.values.whereType<String>().any((v) => v.contains('transferencia')), isFalse);
      final log = (await auditoria()).single;
      expect(log.evento, EventoAuditoriaLocal.cobroAnulado);
      expect(log.uuid, 'c-1');
      expect(log.motivo, 'Pagó con transferencia');
      expect(log.creadoEn, t0.add(const Duration(hours: 1)));
    });

    test('con un motivo de la lista el audit_log guarda ese motivo y nunca el monto', () async {
      await anular(motivo: MotivoDeAnulacion.clienteEquivocado);

      final log = (await auditoria()).single;
      expect(log.motivo, 'Cliente equivocado');
      expect('${log.evento}${log.uuid}${log.motivo}', isNot(contains('600')));
    });

    test('recalcula el color de la casa en la misma transacción', () async {
      await db.delete(db.houseStatuses).go();

      await anular();

      expect(await db.select(db.houseStatuses).get(), hasLength(1));
    });

    test('un segundo toque o un reintento no escribe ni encola nada y dice lo mismo', () async {
      await anular();
      encolador.encolados.clear();
      final antes = await fila();

      final r = await anular(
        motivo: MotivoDeAnulacion.otro,
        justificacion: 'otra cosa',
        ahora: t0.add(const Duration(hours: 2)),
      );

      expect(r.yaEstaba, isTrue);
      expect(await fila(), antes);
      expect(encolador.encolados, isEmpty);
      expect(await auditoria(), hasLength(1));
    });

    test('un reintento se acepta aunque la ventana ya haya pasado', () async {
      await anular();

      final r = await anular(ahora: t0.add(const Duration(days: 10)));

      expect(r.yaEstaba, isTrue);
    });

    test('la ventana es de 72 h desde el cobro, inclusive', () async {
      final r = await anular(ahora: t0.add(const Duration(hours: 72)));

      expect(r.detalle.cobranza.estaAnulado, isTrue);
    });

    test('pasadas las 72 h no anula nada: ni marca, ni cola, ni audit_log, ni saldo', () async {
      await expectLater(
        anular(ahora: t0.add(const Duration(hours: 72, seconds: 1))),
        throwsA(isA<AnulacionFueraDePlazoException>()),
      );

      expect((await fila()).anuladoAt, isNull);
      expect(encolador.encolados, isEmpty);
      expect(await auditoria(), isEmpty);
      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 90000);
    });

    test('la ventana corre desde la fecha del cobro, no desde cuando se cargó', () async {
      // Un cobro con fecha una hora después del primero: su ventana corre desde su propia fecha.
      await local.registrar(cobroDe('c-2', 1000, fecha: t0.add(const Duration(hours: 1))));
      encolador.encolados.clear();

      await expectLater(
        anular(id: 'c-2', ahora: t0.add(const Duration(hours: 73, minutes: 1))),
        throwsA(isA<AnulacionFueraDePlazoException>()),
      );
    });

    test('un cobro que no está, uno dado de baja o uno de otra cuenta no se anulan', () async {
      await expectLater(anular(id: 'nada'), throwsA(isA<CobroAusenteException>()));
      await expectLater(anular(colportor: 'col-2'), throwsA(isA<CobroAusenteException>()));
      await db.customStatement('UPDATE cobranza SET deleted_at = 1 WHERE id = ?', ['c-1']);
      await expectLater(anular(), throwsA(isA<CobroAusenteException>()));

      expect(encolador.encolados, isEmpty);
    });

    test('si el encolado falla se revierte todo: el cobro sigue vigente y sin audit_log', () async {
      encolador.fallarCon = StateError('cola');

      await expectLater(anular(), throwsA(isA<StateError>()));

      final f = await fila();
      expect([f.anuladoAt, f.motivoAnulacion], [null, null]);
      expect(await auditoria(), isEmpty);
      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 90000);
      encolador.fallarCon = null;
      await anular();
      expect((await fila()).anuladoAt, isNotNull);
    });

    test('un cobro anulado no cuenta para el saldo de la persona ni el total', () async {
      await anular();

      expect(await local.saldosPorPersona(['per-1']), {'per-1': 150000});
    });

    test('dos cobros: anular uno deja el otro contando', () async {
      await local.registrar(cobroDe('c-2', 30000));
      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 60000);

      await anular();

      expect((await local.ventaConSaldo('v-1'))!.saldoCentavos, 120000);
    });
  });

  group('detalle', () {
    test('trae el cobro, la venta con su saldo y el nombre del cliente', () async {
      final d = (await local.detalle('c-1'))!;

      expect(d.cobranza.id, 'c-1');
      expect(d.cobranza.montoCentavos, 60000);
      expect(d.venta.numeroTalonario, 'T-100');
      expect(d.venta.saldoCentavos, 90000);
      expect(d.cliente, 'María Fernández');
      expect(d.puedeAnularseHasta, t0.add(const Duration(hours: 72)));
      expect(d.dentroDelPlazo(t0.add(const Duration(hours: 72))), isTrue);
      expect(d.dentroDelPlazo(t0.add(const Duration(hours: 72, milliseconds: 1))), isFalse);
    });

    test('un cobro anulado se lee anulado, con su motivo', () async {
      await anular(motivo: MotivoDeAnulacion.clienteEquivocado);

      final d = (await local.detalle('c-1'))!;

      expect(d.cobranza.motivoAnulacion, MotivoDeAnulacion.clienteEquivocado);
      expect(d.cobranza.anuladoAt, t0.add(const Duration(hours: 1)));
    });

    test('un cobro que no está o está dado de baja es null', () async {
      expect(await local.detalle('nada'), isNull);
      await db.customStatement('UPDATE cobranza SET deleted_at = 1 WHERE id = ?', ['c-1']);
      expect(await local.detalle('c-1'), isNull);
    });
  });

  group('repositorio', () {
    test('traduce cada rechazo a su falla y nunca lanza', () async {
      final repo = AnulacionDeCobroRepositoryImpl(local, logger: loggerMudo());

      final fuera = await repo.anular(
        cobranzaId: 'c-1',
        motivo: MotivoDeAnulacion.montoEquivocado,
        colportorId: 'col-1',
        ahora: t0.add(const Duration(days: 5)),
      );
      final ausente = await repo.anular(
        cobranzaId: 'nada',
        motivo: MotivoDeAnulacion.montoEquivocado,
        colportorId: 'col-1',
        ahora: t0,
      );
      encolador.fallarCon = StateError('cola');
      final falla = await repo.anular(
        cobranzaId: 'c-1',
        motivo: MotivoDeAnulacion.montoEquivocado,
        colportorId: 'col-1',
        ahora: t0,
      );

      expect(fuera.fold((f) => f.codigo, (_) => ''), 'COBRO_ANULACION_FUERA_DE_PLAZO');
      expect(ausente.fold((f) => f.codigo, (_) => ''), 'COBRO_AUSENTE');
      expect(falla.fold((f) => f.codigo, (_) => ''), 'COBRO_NO_ANULADO');
    });
  });

  group('modelo', () {
    test('un cobro vigente sube sin marca y uno anulado sube con ella', () {
      final vigente = CobranzaModel.toJson(cobroDe('c-1', 100));
      final anulado = CobranzaModel.toJson(
        Cobranza(
          id: 'c-1',
          ventaId: 'v-1',
          montoCentavos: 100,
          medio: MedioCobranza.efectivo,
          fecha: t0,
          anuladoAt: t0,
          motivoAnulacion: MotivoDeAnulacion.otro,
          auditoria: Auditoria(createdAt: t0, updatedAt: t0),
        ),
      );

      expect([vigente['anulado_at'], vigente['motivo_anulacion']], [null, null]);
      expect(anulado['anulado_at'], t0.toIso8601String());
      expect(anulado['motivo_anulacion'], 'Otro');
    });

    test('MotivoDeAnulacion.desdeCodigo reconoce la lista del servidor y nada más', () {
      for (final m in MotivoDeAnulacion.values) {
        expect(MotivoDeAnulacion.desdeCodigo(m.codigo), m);
      }
      expect(MotivoDeAnulacion.desdeCodigo('Cualquier cosa'), isNull);
      expect(MotivoDeAnulacion.desdeCodigo(null), isNull);
    });
  });
}
