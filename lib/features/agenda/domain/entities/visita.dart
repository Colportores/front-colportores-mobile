import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';

/// Resultado de una visita (`visita.tipo_resultado`, esquema-datos.md §Operaciones de campo).
/// [codigo] es el valor de la columna.
///
/// `COBRANZA` es la pasada a cobrar (HU-VIS-005; decisión de Cristian del 23/10, «Visita cobro»):
/// un resultado más, que queda en el historial aunque no se cobre, cumple la cita de cobranza y **no**
/// cuenta como presentación.
enum TipoResultadoVisita {
  venta('VENTA'),
  noContesto('NO_CONTESTO'),
  rechazo('RECHAZO'),
  entrevista('ENTREVISTA'),
  cobranza('COBRANZA');

  const TipoResultadoVisita(this.codigo);

  final String codigo;

  /// Si el resultado cuenta como **presentación** (HU-VIS-005, decisión de Cristian del 21/10,
  /// docs#69): la visita con la entrevista hecha. Cuentan `VENTA` y `ENTREVISTA`; no `NO_CONTESTO`
  /// (nadie atendió) ni `COBRANZA` (fue a cobrar). `RECHAZO` tampoco, hasta que se confirme (S62). Es la misma definición que usa
  /// el servidor para el tablero del coordinador: la app no guarda ningún campo aparte, el resultado
  /// ya queda distinguible por su [codigo].
  bool get cuentaComoPresentacion => this == venta || this == entrevista;

  /// Si la visita **cumple** la agenda que tenía la casa (la agenda pasa a `CUMPLIDA`). Con
  /// `NO_CONTESTO` la agenda pasa a `NO_CUMPLIDA` (HU-VIS-005; decisión del 23/10, «No cumplida»).
  /// Los otros resultados la cumplen: la HU solo nombra a `NO_CONTESTO` como «no cumplida» (lectura
  /// del mapa de decisiones, §2; `COBRANZA` cumple la cita de cobranza).
  bool get cumpleLaAgenda => this != noContesto;

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
    required this.espacioId,
    this.espacioPersonaId,
    required DateTime fecha,
    required this.tipoResultado,
    required this.colportorId,
    this.jornadaId,
    required this.auditoria,
  }) : fecha = instanteMs(fecha);

  final String id;

  /// FK a `espacio.id`: la casa o el depto de la visita. Es a lo que cuelga la visita
  /// (backend-supabase 0069; decisión del 23/10, «Sin persona»).
  final String espacioId;

  /// FK opcional a `espacio_persona.id`: con quién fue la visita. «No contestó» y «Rechazo» no piden
  /// persona; con persona, es el vínculo de ese espacio (ADR-017).
  final String? espacioPersonaId;

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
    espacioId,
    espacioPersonaId,
    fecha,
    tipoResultado,
    colportorId,
    jornadaId,
    auditoria,
  ];
}
