// Dobles y semillas de la agenda, las visitas y la cache `house_status` (BACK-HU-VIS-001) para los
// tests contra la DB real en memoria: la misma tabla, los mismos CHECK y las mismas transacciones
// que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/house_status.dart';
import 'package:colportores_mobile/features/mapa/domain/services/house_status_updater.dart';
import 'package:drift/drift.dart';

/// El instante de las semillas.
final t0 = DateTime.utc(2026, 10, 23, 13, 45, 10, 123);

Auditoria auditoriaDe({DateTime? creada, DateTime? borrada, int syncVersion = 0}) => Auditoria(
  createdAt: creada ?? t0,
  updatedAt: creada ?? t0,
  createdBy: 'col-1',
  deletedAt: borrada,
  syncVersion: syncVersion,
);

/// Una ubicación en la DB (con las columnas mínimas que exige la tabla).
Future<void> sembrarUbicacion(
  AppDatabase db, {
  String id = 'ub-1',
  String tipo = 'CASA',
  double lat = -34.9,
  double lon = -56.16,
  DateTime? borrada,
}) => db
    .into(db.ubicaciones)
    .insert(
      UbicacionesCompanion.insert(
        id: id,
        tipo: tipo,
        lat: lat,
        lon: lon,
        ciudadId: 'ciu-1',
        createdAt: t0,
        updatedAt: t0,
        deletedAt: Value(borrada),
      ),
    );

Future<void> sembrarEspacio(
  AppDatabase db, {
  String id = 'esp-1',
  String ubicacionId = 'ub-1',
  String? numeroDepto,
  DateTime? borrado,
}) => db
    .into(db.espacios)
    .insert(
      EspaciosCompanion.insert(
        id: id,
        ubicacionId: ubicacionId,
        numeroDepto: Value(numeroDepto),
        createdAt: t0,
        updatedAt: t0,
        deletedAt: Value(borrado),
      ),
    );

Future<void> sembrarVinculo(
  AppDatabase db, {
  String id = 'ep-1',
  String espacioId = 'esp-1',
  String personaId = 'per-1',
  DateTime? borrado,
}) => db
    .into(db.espacioPersonas)
    .insert(
      EspacioPersonasCompanion.insert(
        id: id,
        espacioId: espacioId,
        personaId: personaId,
        createdAt: t0,
        updatedAt: t0,
        deletedAt: Value(borrado),
      ),
    );

/// Una casa con un espacio y una persona: `ub-1` → `esp-1` → `ep-1`.
Future<void> sembrarCasa(AppDatabase db) async {
  await sembrarUbicacion(db);
  await sembrarEspacio(db);
  await sembrarVinculo(db);
}

/// Un edificio con dos deptos y una persona en cada uno: `ub-1` → `esp-1`/`esp-2` → `ep-1`/`ep-2`.
Future<void> sembrarEdificio(AppDatabase db) async {
  await sembrarUbicacion(db, tipo: 'EDIFICIO');
  await sembrarEspacio(db, numeroDepto: '1A');
  await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
  await sembrarVinculo(db);
  await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');
}

Agenda agendaDe(
  String id, {
  String espacio = 'esp-1',
  String? vinculo = 'ep-1',
  TipoAgenda tipo = TipoAgenda.entrevista,
  EstadoAgenda estado = EstadoAgenda.programada,
  DateTime? creada,
  DateTime? borrada,
  String? visitaId,
  bool esEstricta = false,
  String? slot,
  String? ventaId,
  String? entregaId,
  DateTime? fecha,
}) => Agenda(
  id: id,
  espacioId: espacio,
  espacioPersonaId: vinculo,
  tipo: tipo,
  fechaProgramada: fecha ?? DateTime.utc(2026, 10, 25, 14),
  slotCodigo: slot,
  esEstricta: esEstricta,
  estado: estado,
  colportorId: 'col-1',
  visitaId: visitaId,
  ventaId: ventaId,
  entregaId: entregaId,
  auditoria: auditoriaDe(creada: creada, borrada: borrada),
);

Visita visitaDe(
  String id, {
  String espacio = 'esp-1',
  String? vinculo = 'ep-1',
  TipoResultadoVisita resultado = TipoResultadoVisita.entrevista,
  DateTime? creada,
  DateTime? borrada,
  String? jornadaId,
}) => Visita(
  id: id,
  espacioId: espacio,
  espacioPersonaId: vinculo,
  fecha: creada ?? t0,
  tipoResultado: resultado,
  colportorId: 'col-1',
  jornadaId: jornadaId,
  auditoria: auditoriaDe(creada: creada, borrada: borrada),
);

NotaDeCampo notaDe(String id, {String texto = 'Atiende de tarde'}) =>
    NotaDeCampo(id: id, texto: texto, auditoria: auditoriaDe());

/// Inserta una agenda directo en la tabla, sin pasar por la app (para armar escenarios).
Future<void> insertarAgenda(AppDatabase db, Agenda a) => db
    .into(db.agendas)
    .insert(
      AgendasCompanion.insert(
        id: a.id,
        espacioId: a.espacioId,
        espacioPersonaId: Value(a.espacioPersonaId),
        tipo: a.tipo.codigo,
        fechaProgramada: a.fechaProgramada,
        slotCodigo: Value(a.slotCodigo),
        esEstricta: Value(a.esEstricta),
        ubicacionAltId: Value(a.ubicacionAltId),
        estado: Value(a.estado.codigo),
        colportorId: a.colportorId,
        visitaId: Value(a.visitaId),
        createdAt: a.auditoria.createdAt,
        updatedAt: a.auditoria.updatedAt,
        createdBy: Value(a.auditoria.createdBy),
        deletedAt: Value(a.auditoria.deletedAt),
      ),
    );

/// Inserta una visita directo en la tabla, sin pasar por la app.
Future<void> insertarVisita(AppDatabase db, Visita v) => db
    .into(db.visitas)
    .insert(
      VisitasCompanion.insert(
        id: v.id,
        espacioId: v.espacioId,
        espacioPersonaId: Value(v.espacioPersonaId),
        fecha: v.fecha,
        tipoResultado: v.tipoResultado.codigo,
        colportorId: v.colportorId,
        jornadaId: Value(v.jornadaId),
        createdAt: v.auditoria.createdAt,
        updatedAt: v.auditoria.updatedAt,
        createdBy: Value(v.auditoria.createdBy),
        deletedAt: Value(v.auditoria.deletedAt),
      ),
    );

/// [HouseStatusUpdater] que solo anota con qué lo llamaron. [fallarCon] simula un recálculo que
/// falla: la transacción de la escritura que lo llamó se tiene que revertir.
final class HouseStatusUpdaterEspia implements HouseStatusUpdater {
  Object? fallarCon;

  final llamadas = <({String ubicacionId, DateTime ahora, String colportorId})>[];

  @override
  Future<HouseStatus?> recalcular(
    String ubicacionId, {
    required DateTime ahora,
    required String colportorId,
  }) async {
    llamadas.add((ubicacionId: ubicacionId, ahora: ahora, colportorId: colportorId));
    final error = fallarCon;
    if (error != null) throw error;
    return null;
  }
}
