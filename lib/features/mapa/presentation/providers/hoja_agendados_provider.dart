import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../agenda/domain/entities/tipo_agenda.dart';

/// Las dos pestañas de la hoja del mapa (vista 06): «Cercanía», las ubicaciones de la más cercana a
/// la más lejana, y «Agendados», las visitas agendadas (06C·03).
enum PestanaHojaMapa { cercania, agendados }

/// Qué muestra la hoja del mapa: la pestaña y, en «Agendados», el chip de tipo elegido (`null` =
/// «Todos»).
final class HojaDelMapaState extends Equatable {
  const HojaDelMapaState({this.pestana = PestanaHojaMapa.cercania, this.tipo});

  final PestanaHojaMapa pestana;
  final TipoAgenda? tipo;

  bool get enAgendados => pestana == PestanaHojaMapa.agendados;

  @override
  List<Object?> get props => [pestana, tipo];
}

/// La pestaña y el filtro de la hoja del mapa del colportor. Se conservan mientras la pestaña «Mapa»
/// está montada (vive en el `IndexedStack` de la pantalla principal): cambiar de pestaña y volver no
/// los pierde.
///
/// El filtro de tipo es de la hoja y no el de la pestaña Agenda: el canvas le dibuja chips propios
/// («Todos», «Cobranzas», «Entrevistas» y «Entregas», con su cuenta) y ningún filtro de estado.
final class HojaDelMapaNotifier extends Notifier<HojaDelMapaState> {
  HojaDelMapaNotifier(this.colportorId);

  final String colportorId;

  @override
  HojaDelMapaState build() => const HojaDelMapaState();

  void elegirPestana(PestanaHojaMapa pestana) {
    if (pestana == state.pestana) return;
    state = HojaDelMapaState(pestana: pestana, tipo: state.tipo);
  }

  /// `null` = «Todos».
  void elegirTipo(TipoAgenda? tipo) {
    if (tipo == state.tipo) return;
    state = HojaDelMapaState(pestana: state.pestana, tipo: tipo);
  }
}

final hojaDelMapaProvider = NotifierProvider.autoDispose
    .family<HojaDelMapaNotifier, HojaDelMapaState, String>(HojaDelMapaNotifier.new);
