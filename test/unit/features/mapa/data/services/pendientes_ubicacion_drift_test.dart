// El adaptador real de lo que la baja toca o impide (HU-UBI-005, #330) contra las tablas reales:
// AppDatabase en memoria, con el espejo de las reglas UB001 y UB002 del servidor y las entrevistas
// agendadas que la baja cancela.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/pendientes_ubicacion_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/venta_falsos.dart';

void main() {
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late VentaLocalDataSourceDrift ventas;
  late CobranzaLocalDataSourceDrift cobranzas;
  late PendientesUbicacionDrift pendientes;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final estadoDeLasCasas = HouseStatusUpdaterEspia();
    ventas = VentaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: estadoDeLasCasas,
    );
    cobranzas = CobranzaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: estadoDeLasCasas,
    );
    pendientes = PendientesUbicacionDrift(
      db,
      cuotas: CuotasLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: estadoDeLasCasas,
      ),
      colportorId: 'col-1',
      logger: loggerMudo(),
    );
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Future<PendientesUbicacion> leer([String id = 'ub-1']) async =>
      (await pendientes.de(id)).getOrElse(() => throw StateError('era un Left'));

  Future<void> vender(String id, {int monto = 150000}) => ventas.registrar(
    ventaDe(id, monto: monto),
    [itemDe('i-$id', id, cantidad: 1, precio: monto)],
  );

  Future<void> cuota(String id, String ventaId, {required int monto, required int dia}) => db
      .into(db.agendas)
      .insert(
        AgendasCompanion.insert(
          id: id,
          espacioId: 'esp-1',
          tipo: TipoAgenda.cobranza.codigo,
          fechaProgramada: DateTime.utc(2026, 11, dia, 14),
          colportorId: 'col-1',
          ventaId: Value(ventaId),
          montoPrevisto: Value(monto),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  /// Una visita del espacio `esp-1` registrada por [colportor].
  Future<void> visitaDe2(String id, {String colportor = 'col-1', DateTime? borrada}) => db
      .into(db.visitas)
      .insert(
        VisitasCompanion.insert(
          id: id,
          espacioId: 'esp-1',
          fecha: t0,
          tipoResultado: TipoResultadoVisita.noContesto.codigo,
          colportorId: colportor,
          createdAt: t0,
          updatedAt: t0,
          deletedAt: Value(borrada),
        ),
      );

  group('sin nada', () {
    test(
      'dado una casa sin ventas, visitas ni agenda, cuando se revisa, no hay pendientes',
      () async {
        final r = await leer();

        expect(r, PendientesUbicacion.ninguno);
        expect(r.bloqueo, isNull);
        expect(r.hayPendientes, isFalse);
      },
    );

    test('dado una ubicación que no existe, cuando se revisa, tampoco hay pendientes', () async {
      expect(await leer('no-esta'), PendientesUbicacion.ninguno);
    });
  });

  group('UB001 · ventas y cobranza', () {
    test('dado una venta sin cobrar y sin plan, cuando se revisa, la cobranza es el saldo de la '
        'venta, sin número de cuota, y dice a dónde ir', () async {
      await vender('v-1', monto: 145000);

      final r = await leer();

      expect(r.tieneVentas, isTrue);
      expect(
        r.cobranzaPendiente,
        const CobranzaPendiente(
          montoCentavos: 145000,
          ventaId: 'v-1',
          espacioId: 'esp-1',
          espacioPersonaId: 'ep-1',
        ),
      );
      expect(r.cobranzaPendiente!.tieneDestino, isTrue);
      expect(r.bloqueo, isA<BloqueoPorCobranza>());
    });

    test('dado una venta con un plan de cuotas, cuando se revisa, la cobranza es la próxima cuota '
        'con su número', () async {
      await vender('v-1', monto: 150000);
      await cuota('c-1', 'v-1', monto: 50000, dia: 10);
      await cuota('c-2', 'v-1', monto: 100000, dia: 20);

      final r = await leer();

      expect(r.cobranzaPendiente!.montoCentavos, 50000);
      expect(r.cobranzaPendiente!.numeroCuota, 1);
      expect(r.cobranzaPendiente!.ventaId, 'v-1');
    });

    test('dado dos ventas con saldo, cuando se revisa, muestra la más antigua', () async {
      await ventas.registrar(ventaDe('v-nueva', monto: 20000, fecha: DateTime.utc(2026, 10, 25)), [
        itemDe('i-n', 'v-nueva', cantidad: 1, precio: 20000),
      ]);
      await ventas.registrar(
        ventaDe('v-vieja', monto: 30000, talonario: 'T-2', fecha: DateTime.utc(2026, 10, 20)),
        [itemDe('i-v', 'v-vieja', cantidad: 1, precio: 30000)],
      );

      final r = await leer();

      expect(r.cobranzaPendiente!.ventaId, 'v-vieja');
      expect(r.cobranzaPendiente!.montoCentavos, 30000);
      expect(r.cobranzaPendiente!.cantidad, 2, reason: 'el aviso dice cuántas son (P4, 04/11)');
    });

    test('dado una sola venta con saldo, cuando se revisa, la cantidad es 1', () async {
      await vender('v-1');

      expect((await leer()).cobranzaPendiente!.cantidad, 1);
    });

    test(
      'dado dos ventas y una cobrada entera, cuando se revisa, solo cuenta la que debe',
      () async {
        await vender('v-1', monto: 150000);
        await ventas.registrar(
          ventaDe('v-2', monto: 30000, talonario: 'T-2', fecha: DateTime.utc(2026, 10, 27)),
          [itemDe('i-2', 'v-2', cantidad: 1, precio: 30000)],
        );
        await cobranzas.registrar(
          Cobranza(
            id: 'c-1',
            ventaId: 'v-1',
            montoCentavos: 150000,
            medio: MedioCobranza.efectivo,
            fecha: t0,
            auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
          ),
        );

        final c = (await leer()).cobranzaPendiente!;

        expect(c.cantidad, 1);
        expect(c.ventaId, 'v-2');
      },
    );

    test('dado una venta ya cobrada entera, cuando se revisa, igual bloquea (tiene ventas) pero '
        'sin cobranza ni destino', () async {
      await vender('v-1', monto: 150000);
      await cobranzas.registrar(
        Cobranza(
          id: 'c-1',
          ventaId: 'v-1',
          montoCentavos: 150000,
          medio: MedioCobranza.efectivo,
          fecha: t0,
          auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
        ),
      );

      final r = await leer();

      expect(r.tieneVentas, isTrue);
      expect(r.cobranzaPendiente, isNull);
      expect(r.bloqueo, isA<BloqueoPorVentasOVisitasAjenas>());
    });

    test('dado una venta de un vínculo dado de baja, cuando se revisa, igual cuenta como venta: el '
        'servidor no mira deleted_at ahí y ante la duda se bloquea', () async {
      await vender('v-1');
      await (db.update(
        db.espacioPersonas,
      )..where((e) => e.id.equals('ep-1'))).write(EspacioPersonasCompanion(deletedAt: Value(t0)));

      final r = await leer();

      expect(r.tieneVentas, isTrue);
      expect(r.bloqueo, isNotNull);
    });

    test('dado una venta dada de baja, cuando se revisa, cuenta como venta pero no como cobranza '
        'pendiente', () async {
      await vender('v-1');
      await (db.update(
        db.ventas,
      )..where((v) => v.id.equals('v-1'))).write(VentasCompanion(deletedAt: Value(t0)));

      final r = await leer();

      expect(r.tieneVentas, isTrue);
      expect(r.cobranzaPendiente, isNull);
    });

    test('dado una venta de otra ubicación, cuando se revisa esta, no se mezcla', () async {
      await sembrarUbicacion(db, id: 'ub-2');
      await sembrarEspacio(db, id: 'esp-2', ubicacionId: 'ub-2');
      await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
      await ventas.registrar(ventaDe('v-2', vinculo: 'ep-2'), [itemDe('i-2', 'v-2')]);

      expect(await leer(), PendientesUbicacion.ninguno);
      expect((await leer('ub-2')).tieneVentas, isTrue);
    });
  });

  group('UB002 · visitas de otro colportor', () {
    test('dado una visita de otro colportor, cuando se revisa, bloquea', () async {
      await visitaDe2('vis-1', colportor: 'col-2');

      final r = await leer();

      expect(r.tieneVisitasDeOtros, isTrue);
      expect(r.bloqueo, isA<BloqueoPorVentasOVisitasAjenas>());
    });

    test('dado solo visitas propias, cuando se revisa, no bloquea', () async {
      await visitaDe2('vis-1');

      expect((await leer()).tieneVisitasDeOtros, isFalse);
    });

    test('dado una visita de otro colportor ya dada de baja, cuando se revisa, igual bloquea (el '
        'servidor no mira deleted_at)', () async {
      await visitaDe2('vis-1', colportor: 'col-2', borrada: t0);

      expect((await leer()).tieneVisitasDeOtros, isTrue);
    });
  });

  group('tipo de la ubicación (P2, 04/11)', () {
    Future<void> comoTipo(String tipo) =>
        db.customStatement("UPDATE ubicacion SET tipo = '$tipo' WHERE id = 'ub-1'");

    test('dado una casa, un edificio y un negocio, cuando se revisa, trae el tipo', () async {
      expect((await leer()).tipo, TipoUbicacion.casa);

      await comoTipo('EDIFICIO');
      expect((await leer()).tipo, TipoUbicacion.edificio);

      await comoTipo('NEGOCIO');
      expect((await leer()).tipo, TipoUbicacion.negocio);
    });

    test(
      'dado un negocio con una entrevista, cuando se revisa, el aviso dice «Este negocio»',
      () async {
        await comoTipo('NEGOCIO');
        await insertarAgenda(db, agendaDe('ag-1'));

        expect((await leer()).resumen, [
          'Este negocio tiene 1 entrevista agendada. Si la das de baja, se cancela.',
        ]);
      },
    );
  });

  group('entrevistas agendadas', () {
    test('dado una entrevista PROGRAMADA, cuando se revisa, pide la segunda confirmación con el '
        'aviso de la decisión de Cristian', () async {
      await insertarAgenda(db, agendaDe('ag-1'));

      final r = await leer();

      expect(r.entrevistasAgendadas, ['ag-1']);
      expect(r.hayPendientes, isTrue);
      expect(r.bloqueo, isNull, reason: 'las entrevistas no bloquean');
      expect(r.resumen, ['Esta casa tiene 1 entrevista agendada. Si la das de baja, se cancela.']);
    });

    test('dado varias entrevistas, cuando se revisa, el aviso va en plural', () async {
      await insertarAgenda(db, agendaDe('ag-b'));
      await insertarAgenda(db, agendaDe('ag-a'));

      final r = await leer();

      expect(r.entrevistasAgendadas, ['ag-a', 'ag-b']);
      expect(r.resumen, [
        'Esta casa tiene 2 entrevistas agendadas. Si la das de baja, se cancelan.',
      ]);
    });

    test('dado entrevistas cumplidas, no cumplidas, canceladas, dadas de baja y una cobranza, '
        'cuando se revisa, ninguna cuenta', () async {
      await insertarAgenda(db, agendaDe('ag-1', estado: EstadoAgenda.cumplida));
      await insertarAgenda(db, agendaDe('ag-2', estado: EstadoAgenda.noCumplida));
      await insertarAgenda(db, agendaDe('ag-3', estado: EstadoAgenda.cancelada));
      await insertarAgenda(db, agendaDe('ag-4', borrada: t0));
      await insertarAgenda(db, agendaDe('ag-5', tipo: TipoAgenda.cobranza));

      expect((await leer()).entrevistasAgendadas, isEmpty);
    });

    test('dado entrevistas en dos deptos de un edificio, cuando se revisa el edificio, cuenta la '
        'de cualquier depto', () async {
      await sembrarUbicacion(db, id: 'ub-9', tipo: 'EDIFICIO');
      await sembrarEspacio(db, id: 'e9a', ubicacionId: 'ub-9', numeroDepto: '1A');
      await sembrarEspacio(db, id: 'e9b', ubicacionId: 'ub-9', numeroDepto: '2B');
      await insertarAgenda(db, agendaDe('ag-a', espacio: 'e9a', vinculo: null));
      await insertarAgenda(db, agendaDe('ag-b', espacio: 'e9b', vinculo: null));

      expect((await leer('ub-9')).entrevistasAgendadas, ['ag-a', 'ag-b']);
    });
  });

  group('lectura que falla', () {
    test('dado que la base no se puede leer, cuando se revisa, devuelve la falla de revisión y no '
        '«no hay nada»', () async {
      await db.close();

      final r = await pendientes.de('ub-1');

      expect(r.isLeft(), isTrue);
      expect(
        r.swap().getOrElse(() => throw StateError('era un Right')),
        isA<FailurePendientesNoDisponibles>(),
      );
    });
  });
}
