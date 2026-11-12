// QA de #679 («Unión rech.»), migración 35 → 36 sobre datos existentes: la 36 solo suma la tabla
// `ubicacion_union_local`, vacía. Ninguna fila de lo que ya había (ubicaciones, espacios, personas,
// vínculos, visitas, agendas, notas, ventas, pares decididos, auditoría, cola) se pierde ni cambia, y
// las uniones hechas antes de la 36 quedan sin fila de unión (no se deshacen: quedan como estaban).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

import 'generated/schema.dart';
import 'generated/schema_v35.dart' as v35;
import 'generated/schema_v36.dart' as v36;

class _SinSalida extends LogOutput {
  @override
  void output(OutputEvent event) {}
}

AppDatabase _abrir(QueryExecutor e) => AppDatabase(e, logger: AppLogger(output: _SinSalida()));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verificador;

  setUpAll(() {
    verificador = SchemaVerifier(GeneratedHelper());
  });

  test(
    'dado un teléfono con casas, personas, ventas y una unión ya encolada en la versión 35, '
    'cuando migra a la 36, no se pierde ni cambia ninguna fila y la tabla de uniones queda vacía',
    () async {
      const casaA = v35.UbicacionData(
        id: 'ub-a',
        tipo: 'CASA',
        calle: 'Italia',
        numero: '1234',
        lat: -34.9,
        lon: -56.1,
        ciudadId: 'ciu-1',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 2,
      );
      const casaBDeBaja = v35.UbicacionData(
        id: 'ub-b',
        tipo: 'CASA',
        calle: 'Italia',
        numero: '1234',
        lat: -34.9,
        lon: -56.1,
        ciudadId: 'ciu-1',
        createdAt: 1758700000000,
        updatedAt: 1758710000000,
        createdBy: 'col-1',
        deletedAt: 1758710000000,
        syncVersion: 3,
      );
      const espacio = v35.EspacioData(
        id: 'esp-a',
        ubicacionId: 'ub-a',
        numeroDepto: '3',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const persona = v35.PersonaData(
        id: 'per-1',
        nombre: 'Ñandú 🙂',
        apellido: "O'Brien",
        telefono: '099123456',
        notasGlobales: 'Prefiere la tarde',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const vinculo = v35.EspacioPersonaData(
        id: 'ep-1',
        espacioId: 'esp-a',
        personaId: 'per-1',
        ubicacionCobranzaAltId: 'ub-b',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const nota = v35.NotaData(
        id: 'n-1',
        targetType: 'UBICACION',
        targetId: 'ub-b',
        texto: 'Portero eléctrico roto',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const visita = v35.VisitaData(
        id: 'vis-1',
        espacioId: 'esp-a',
        espacioPersonaId: 'ep-1',
        fecha: 1758700000000,
        tipoResultado: 'VENTA',
        colportorId: 'col-1',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const venta = v35.VentaData(
        id: 'v-1',
        espacioPersonaId: 'ep-1',
        numeroTalonario: 'T-001',
        montoTotal: 150000,
        fecha: 1758700000000,
        colportorId: 'col-1',
        visitaId: 'vis-1',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const agenda = v35.AgendaData(
        id: 'ag-1',
        espacioId: 'esp-a',
        espacioPersonaId: 'ep-1',
        tipo: 'ENTREVISTA',
        fechaProgramada: 1758800000000,
        esEstricta: 0,
        estado: 'PROGRAMADA',
        colportorId: 'col-1',
        ubicacionAltId: 'ub-b',
        createdAt: 1758700000000,
        updatedAt: 1758700000000,
        createdBy: 'col-1',
        syncVersion: 1,
      );
      const par = v35.UbicacionParDecididoData(
        ubicacionAId: 'ub-c',
        ubicacionBId: 'ub-d',
        decision: 'CONSERVAR_AMBOS',
        decididoEn: 1758700000000,
      );
      const auditoria = v35.AuditLogData(
        id: 1,
        evento: 'ubicacion_baja',
        uuid: 'ub-b',
        motivo: 'duplicado_de_ub-a',
        creadoEn: 1758710000000,
      );
      // La unión que el teléfono ya hizo antes de la 36 y que el servidor todavía no contestó.
      const unionEncolada = v35.SyncQueueData(
        id: 'q-1',
        clientOpId: 'op-1',
        entity: 'ubicacion',
        op: 'marcar_como_duplicado',
        payload: '{"duplicada_id":"ub-b","conservada_id":"ub-a"}',
        rowPk: 'ub-b',
        createdAt: 1758710000000,
        state: 'INVALID',
        code: 'UB003',
        message: '',
      );

      await verificador.testWithDataIntegrity(
        oldVersion: 35,
        newVersion: 36,
        createOld: v35.DatabaseAtV35.new,
        createNew: v36.DatabaseAtV36.new,
        openTestedDatabase: _abrir,
        createItems: (batch, viejo) {
          batch
            ..insertAll(viejo.ubicacion, [casaA, casaBDeBaja])
            ..insert(viejo.espacio, espacio)
            ..insert(viejo.persona, persona)
            ..insert(viejo.espacioPersona, vinculo)
            ..insert(viejo.nota, nota)
            ..insert(viejo.visita, visita)
            ..insert(viejo.venta, venta)
            ..insert(viejo.agenda, agenda)
            ..insert(viejo.ubicacionParDecidido, par)
            ..insert(viejo.auditLog, auditoria)
            ..insert(viejo.syncQueue, unionEncolada);
        },
        validateItems: (nuevo) async {
          final ubicaciones = await (nuevo.select(
            nuevo.ubicacion,
          )..orderBy([(u) => OrderingTerm.asc(u.id)])).get();
          expect(ubicaciones.map((u) => u.toJson()), [casaA.toJson(), casaBDeBaja.toJson()]);
          expect((await nuevo.select(nuevo.espacio).get()).map((e) => e.toJson()), [
            espacio.toJson(),
          ]);
          expect((await nuevo.select(nuevo.persona).get()).map((p) => p.toJson()), [
            persona.toJson(),
          ]);
          expect((await nuevo.select(nuevo.espacioPersona).get()).map((p) => p.toJson()), [
            vinculo.toJson(),
          ]);
          expect((await nuevo.select(nuevo.nota).get()).map((p) => p.toJson()), [nota.toJson()]);
          expect((await nuevo.select(nuevo.visita).get()).map((p) => p.toJson()), [
            visita.toJson(),
          ]);
          expect((await nuevo.select(nuevo.venta).get()).map((p) => p.toJson()), [venta.toJson()]);
          expect((await nuevo.select(nuevo.agenda).get()).map((p) => p.toJson()), [
            agenda.toJson(),
          ]);
          expect((await nuevo.select(nuevo.ubicacionParDecidido).get()).map((p) => p.toJson()), [
            par.toJson(),
          ]);
          expect((await nuevo.select(nuevo.auditLog).get()).map((p) => p.toJson()), [
            auditoria.toJson(),
          ]);
          expect((await nuevo.select(nuevo.syncQueue).get()).map((p) => p.toJson()), [
            unionEncolada.toJson(),
          ]);
          // La unión de antes de la 36 no tiene qué deshacer: la tabla arranca vacía.
          expect(await nuevo.select(nuevo.ubicacionUnionLocal).get(), isEmpty);
        },
      );
    },
  );
}
