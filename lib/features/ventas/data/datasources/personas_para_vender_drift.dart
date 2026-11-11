import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../mapa/data/models/ubicacion_model.dart';
import '../../../mapa/domain/entities/espacio.dart';
import '../../../mapa/domain/entities/persona.dart';
import '../../../mapa/domain/entities/ubicacion.dart';
import '../../domain/entities/persona_para_vender.dart';
import '../../domain/repositories/lector_de_personas_para_vender.dart';

/// [LectorDePersonasParaVender] sobre las tablas `espacio_persona`, `persona`, `espacio` y `ubicacion`
/// de la DB cifrada. Solo lee: las personas son locales (nunca salen del teléfono) y esta lista no
/// escribe nada.
///
/// Entra la persona sin baja, con el vínculo sin baja, en un espacio sin baja de una ubicación sin
/// baja. Las personas son de quien las dio de alta (`created_by`).
final class PersonasParaVenderDrift implements LectorDePersonasParaVender {
  PersonasParaVenderDrift(this._db);

  final AppDatabase _db;

  @override
  Stream<List<PersonaParaVender>> observar(String colportorId) {
    final vinculos = _db.espacioPersonas;
    final personas = _db.personas;
    final espacios = _db.espacios;
    final ubicaciones = _db.ubicaciones;
    final consulta =
        _db.select(vinculos).join([
          innerJoin(personas, personas.id.equalsExp(vinculos.personaId)),
          innerJoin(espacios, espacios.id.equalsExp(vinculos.espacioId)),
          innerJoin(ubicaciones, ubicaciones.id.equalsExp(espacios.ubicacionId)),
        ])..where(
          personas.createdBy.equals(colportorId) &
              personas.deletedAt.isNull() &
              vinculos.deletedAt.isNull() &
              espacios.deletedAt.isNull() &
              ubicaciones.deletedAt.isNull(),
        );
    return consulta.watch().map(
      (filas) => [
        for (final fila in filas)
          PersonaParaVender(
            persona: _aPersona(fila.readTable(personas)),
            espacioPersonaId: fila.readTable(vinculos).id,
            espacio: _aEspacio(fila.readTable(espacios)),
            ubicacion: _aUbicacion(fila.readTable(ubicaciones)),
          ),
      ],
    );
  }

  static Auditoria _auditoria({
    required DateTime createdAt,
    required DateTime updatedAt,
    required String? createdBy,
    required DateTime? deletedAt,
    required int syncVersion,
  }) => Auditoria(
    createdAt: createdAt,
    updatedAt: updatedAt,
    createdBy: createdBy,
    deletedAt: deletedAt,
    syncVersion: syncVersion,
  );

  static Persona _aPersona(PersonaFila f) => Persona(
    id: f.id,
    nombre: f.nombre,
    apellido: f.apellido,
    telefono: f.telefono,
    notasGlobales: f.notasGlobales,
    auditoria: _auditoria(
      createdAt: f.createdAt,
      updatedAt: f.updatedAt,
      createdBy: f.createdBy,
      deletedAt: f.deletedAt,
      syncVersion: f.syncVersion,
    ),
  );

  static Espacio _aEspacio(EspacioFila f) => Espacio(
    id: f.id,
    ubicacionId: f.ubicacionId,
    numeroDepto: f.numeroDepto,
    piso: f.piso,
    auditoria: _auditoria(
      createdAt: f.createdAt,
      updatedAt: f.updatedAt,
      createdBy: f.createdBy,
      deletedAt: f.deletedAt,
      syncVersion: f.syncVersion,
    ),
  );

  static Ubicacion _aUbicacion(UbicacionFila f) => Ubicacion(
    id: f.id,
    tipo: UbicacionModel.tipoDesdeCodigo(f.tipo),
    calle: f.calle,
    numero: f.numero,
    lat: f.lat,
    lon: f.lon,
    ciudadId: f.ciudadId,
    zonaId: f.zonaId,
    auditoria: _auditoria(
      createdAt: f.createdAt,
      updatedAt: f.updatedAt,
      createdBy: f.createdBy,
      deletedAt: f.deletedAt,
      syncVersion: f.syncVersion,
    ),
  );
}
