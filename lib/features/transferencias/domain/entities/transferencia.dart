import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// En qué está una transferencia de materiales (HU-STK-005 y HU-STK-006), tal como la ve el colportor.
///
/// El servidor tiene cinco estados; `EJECUTADO` queda sin uso (autorizar ya ejecuta) y se lee como
/// [autorizada]. Las cuatro del canvas (vista 40, B·01): por autorizar, autorizada, rechazada y cancelada.
enum EstadoDeTransferencia {
  /// `PENDIENTE_AUTORIZACION`: espera a la coordinadora.
  porAutorizar,

  /// `AUTORIZADO` (o `EJECUTADO`): la coordinadora la autorizó y los materiales ya cambiaron de mano.
  autorizada,

  /// `RECHAZADO`: la coordinadora no la autorizó; lleva su motivo.
  rechazada,

  /// `CANCELADO`: quien la pidió la canceló mientras estaba por autorizar.
  cancelada;

  /// Ya no cambia: autorizada, rechazada o cancelada.
  bool get estaCerrada => this != porAutorizar;
}

/// Una línea de la transferencia: un material y cuántas unidades.
final class LineaDeTransferencia extends Equatable {
  const LineaDeTransferencia({required this.id, required this.productoId, required this.cantidad});

  final String id;
  final String productoId;

  /// Unidades; siempre mayor que cero.
  final int cantidad;

  @override
  List<Object?> get props => [id, productoId, cantidad];
}

/// Una transferencia de materiales entre dos colportores de la misma campaña (HU-STK-005).
///
/// [origenId] es quien **da** los materiales y [destinoId] quien los **recibe**: el colportor que la pide
/// desde el teléfono es siempre el destino («Juan le pide 2 libros a Ana»). La decide la coordinadora;
/// quien la pidió la puede cancelar mientras está por autorizar.
///
/// **Sin dato de ninguna persona más que ids opacos** (ADR-004): los nombres de las puntas no viajan en
/// la fila.
final class Transferencia extends Equatable {
  const Transferencia({
    required this.id,
    required this.origenId,
    required this.destinoId,
    required this.estado,
    required this.lineas,
    required this.auditoria,
    this.solicitanteId,
    this.fechaSolicitud,
    this.numero,
    this.decididoEn,
    this.motivoRechazo,
  });

  final String id;
  final String origenId;
  final String destinoId;
  final EstadoDeTransferencia estado;
  final List<LineaDeTransferencia> lineas;
  final Auditoria auditoria;

  /// Quién la pidió desde el teléfono; `null` en la que arma el coordinador y en la que todavía no
  /// subió (lo fija el servidor).
  final String? solicitanteId;

  /// Cuándo llegó al servidor; `null` mientras la transferencia espera en la cola de este teléfono.
  final DateTime? fechaSolicitud;

  /// El número visible («T-18»); lo pone el servidor.
  final int? numero;

  /// Cuándo la decidió la coordinadora.
  final DateTime? decididoEn;

  /// Por qué la rechazó la coordinadora.
  final String? motivoRechazo;

  /// Todavía no llegó al servidor: espera en la cola de este teléfono (40A·07).
  bool get enCola => fechaSolicitud == null;

  /// Cuándo se pidió: la hora del servidor si ya llegó, y la del teléfono mientras tanto.
  DateTime get pedidaEl => fechaSolicitud ?? auditoria.createdAt;

  /// ¿La pidió [usuarioId] desde su teléfono? La que todavía no subió no tiene solicitante: la creó él
  /// mismo si es el creador de la fila y la recibe.
  bool laPidio(String usuarioId) =>
      solicitanteId == usuarioId || (solicitanteId == null && auditoria.createdBy == usuarioId);

  /// La armó un coordinador desde el panel: nadie la pidió desde un teléfono y la fila no es suya.
  bool esDeCoordinacion(String usuarioId) =>
      solicitanteId == null && auditoria.createdBy != null && auditoria.createdBy != usuarioId;

  /// La otra punta: con quién es la transferencia para [usuarioId].
  String contraparteDe(String usuarioId) => origenId == usuarioId ? destinoId : origenId;

  /// [usuarioId] la puede cancelar: la pidió él y sigue por autorizar (decisión «Cancelar tr.»).
  bool laPuedeCancelar(String usuarioId) =>
      estado == EstadoDeTransferencia.porAutorizar && laPidio(usuarioId);

  /// Total de unidades de todas las líneas.
  int get totalDeUnidades => lineas.fold(0, (suma, l) => suma + l.cantidad);

  @override
  List<Object?> get props => [
    id,
    origenId,
    destinoId,
    estado,
    lineas,
    auditoria,
    solicitanteId,
    fechaSolicitud,
    numero,
    decididoEn,
    motivoRechazo,
  ];
}

/// El resultado de pedir una transferencia: la fila guardada y si ya estaba (un segundo toque o un
/// reintento con el mismo id no escribe nada).
final class TransferenciaPedida extends Equatable {
  const TransferenciaPedida({required this.transferencia, this.yaEstaba = false});

  final Transferencia transferencia;
  final bool yaEstaba;

  @override
  List<Object?> get props => [transferencia, yaEstaba];
}
