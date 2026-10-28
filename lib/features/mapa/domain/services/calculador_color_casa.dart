import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/entities/visita.dart';
import '../entities/color_house_status.dart';

/// El resultado de una visita y cuándo fue: lo único que la regla del color necesita de ella.
typedef ResultadoDeVisitaFechado = ({TipoResultadoVisita resultado, DateTime fecha});

/// La regla de prioridad de ADR-003 (§8.4): qué color le toca a una casa según lo que pasó en ella.
/// Es la única; la capa `data` solo junta los hechos (`HouseStatusUpdaterDrift`) y se la pregunta
/// acá.
///
/// Cada hecho de la casa aporta un color y **gana el de mayor prioridad** (el número más chico),
/// con independencia del orden en que ocurrieron o llegaron: así el resultado no depende del orden
/// de la cola ni de un reintento, y una agenda que se cancela o se cumple devuelve la casa al color
/// que le corresponde sin mirar la historia.
///
/// **Excepción: entre los resultados de visita 5, 6 y 7 manda el último** (decisión de Cristian,
/// 23/10, «Rojo o verde»): la entrevista dada, el «no contestó» y el rechazo compiten por su fecha
/// y no por su número, así que un rechazo posterior a la entrevista deja la casa roja y la
/// entrevista queda en el historial. Lo pendiente (1, 2 y 3) y la venta completa (4) siguen por
/// encima de cualquiera de los tres. El resultado sigue sin depender del orden en que llegan los
/// datos: la fecha de la visita decide, y a igual instante gana la de número más chico.
///
/// Aportan las agendas, las visitas y las ventas (prioridades 1, 3, 5, 6 y 7). La entrega y la cobranza
/// (HU-VEN-002, HU-COB-001) suman las 2 y 4: un parámetro nuevo acá, sin tocar a quien ya llama.
abstract final class CalculadorColorCasa {
  /// El color de una casa con [agendasPendientes] (los tipos de sus agendas que siguen esperando
  /// su visita) y [resultadosDeVisitas] (el resultado y la fecha de cada una de sus visitas), o
  /// `null` si ninguna aporta un color: en ese caso la casa es «Sin visita», y no hay fila de
  /// `house_status`.
  ///
  /// - Una agenda pendiente **de entrevista** → 3, entrevista programada. La de **cobranza** no
  ///   pinta nada acá: «cobranza pendiente» (2) depende de que haya una venta con saldo (S9).
  /// - Una visita `ENTREVISTA` → 5, `NO_CONTESTO` → 6, `RECHAZO` → 7, y de todas esas **vale la
  ///   más reciente**. La `VENTA` no aporta por sí sola (pinta la venta, [montosDeVentas]) y no
  ///   desplaza a ninguna de las tres. La `COBRANZA` tampoco: pinta el cobro (S9), no la visita.
  /// - Una venta con monto mayor a cero → 1 hasta que haya entrega y cobro (ver arriba).
  static ColorHouseStatus? calcular({
    Iterable<TipoAgenda> agendasPendientes = const [],
    Iterable<ResultadoDeVisitaFechado> resultadosDeVisitas = const [],
    Iterable<int> montosDeVentas = const [],
  }) => ColorHouseStatus.elDeMayorPrioridad(
    [
      // Una venta con algo para cobrar, sin entrega ni cobro registrados todavía (esas tablas llegan
      // con HU-VEN-002 y HU-COB-001): entrega y cobranza pendientes (1). Una venta de $ 0 (solo
      // misioneros, que no cuentan como venta) no pinta por sí sola: la casa queda «entrevista dada».
      for (final monto in montosDeVentas)
        if (monto > 0) ColorHouseStatus.entregaYCobranzaPendiente,
      for (final tipo in agendasPendientes)
        if (tipo == TipoAgenda.entrevista) ColorHouseStatus.entrevistaProgramada,
      _colorDeLaUltimaVisita(resultadosDeVisitas),
    ].whereType<ColorHouseStatus>(),
  );

  /// El color de la visita más reciente entre las que pintan (entrevista dada, sin contestar,
  /// rechazo), o `null` si no hay ninguna. A igual fecha, el de número más chico: el desempate no
  /// depende del orden de la lista.
  static ColorHouseStatus? _colorDeLaUltimaVisita(Iterable<ResultadoDeVisitaFechado> visitas) {
    ColorHouseStatus? color;
    DateTime? fecha;
    for (final (:resultado, fecha: cuando) in visitas) {
      final deEsta = switch (resultado) {
        TipoResultadoVisita.entrevista => ColorHouseStatus.entrevistaSinVenta,
        TipoResultadoVisita.noContesto => ColorHouseStatus.sinContestar,
        TipoResultadoVisita.rechazo => ColorHouseStatus.rechazo,
        TipoResultadoVisita.venta || TipoResultadoVisita.cobranza => null,
      };
      if (deEsta == null) continue;
      final esMasNueva = fecha == null || cuando.isAfter(fecha);
      final empata = fecha != null && cuando.isAtSameMomentAs(fecha);
      if (esMasNueva || (empata && deEsta.prioridad < color!.prioridad)) {
        color = deEsta;
        fecha = cuando;
      }
    }
    return color;
  }
}
