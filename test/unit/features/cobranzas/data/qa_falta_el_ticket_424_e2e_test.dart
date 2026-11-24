// «Falta el ticket» (#424) contra las tablas reales: el detalle que lee `DetalleDelCobroPage` trae
// `ticketId` vacío para un cobro con tarjeta sin ticket y lo trae ligado cuando el ticket se registra
// por el camino real de la foto (vista 29 C). AppDatabase en memoria, mismo esquema y mismos CHECK.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import 'package:colportores_mobile/features/cobranzas/data/repositories/anulacion_de_cobro_repository_impl.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/tickets/data/datasources/ticket_local_data_source_drift.dart';
import 'package:colportores_mobile/features/ventas/data/datasources/venta_local_data_source_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../helpers/campo_falsos.dart';
import '../../../../helpers/logger_mudo.dart';
import '../../../../helpers/tickets_falsos.dart';
import '../../../../helpers/venta_falsos.dart';

Cobranza _cobro(String id, MedioCobranza medio) => Cobranza(
  id: id,
  ventaId: 'v-1',
  montoCentavos: 60000,
  medio: medio,
  fecha: t0,
  tarjetaTipo: medio == MedioCobranza.tarjeta ? TipoTarjeta.credito : null,
  tarjetaMarca: medio == MedioCobranza.tarjeta ? 'Visa' : null,
  numeroAprobacion: medio == MedioCobranza.tarjeta ? '004512' : null,
  auditoria: Auditoria(createdAt: t0, updatedAt: t0, createdBy: 'col-1'),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late CobranzaLocalDataSourceDrift local;
  late AnulacionDeCobroRepositoryImpl repo;
  late TicketLocalDataSourceDrift tickets;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    final casas = HouseStatusUpdaterDrift(db, encolador: encolador);
    local = CobranzaLocalDataSourceDrift(db, encolador: encolador, estadoDeLasCasas: casas);
    repo = AnulacionDeCobroRepositoryImpl(local, logger: loggerMudo());
    tickets = TicketLocalDataSourceDrift(db, encolador: encolador);
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
  });
  tearDown(() => db.close());

  Future<String?> ticketIdDelDetalle(String id) async {
    final d = (await repo.detalle(id)).fold((f) => fail('falla $f'), (d) => d);
    return d!.cobranza.ticketId;
  }

  test(
    'un cobro con tarjeta sin ticket llega al detalle con el ticket vacío y con sus datos',
    () async {
      await local.registrar(_cobro('c-1', MedioCobranza.tarjeta));

      final d = (await repo.detalle('c-1')).fold((f) => fail('falla $f'), (d) => d)!;

      expect(d.cobranza.medio, MedioCobranza.tarjeta);
      expect(d.cobranza.ticketId, isNull);
      // Lo que la foto del ticket precarga.
      expect(d.cobranza.numeroAprobacion, '004512');
      expect(d.cobranza.montoCentavos, 60000);
    },
  );

  test(
    'registrada la foto del ticket con ese cobro, el detalle ya trae el ticket (la marca se va)',
    () async {
      await local.registrar(_cobro('c-1', MedioCobranza.tarjeta));
      expect(await ticketIdDelDetalle('c-1'), isNull);

      await tickets.registrar(ticketDePrueba('t-1'), fotoLocalDePrueba('t-1'), cobroId: 'c-1');

      expect(await ticketIdDelDetalle('c-1'), 't-1');
    },
  );

  test('un segundo toque a «Enviar» (mismo ticket) no cambia el ligue', () async {
    await local.registrar(_cobro('c-1', MedioCobranza.tarjeta));

    await tickets.registrar(ticketDePrueba('t-1'), fotoLocalDePrueba('t-1'), cobroId: 'c-1');
    final otra = await tickets.registrar(
      ticketDePrueba('t-1'),
      fotoLocalDePrueba('t-1'),
      cobroId: 'c-1',
    );

    expect(otra.yaEstaba, isTrue);
    expect(await ticketIdDelDetalle('c-1'), 't-1');
  });

  test('un cobro en efectivo no tiene ticket y el detalle no lo confunde con tarjeta', () async {
    await local.registrar(_cobro('c-2', MedioCobranza.efectivo));

    final d = (await repo.detalle('c-2')).fold((f) => fail('falla $f'), (d) => d)!;

    expect(d.cobranza.medio, MedioCobranza.efectivo);
    expect(d.cobranza.ticketId, isNull);
  });

  test('un cobro con tarjeta anulado llega anulado: la pantalla no pide el ticket', () async {
    await local.registrar(_cobro('c-1', MedioCobranza.tarjeta));
    await local.anular(
      cobranzaId: 'c-1',
      motivo: MotivoDeAnulacion.montoEquivocado,
      colportorId: 'col-1',
      ahora: t0.add(const Duration(hours: 1)),
    );

    final d = (await repo.detalle('c-1')).fold((f) => fail('falla $f'), (d) => d)!;

    expect(d.cobranza.estaAnulado, isTrue);
  });
}
