import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/contexto_notas_persona.dart';

/// Por qué una persona está en solo lectura y con qué datos se lo explica a la colportora (32B·04 y
/// 32B·08). Lo comparten las notas de la persona (HU-UBI-012) y su edición (HU-UBI-010): las dos
/// piden lo mismo para dejar escribir.
final class CausaSoloLecturaPersona {
  const CausaSoloLecturaPersona(this.causa, {this.bajaDesde, this.numeroDepto, this.direccion});

  final CausaSoloLectura causa;
  final DateTime? bajaDesde;
  final String? numeroDepto;
  final String? direccion;
}

/// Dónde está hoy una persona: por qué no se la puede cambiar ([causa], `null` si se puede) y su
/// espacio vigente ([espacioId]: el vínculo más reciente con el espacio y la ubicación activos; `null`
/// si no hay ninguno).
typedef LugarDePersona = ({CausaSoloLecturaPersona? causa, String? espacioId});

/// Solo lectura (32B·04 y 32B·08): la persona está dada de baja, o ninguno de sus vínculos sigue
/// activo con un espacio y una ubicación activos. Si la ubicación no está en el teléfono (el pull no
/// garantiza el orden) no se la cuenta como de baja: ante una fila que falta no se inventa un motivo
/// para frenar.
///
/// Para leerlo dentro de la transacción de quien escribe: usa la misma [db].
Future<LugarDePersona> lugarDePersona(AppDatabase db, PersonaFila persona) async {
  final baja = persona.deletedAt;
  if (baja != null) {
    return (
      causa: CausaSoloLecturaPersona(CausaSoloLectura.personaDeBaja, bajaDesde: baja),
      espacioId: null,
    );
  }
  final consulta =
      db.select(db.espacioPersonas).join([
          innerJoin(db.espacios, db.espacios.id.equalsExp(db.espacioPersonas.espacioId)),
          leftOuterJoin(db.ubicaciones, db.ubicaciones.id.equalsExp(db.espacios.ubicacionId)),
        ])
        ..where(
          db.espacioPersonas.personaId.equals(persona.id) & db.espacioPersonas.deletedAt.isNull(),
        )
        ..orderBy([OrderingTerm.desc(db.espacioPersonas.createdAt)]);
  final filas = await consulta.get();
  if (filas.isEmpty) {
    return (
      causa: const CausaSoloLecturaPersona(CausaSoloLectura.sinEspacioActivo),
      espacioId: null,
    );
  }
  for (final fila in filas) {
    final ubicacion = fila.readTableOrNull(db.ubicaciones);
    final espacio = fila.readTable(db.espacios);
    if (espacio.deletedAt == null && ubicacion?.deletedAt == null) {
      return (causa: null, espacioId: espacio.id);
    }
  }
  // El más reciente de los vínculos, todos con su espacio o su ubicación dados de baja.
  final fila = filas.first;
  final espacio = fila.readTable(db.espacios);
  final ubicacion = fila.readTableOrNull(db.ubicaciones);
  final calle = ubicacion?.calle?.trim() ?? '';
  final numero = ubicacion?.numero?.trim() ?? '';
  final direccion = [calle, numero].where((p) => p.isNotEmpty).join(' ');
  final depto = espacio.numeroDepto?.trim() ?? '';
  return (
    causa: CausaSoloLecturaPersona(
      CausaSoloLectura.espacioDeBaja,
      numeroDepto: depto.isEmpty ? null : depto,
      direccion: direccion.isEmpty ? null : direccion,
    ),
    espacioId: espacio.id,
  );
}
