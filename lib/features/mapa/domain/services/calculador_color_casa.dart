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
/// Hoy aportan las agendas y las visitas (prioridades 3, 5, 6 y 7). La venta, la entrega y la
/// cobranza (S9) suman las 1, 2 y 4: un parámetro nuevo acá, sin tocar a quien ya llama.
abstract final class CalculadorColorCasa {
  /// El color de una casa con [agendasPendientes] (los tipos de sus agendas que siguen esperando
  /// su visita) y [resultadosDeVisitas] (el resultado de cada una de sus visitas), o `null` si
  /// ninguna aporta un color: en ese caso la casa es «Sin visita», y no hay fila de `house_status`.
  ///
  /// - Una agenda pendiente **de entrevista** → 3, entrevista programada. La de **cobranza** no
  ///   pinta nada acá: «cobranza pendiente» (2) depende de que haya una venta con saldo (S9).
  /// - Una visita `ENTREVISTA` → 5, `NO_CONTESTO` → 6, `RECHAZO` → 7. La `VENTA` no aporta nada
  ///   hasta que la venta exista (S9: 4 si el saldo es 0, 1 o 2 si falta cobrar o entregar).
  static ColorHouseStatus? calcular({
    Iterable<TipoAgenda> agendasPendientes = const [],
    Iterable<TipoResultadoVisita> resultadosDeVisitas = const [],
  }) => ColorHouseStatus.elDeMayorPrioridad(
    [
      for (final tipo in agendasPendientes)
        if (tipo == TipoAgenda.entrevista) ColorHouseStatus.entrevistaProgramada,
      for (final resultado in resultadosDeVisitas)
        switch (resultado) {
          TipoResultadoVisita.entrevista => ColorHouseStatus.entrevistaSinVenta,
          TipoResultadoVisita.noContesto => ColorHouseStatus.sinContestar,
          TipoResultadoVisita.rechazo => ColorHouseStatus.rechazo,
          TipoResultadoVisita.venta => null,
        },
    ].whereType<ColorHouseStatus>(),
  );
}
