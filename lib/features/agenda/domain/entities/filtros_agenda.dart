import 'package:equatable/equatable.dart';

import 'estado_agenda.dart';
import 'tipo_agenda.dart';

/// Qué estados muestra la agenda (23B·04 «Filtro de estado»). Por defecto, [pendientes].
enum EstadoFiltroAgenda {
  /// Las `PROGRAMADA` de hoy en adelante, incluida la de hoy cuya hora ya pasó (23B·02).
  pendientes,
  cumplidas,
  noCumplidas,
  canceladas,
  todas;

  /// ¿Una agenda en [estado] entra con este filtro?
  bool admite(EstadoAgenda estado) => switch (this) {
    pendientes => estado == EstadoAgenda.programada,
    cumplidas => estado == EstadoAgenda.cumplida,
    noCumplidas => estado == EstadoAgenda.noCumplida,
    canceladas => estado == EstadoAgenda.cancelada,
    todas => true,
  };
}

/// Los filtros de la agenda: por tipo (entrevista o cobranza; `null` = todas) y por estado.
class FiltrosAgenda extends Equatable {
  const FiltrosAgenda({this.tipo, this.estado = EstadoFiltroAgenda.pendientes});

  /// `null` = «Todas».
  final TipoAgenda? tipo;
  final EstadoFiltroAgenda estado;

  /// Los de la primera vez: todas las agendas pendientes.
  static const porDefecto = FiltrosAgenda();

  bool get esPorDefecto => this == porDefecto;

  FiltrosAgenda conTipo(TipoAgenda? nuevo) => FiltrosAgenda(tipo: nuevo, estado: estado);

  FiltrosAgenda conEstado(EstadoFiltroAgenda nuevo) => FiltrosAgenda(tipo: tipo, estado: nuevo);

  @override
  List<Object?> get props => [tipo, estado];
}
