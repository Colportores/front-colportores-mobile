import '../entities/entrevista_cercana.dart';
import '../entities/franja_horaria.dart';
import '../entities/sugerencia_de_fecha.dart';

/// Elige la fecha que se sugiere al agendar una entrevista, a partir de las entrevistas que el teléfono
/// ya tiene agendadas cerca de la casa (vista 39, R·02). Función pura: la lectura de las entrevistas
/// cercanas y la distancia son de otro lado (`EntrevistasCercanasRepository`).
///
/// **Criterio** (un solo punto, decisión pendiente marcada «mapa §2» en el PR de #513):
///
/// - se agrupan por día (hora local);
/// - gana el día con **más** entrevistas; con igual cantidad, el más próximo;
/// - la franja es la que más se repite ese día (con empate, la más temprana); la hora sugerida es el
///   comienzo de esa franja. Si ninguna entrevista cae en una franja, la hora de la más temprana;
/// - un día cuyo momento sugerido ya pasó no se sugiere (no se le ofrece a nadie una hora vencida);
/// - sin entrevistas cerca, o sin ningún día que sirva, `null`: no se sugiere nada.
abstract final class SugeridorDeFecha {
  static SugerenciaDeFecha? calcular(
    Iterable<EntrevistaCercana> cercanas, {
    required DateTime ahora,
  }) {
    final alMinuto = DateTime(ahora.year, ahora.month, ahora.day, ahora.hour, ahora.minute);
    final porDia = <DateTime, List<DateTime>>{};
    final slots = <DateTime, List<String?>>{};
    for (final e in cercanas) {
      final f = e.fecha.toLocal();
      if (f.isBefore(alMinuto)) continue;
      final dia = DateTime(f.year, f.month, f.day);
      (porDia[dia] ??= []).add(f);
      (slots[dia] ??= []).add(e.slotCodigo);
    }

    SugerenciaDeFecha? mejor;
    for (final dia in porDia.keys) {
      final fechas = porDia[dia]!..sort();
      final franja = _franjaMasRepetida(fechas, slots[dia]!);
      final momento = franja == null
          ? fechas.first
          : DateTime(dia.year, dia.month, dia.day, franja.desde ~/ 60, franja.desde % 60);
      if (momento.isBefore(alMinuto)) continue;
      final candidata = SugerenciaDeFecha(
        momento: momento,
        cantidad: fechas.length,
        franja: franja,
      );
      if (mejor == null ||
          candidata.cantidad > mejor.cantidad ||
          (candidata.cantidad == mejor.cantidad && candidata.momento.isBefore(mejor.momento))) {
        mejor = candidata;
      }
    }
    return mejor;
  }

  /// La franja que más entrevistas tiene; con empate, la más temprana. La franja de una entrevista es
  /// la que se guardó o, si no hay, la que se le recomendaría por su hora.
  static FranjaHoraria? _franjaMasRepetida(List<DateTime> fechas, List<String?> codigos) {
    final cuenta = <FranjaHoraria, int>{};
    for (var i = 0; i < fechas.length; i++) {
      final franja =
          FranjaHoraria.desdeCodigo(codigos[i]) ??
          FranjaHoraria.sugeridaPara(fechas[i].hour * 60 + fechas[i].minute);
      if (franja != null) cuenta[franja] = (cuenta[franja] ?? 0) + 1;
    }
    FranjaHoraria? elegida;
    for (final f in FranjaHoraria.values) {
      final n = cuenta[f] ?? 0;
      if (n > 0 && (elegida == null || n > cuenta[elegida]!)) elegida = f;
    }
    return elegida;
  }
}
