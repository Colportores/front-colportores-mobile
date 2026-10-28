import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/entities/visita.dart';
import '../entities/color_house_status.dart';

/// La regla de prioridad de ADR-003 (§8.4): qué color le toca a una casa según lo que pasó en ella.
/// Es la única; la capa `data` solo junta los hechos (`HouseStatusUpdaterDrift`) y se la pregunta
/// acá.
///
/// Cada hecho de la casa aporta un color y **gana el de mayor prioridad** (el número más chico),
/// con independencia del orden en que ocurrieron o llegaron: así el resultado no depende del orden
/// de la cola ni de un reintento, y una agenda que se cancela o se cumple devuelve la casa al color
/// que le corresponde sin mirar la historia.
///
/// Aportan las agendas, las visitas, las ventas y sus cobros (prioridades 1, 3, 4, 5, 6 y 7). La
/// entrega (HU-VEN-002) suma la 2 y afina la 4: un parámetro nuevo acá, sin tocar a quien ya llama.
abstract final class CalculadorColorCasa {
  /// El color de una casa con [agendasPendientes] (los tipos de sus agendas que siguen esperando
  /// su visita) y [resultadosDeVisitas] (el resultado de cada una de sus visitas), o `null` si
  /// ninguna aporta un color: en ese caso la casa es «Sin visita», y no hay fila de `house_status`.
  ///
  /// - Una agenda pendiente **de entrevista** → 3, entrevista programada. La de **cobranza** no
  ///   pinta nada acá: «cobranza pendiente» (2) depende de que haya una venta con saldo (S9).
  /// - Una visita `ENTREVISTA` → 5, `NO_CONTESTO` → 6, `RECHAZO` → 7. La `VENTA` no aporta por sí
  ///   sola: pinta la venta ([montosDeVentas]). La `COBRANZA` tampoco: pinta el cobro (S9), no la
  ///   visita.
  /// - Una venta con monto mayor a cero → 1 hasta que haya entrega y cobro (ver arriba).
  static ColorHouseStatus? calcular({
    Iterable<TipoAgenda> agendasPendientes = const [],
    Iterable<TipoResultadoVisita> resultadosDeVisitas = const [],
    Iterable<int> montosDeVentas = const [],
    Iterable<({int montoCentavos, int cobradoCentavos})> ventas = const [],
  }) => ColorHouseStatus.elDeMayorPrioridad(
    [
      // Una venta con cobros (HU-COB-001): con saldo sigue pendiente (1; la entrega todavía no se
      // registra en el teléfono, así que no se distingue la cobranza sola, 2) y con el saldo en cero
      // es una venta completa (4). Una venta de $ 0 no pinta.
      for (final venta in ventas)
        if (venta.montoCentavos > 0)
          if (venta.cobradoCentavos >= venta.montoCentavos)
            ColorHouseStatus.ventaCompleta
          else
            ColorHouseStatus.entregaYCobranzaPendiente,
      // Una venta con algo para cobrar, sin entrega ni cobro registrados todavía (esas tablas llegan
      // con HU-VEN-002 y HU-COB-001): entrega y cobranza pendientes (1). Una venta de $ 0 (todo lo
      // regalado) no pide cobrar nada y no pinta por sí sola.
      for (final monto in montosDeVentas)
        if (monto > 0) ColorHouseStatus.entregaYCobranzaPendiente,
      for (final tipo in agendasPendientes)
        if (tipo == TipoAgenda.entrevista) ColorHouseStatus.entrevistaProgramada,
      for (final resultado in resultadosDeVisitas)
        switch (resultado) {
          TipoResultadoVisita.entrevista => ColorHouseStatus.entrevistaSinVenta,
          TipoResultadoVisita.noContesto => ColorHouseStatus.sinContestar,
          TipoResultadoVisita.rechazo => ColorHouseStatus.rechazo,
          TipoResultadoVisita.venta || TipoResultadoVisita.cobranza => null,
        },
    ].whereType<ColorHouseStatus>(),
  );
}
