import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';

/// Resultado de una visita (`visita.tipo_resultado`, esquema-datos.md §Operaciones de campo).
/// [codigo] es el valor de la columna.
///
/// La HU-VIS-005 suma `COBRANZA`, que el servidor no admite todavía: hasta la decisión de Cristian
/// (pendiente P2 de #151) la tabla copia el `CHECK` del servidor y este enum no lo tiene.
enum TipoResultadoVisita {
  venta('VENTA'),
  noContesto('NO_CONTESTO'),
  rechazo('RECHAZO'),
  entrevista('ENTREVISTA');

  const TipoResultadoVisita(this.codigo);

  final String codigo;

  /// Inversa de [codigo]. Lanza `ArgumentError` con un valor desconocido (lo frena el `CHECK`).
  static TipoResultadoVisita desdeCodigo(String codigo) => values.firstWhere(
    (t) => t.codigo == codigo,
    orElse: () => throw ArgumentError.value(codigo, 'codigo', 'resultado de visita desconocido'),
  );
}

/// Contacto realizado por el colportor (esquema-datos.md §Operaciones de campo, tabla `visita`).
///
/// **No lleva notas**: las de una visita son filas de `nota` (`target_type = VISITA`, local-only,
/// ADR-017), nunca una columna. Así la fila que sube es la entidad entera y no hay dato personal.
class Visita extends Equatable {
  Visita({
    required this.id,
    required this.espacioPersonaId,
    required DateTime fecha,
    required this.tipoResultado,
    required this.colportorId,
    this.jornadaId,
    required this.auditoria,
  }) : fecha = instanteMs(fecha);

  final String id;

  /// FK a `espacio_persona.id` (`NOT NULL`, ADR-017).
  final String espacioPersonaId;

  /// Siempre en UTC y al milisegundo — ver [instanteMs].
  final DateTime fecha;

  final TipoResultadoVisita tipoResultado;

  /// FK a `usuario.id`.
  final String colportorId;

  /// FK a `jornada.id`. Opcional, como en el servidor.
  final String? jornadaId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [
    id,
    espacioPersonaId,
    fecha,
    tipoResultado,
    colportorId,
    jornadaId,
    auditoria,
  ];
}
