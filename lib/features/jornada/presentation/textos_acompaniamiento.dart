import '../domain/entities/acompaniante.dart';

/// Los textos del acompañamiento de la jornada (vista 20, 20J·01 a 20J·07; HU-JOR-003) y de la tendencia
/// del cierre (vista 21, 21J·01 a 21J·04). Lo que viene del canvas va literal; lo demás se anota como
/// propuesta en el PR.
abstract final class TextosAcompaniamiento {
  static const pregunta = '¿Te acompañó alguien?';

  /// Solo coordinadores (decisión de Cristian, 09/11, «Lista acomp.»): el canvas decía «o administrador».
  ///
  /// Sin saber cuál es la campaña de la jornada la lista trae los de todas sus campañas, y el texto lo dice
  /// («Lista acomp.» y decisión del 26/11 sobre «Campaña desconocida»).
  static String ayudaDelInterruptor({bool campaniaConocida = true}) =>
      campaniaConocida ? 'Coordinador de tu campaña' : 'Coordinador de tus campañas';

  static const tituloDeLaHoja = '¿Quién te acompaña?';

  static const ayudaDeLaHoja = 'Elegí a quien te acompañó. Si fueron dos o más, marcalos a todos.';

  static String rolDeLaLista({bool campaniaConocida = true}) =>
      campaniaConocida ? 'Coordinación de tu campaña' : 'Coordinación de tus campañas';

  static const listo = 'Listo';
  static const cancelar = 'Cancelar';
  static const cerrar = 'Cerrar';
  static const cambiar = 'Cambiar';
  static const reintentar = 'Reintentar';
  static const nadieMeAcompanio = 'Nadie me acompañó';

  /// 20J·05, lista vacía.
  static const listaVacia =
      'Todavía no recibimos la lista de coordinadores de tu campaña. Se actualiza cuando haya conexión.';

  static const cargandoLaLista = 'Cargando la lista…';

  static const noPudimosLeerLaLista =
      'No pudimos leer la lista de coordinadores. Probá de nuevo; si sigue pasando, avisale a tu coordinador.';

  /// 20J·07, error al guardar.
  static const noPudimosGuardar = 'No pudimos guardar el acompañamiento. Probá de nuevo.';

  static const noPudimosLeerElAcompaniamiento =
      'No pudimos leer quién te acompaña. Tus datos siguen guardados en este teléfono. Probá de nuevo.';

  static const guardando = 'Guardando…';

  /// La persona que ya figuraba pero que el teléfono no tiene en su lista (dejó de contar): se muestra para
  /// poder sacarla.
  static const personaSinNombre = 'Acompañante';

  static String teAcompania(int cuantos) => cuantos == 1 ? 'TE ACOMPAÑA' : 'TE ACOMPAÑAN';

  /// 20J·03: «Anotamos que te acompaña Marta.»; con varios, «…te acompañan Marta y Daniel.».
  static String anotado(List<Acompaniante> quienes) {
    if (quienes.isEmpty) return 'Anotamos que nadie te acompañó.';
    final nombres = [
      for (final q in quienes) q.nombre?.trim().isNotEmpty == true ? q.nombre!.trim() : 'alguien',
    ];
    final lista = nombres.length == 1
        ? nombres.first
        : '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
    return 'Anotamos que te ${nombres.length == 1 ? 'acompaña' : 'acompañan'} $lista.';
  }

  /// 21J·03: «Te acompañó: Marta Pérez» / «Nadie».
  static String teAcompanioA(List<Acompaniante> quienes) => quienes.isEmpty
      ? 'Nadie'
      : [for (final q in quienes) q.nombreCompleto ?? personaSinNombre].join(', ');

  static const teAcompanio = 'Te acompañó';

  /// 21J·03, el aviso del cierre.
  static const avisoSiTeOlvidaste =
      'Si alguien te acompañó y no lo marcaste, avisale a tu coordinador: lo agrega desde el panel.';

  // La tendencia del cierre (vista 21).
  static const contraLaAnterior = 'CONTRA TU JORNADA ANTERIOR';
  static const tuJornada = 'TU JORNADA';
  static const casasVisitadas = 'Casas visitadas';
  static const ventas = 'Ventas';
  static const primeraJornada =
      'Es tu primera jornada: desde mañana te mostramos cómo vas contra la anterior.';

  /// «▲ 3» / «▼ 1» / «= igual»: el signo va además del color.
  static String variacion(int diferencia) => diferencia > 0
      ? '▲ $diferencia'
      : diferencia < 0
      ? '▼ ${-diferencia}'
      : '= igual';

  /// Lo que lee el lector de pantalla de una fila de la tendencia.
  static String variacionHablada(int diferencia) => diferencia > 0
      ? '$diferencia más que en tu jornada anterior'
      : diferencia < 0
      ? '${-diferencia} menos que en tu jornada anterior'
      : 'igual que en tu jornada anterior';
}
