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
/// Aportan las agendas, las visitas, las ventas y sus entregas (prioridades 1 a 7). La cobranza
/// (HU-COB-001) suma el saldo real: hoy el saldo de una venta es su monto entero.
abstract final class CalculadorColorCasa {
  /// El color de una casa con [agendasPendientes] (los tipos de sus agendas que siguen esperando
  /// su visita) y [resultadosDeVisitas] (el resultado de cada una de sus visitas), o `null` si
  /// ninguna aporta un color: en ese caso la casa es «Sin visita», y no hay fila de `house_status`.
  ///
  /// - Una agenda pendiente **de entrevista** → 3, entrevista programada. La de **cobranza** no
  ///   pinta nada acá: «cobranza pendiente» (2) depende de que haya una venta con saldo (S9).
  /// - Una visita `ENTREVISTA` → 5, `NO_CONTESTO` → 6, `RECHAZO` → 7. La `VENTA` no aporta por sí
  ///   sola: pinta la venta ([ventas]). La `COBRANZA` tampoco: pinta el cobro (S9), no la visita.
  /// - Una venta ([VentaParaElColor]) pinta según su saldo y su entrega: con saldo y sin entregar →
  ///   1 (entrega y cobranza pendientes); con saldo y entregada → 2 (cobranza pendiente); sin saldo y
  ///   entregada → 4 (venta completa). Sin saldo y sin entregar no pinta por sí sola (la venta de
  ///   $ 0 todavía sin entregar espera la decisión de Cristian, #531 P2).
  static ColorHouseStatus? calcular({
    Iterable<TipoAgenda> agendasPendientes = const [],
    Iterable<TipoResultadoVisita> resultadosDeVisitas = const [],
    Iterable<VentaParaElColor> ventas = const [],
  }) => ColorHouseStatus.elDeMayorPrioridad(
    [
      for (final venta in ventas) venta.color,
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

/// Lo que el color de la casa necesita saber de una venta viva (ADR-003 §8.4, HU-VEN-002).
final class VentaParaElColor {
  const VentaParaElColor({required this.saldoCentavos, required this.entregada});

  /// Lo que falta cobrar, en centavos. Hasta que existan los cobros (HU-COB-001) es el monto de la
  /// venta entero.
  final int saldoCentavos;

  /// Se entregó todo: la venta tiene filas de entrega y ninguna sigue pendiente.
  final bool entregada;

  /// El color que aporta esta venta, o `null` si no pinta por sí sola.
  ColorHouseStatus? get color {
    if (saldoCentavos > 0) {
      return entregada
          ? ColorHouseStatus.cobranzaPendiente
          : ColorHouseStatus.entregaYCobranzaPendiente;
    }
    return entregada ? ColorHouseStatus.ventaCompleta : null;
  }
}
