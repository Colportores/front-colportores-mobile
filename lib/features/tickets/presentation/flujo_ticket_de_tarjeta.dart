import 'package:flutter/material.dart';

import '../../cobranzas/domain/entities/cobranza.dart';
import 'pages/ticket_de_tarjeta_page.dart';

export 'pages/ticket_de_tarjeta_page.dart' show ResultadoDelFlujoDeTicket;

/// El punto de entrada de la foto del ticket de tarjeta (vista 29, grupo C, HU-COB-007): lo abre el
/// cobro con tarjeta registrado (29A·03, «Sacar foto del ticket») y, más adelante, el detalle del
/// cobro con «Falta el ticket» (vista 30, #424).
///
/// Se abre con el cobro ya resuelto: no vuelve a pedir persona ni venta. Al terminar («Listo») o con
/// «Después» el que lo abrió vuelve a la hoja de la casa; si se cierra la cámara sin sacar nada
/// ([ResultadoDelFlujoDeTicket.cancelado]) sigue donde estaba.
abstract final class FlujoTicketDeTarjeta {
  static Future<ResultadoDelFlujoDeTicket> abrir(
    BuildContext context, {
    required Cobranza cobro,
    required String colportorId,
    String? subtitulo,
  }) async {
    final resultado = await Navigator.of(context).push<ResultadoDelFlujoDeTicket>(
      MaterialPageRoute(
        builder: (_) => TicketDeTarjetaPage(
          cobroId: cobro.id,
          colportorId: colportorId,
          montoDelCobroCentavos: cobro.montoCentavos,
          fechaDelCobro: cobro.fecha,
          tarjetaTipo: cobro.tarjetaTipo,
          tarjetaMarca: cobro.tarjetaMarca,
          numeroAprobacion: cobro.numeroAprobacion,
          subtitulo: subtitulo,
        ),
      ),
    );
    return resultado ?? ResultadoDelFlujoDeTicket.cancelado;
  }
}
