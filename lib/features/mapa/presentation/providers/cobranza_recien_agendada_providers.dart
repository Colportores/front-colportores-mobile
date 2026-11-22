import 'package:flutter_riverpod/flutter_riverpod.dart';

/// La cobranza que se agendó al guardar una venta (vista 39, R·08): la hoja de la casa la dibuja
/// como una tarjeta con «Cambiar» en vez de repetirla en «Visitas agendadas».
///
/// Lleva el nombre de quien debe porque la tarjeta dice «Cobranza · Pedro». No es un dato
/// persistente: la hoja lo toma una vez al abrirse y lo suelta.
typedef CobranzaRecienAgendada = ({String ubicacionId, String agendaId, String persona});

/// Quien agenda la cobranza ([marcar]) y la hoja de esa casa ([consumir]).
class CobranzaRecienAgendadaNotifier extends Notifier<CobranzaRecienAgendada?> {
  @override
  CobranzaRecienAgendada? build() => null;

  void marcar(CobranzaRecienAgendada cobranza) => state = cobranza;

  void consumir() => state = null;
}

final cobranzaRecienAgendadaProvider =
    NotifierProvider<CobranzaRecienAgendadaNotifier, CobranzaRecienAgendada?>(
      CobranzaRecienAgendadaNotifier.new,
    );
