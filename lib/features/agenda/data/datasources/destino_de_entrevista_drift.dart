import '../../../../core/database/app_database.dart';
import '../../domain/services/destino_de_entrevista.dart';

/// [ResolverDestinoDeEntrevista] sobre las tablas `espacio`, `espacio_persona` y `persona` de la DB
/// local. Solo lee.
///
/// El vínculo manda sobre el espacio guardado al empezar: la unión de duplicados repunta los
/// vínculos al espacio que quedó (también los dados de baja), así que el `espacio_id` del vínculo es
/// el vigente aunque el de la entrevista ya esté de baja.
final class DestinoDeEntrevistaDrift implements ResolverDestinoDeEntrevista {
  DestinoDeEntrevistaDrift(this._db);

  final AppDatabase _db;

  @override
  Future<DestinoDeEntrevista?> resolver({
    required String espacioId,
    required String espacioPersonaId,
  }) async {
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.id.equals(espacioPersonaId))).getSingleOrNull();

    var conPersona = false;
    if (vinculo != null && vinculo.deletedAt == null) {
      final persona = await (_db.select(
        _db.personas,
      )..where((p) => p.id.equals(vinculo.personaId))).getSingleOrNull();
      conPersona = persona != null && persona.deletedAt == null;
    }

    final espacioVigente = vinculo?.espacioId ?? espacioId;
    final espacio = await (_db.select(
      _db.espacios,
    )..where((e) => e.id.equals(espacioVigente))).getSingleOrNull();
    if (espacio == null || espacio.deletedAt != null) return null;

    return DestinoDeEntrevista(
      espacioId: espacio.id,
      espacioPersonaId: conPersona ? espacioPersonaId : null,
    );
  }
}
