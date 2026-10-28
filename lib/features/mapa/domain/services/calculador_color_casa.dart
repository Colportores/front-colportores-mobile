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
/// Hoy aportan las agendas y las visitas (prioridades 3, 5, 6 y 7). La venta, la entrega y la
/// cobranza (S9) suman las 1, 2 y 4: un parámetro nuevo acá, sin tocar a quien ya llama.
abstract final class CalculadorColorCasa {
  /// El color de una casa con [agendasPendientes] (los tipos de sus agendas que siguen esperando
  /// su visita) y [resultadosDeVisitas] (el resultado y la fecha de cada una de sus visitas), o
  /// `null` si ninguna aporta un color: en ese caso la casa es «Sin visita», y no hay fila de
  /// `house_status`.
  ///
  /// - Una agenda pendiente **de entrevista** → 3, entrevista programada. La de **cobranza** no
  ///   pinta nada acá: «cobranza pendiente» (2) depende de que haya una venta con saldo (S9).
  /// - Una visita `ENTREVISTA` → 5, `NO_CONTESTO` → 6, `RECHAZO` → 7, y de todas esas **vale la
  ///   más reciente**. La `VENTA` no aporta nada hasta que la venta exista (S9: 4 si el saldo es 0,
  ///   1 o 2 si falta cobrar o entregar) y no desplaza a ninguna de las tres. La `COBRANZA`
  ///   tampoco: pinta el cobro (S9), no la visita.
  static ColorHouseStatus? calcular({
    Iterable<TipoAgenda> agendasPendientes = const [],
    Iterable<ResultadoDeVisitaFechado> resultadosDeVisitas = const [],
  }) => ColorHouseStatus.elDeMayorPrioridad(
    [
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
