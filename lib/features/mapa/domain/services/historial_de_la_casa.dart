import '../../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../entities/evento_de_la_casa.dart';

/// De dónde sale todo lo que pasó en una casa (la pestaña Historial de la hoja arriba, vista 39 C·03).
/// Local: las visitas, las ventas y los cobros viven en el teléfono.
abstract interface class HistorialDeLaCasa {
  /// Lo que pasó en el espacio [espacioId] (la casa, el negocio o el depto), el más nuevo primero,
  /// al día cuando cambia cualquiera de las tablas que lo componen. Un error de lectura sale por el
  /// `Stream`.
  Stream<List<EventoDeLaCasa>> observar(String espacioId);
}

/// Mientras no haya de dónde leerlo (los tests): no se sabe nada.
final class HistorialDeLaCasaSinFuente implements HistorialDeLaCasa {
  const HistorialDeLaCasaSinFuente();

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) => Stream.value(const <EventoDeLaCasa>[]);
}

/// Por qué se filtra el historial de la casa (vista 39, C·03: «Todo / Entrevistas / Ventas / Cobros»).
enum FiltroDeLaCasa {
  /// Sin filtro: todo lo que pasó.
  todo,

  /// Las entrevistas dadas.
  entrevistas,

  /// Las ventas.
  ventas,

  /// Los cobros y las visitas de cobranza.
  cobros,
}

/// Aplica un [FiltroDeLaCasa] al historial de la casa, sin cambiarle el orden.
///
/// - [FiltroDeLaCasa.entrevistas]: las visitas con la entrevista dada.
/// - [FiltroDeLaCasa.ventas]: las ventas (y una visita de venta que quedó sin su venta).
/// - [FiltroDeLaCasa.cobros]: los cobros y las visitas de cobranza.
/// - «No contestó» y «Rechazo» no tienen filtro propio en el canvas: se ven en [FiltroDeLaCasa.todo].
abstract final class FiltroDelHistorialDeLaCasa {
  static List<EventoDeLaCasa> aplicar(List<EventoDeLaCasa> eventos, FiltroDeLaCasa filtro) {
    if (filtro == FiltroDeLaCasa.todo) return eventos;
    return [
      for (final e in eventos)
        if (_entra(e, filtro)) e,
    ];
  }

  static bool _entra(EventoDeLaCasa e, FiltroDeLaCasa filtro) => switch ((filtro, e)) {
    (FiltroDeLaCasa.todo, _) => true,
    (FiltroDeLaCasa.entrevistas, VisitaDeLaCasa(:final resultado)) =>
      resultado == TipoResultadoVisita.entrevista,
    (FiltroDeLaCasa.ventas, VentaDeLaCasa()) => true,
    (FiltroDeLaCasa.ventas, VisitaDeLaCasa(:final resultado)) =>
      resultado == TipoResultadoVisita.venta,
    (FiltroDeLaCasa.cobros, CobroDeLaCasa()) => true,
    (FiltroDeLaCasa.cobros, VisitaDeLaCasa(:final resultado)) =>
      resultado == TipoResultadoVisita.cobranza,
    _ => false,
  };
}
