import 'formato_baja.dart';

/// Los textos de «Registrar visita: ¿qué pasó?» (vista 39, C·06) y del aviso «Guardado» (R·01). Los
/// del canvas van letra por letra; los que el canvas no dibuja (guardar, falla, deshacer, edificio) son
/// propuestas que quedan marcadas en el PR (mapa §2: texto/aviso).
abstract final class TextosRegistrarVisita {
  // C·06 — la hoja.
  static const titulo = '¿Qué pasó?';
  static const cancelar = 'Cancelar';

  static const noContesto = 'No contestó';
  static const rechazo = 'Rechazo';
  static const programarEntrevista = 'Programar entrevista';
  static const entrevistaDada = 'Entrevista dada';
  static const cobranza = 'Cobranza';

  /// «Vender» no está en el canvas de C·06: lo pide la decisión de Cristian del 04/11 («Vender desde el
  /// mapa»), que manda sobre el artboard. Texto propuesto (mapa §2: texto/aviso).
  static const vender = 'Vender';

  static const ayudaGuardaYVuelve = 'Guarda y vuelve al mapa';
  static const ayudaProgramar = 'Elegís día y franja';
  static const ayudaEntrevistaDada = 'Empieza a contar el tiempo';

  /// La ayuda de «Cobranza»: «Pedro Gómez debe $ 1.200». El canvas escribe el monto como «\$ 1.200»; las
  /// vistas aprobadas de baja escriben «\$U 1.200» (mapa §2: coherencia entre pantallas): un solo punto
  /// para cambiarlo.
  static String ayudaCobranza(String persona, int centavos) =>
      '$persona debe ${FormatoBaja.monto(centavos).replaceFirst(r'$U', r'$')}';

  /// La ayuda de «Vender» cuando en la casa hay más de una persona entrevistada: no se elige sola, se
  /// pregunta a quién en el paso siguiente. Texto propuesto (mapa §2: texto/aviso).
  static const ayudaVenderVarias = 'Elegís a quién le vendés';

  /// «Vender» cuando las personas entrevistadas se dieron de baja desde que se abrió «¿Qué pasó?»: no hay
  /// a quién venderle. Dice qué pasó y qué hacer (mapa §2: texto/aviso; texto del issue front-colportores-mobile#669).
  static const nadieParaVender =
      'Ya no queda ninguna persona entrevistada en esta casa. Elegí otra opción.';

  /// La ayuda de «Vender»: «Registrar la venta de Pedro Gómez».
  static String ayudaVender(String persona) => persona.trim().isEmpty
      ? 'Registrar la venta de la entrevista'
      : 'Registrar la venta de ${persona.trim()}';

  // R·01 — el aviso «Guardado».
  static String guardado(String direccion, String resultado) =>
      'Guardado. $direccion quedó como «$resultado».';
  static const deshacer = 'Deshacer';

  /// Cuánto dura el aviso con «Deshacer» (8 s, como el de reactivar una casa; sin lector de pantalla).
  static const duracionDeshacer = Duration(seconds: 8);

  /// Lo que dice el aviso de cada resultado que se guarda de un toque.
  static const resultadoNoContesto = noContesto;
  static const resultadoRechazo = rechazo;

  // Lo que el canvas no dibuja.

  /// Mientras se guarda, el renglón elegido (la acción no se puede repetir).
  static const guardando = 'Guardando…';

  /// Falla al guardar: qué pasó y qué hacer.
  static const noPudimosGuardar = 'No pudimos guardar la visita. Probá de nuevo.';

  /// La casa que se visitaba ya no está en el teléfono (la dieron de baja desde otra pantalla).
  static const casaNoEstaMas =
      'Esta casa ya no está en tu teléfono. Cerrá esta hoja y volvé a abrir la casa.';

  /// «¿Qué pasó en el 2A?» (vista 39, N·07): «¿Qué pasó?» en un depto, con su número. A confirmar (mapa
  /// §2: texto): un depto sin número (el canvas no lo dibuja) dice «¿Qué pasó en este depto?».
  static String tituloDelDepto(String? numeroDepto) {
    final numero = numeroDepto?.trim() ?? '';
    return numero.isEmpty ? '¿Qué pasó en este depto?' : '¿Qué pasó en el $numero?';
  }

  /// «Registrar visita» sin el depto elegido (en un edificio todo es por depto, vista 39 C·09). Desde
  /// la hoja de la casa ya no pasa: el depto se elige en la lista de deptos. A confirmar (mapa §2:
  /// texto): dice cómo seguir.
  static const edificioSinDepto =
      'Elegí el depto en la lista del edificio para registrar la visita.';

  /// «+ Agendar» de la pestaña Agenda sobre un edificio, o un negocio con más de un espacio: la cita es
  /// de un depto, y el depto se elige en la hoja del edificio (vista 39, C·09 → C·10 «+ Agendar»). A
  /// confirmar (mapa §2: texto): dice cómo seguir.
  static const edificioSinDeptoParaAgendar =
      'Para agendar en un edificio, tocalo en el Mapa, elegí el depto y tocá «+ Agendar».';

  /// El resultado se deshizo.
  static String seDeshizo(String direccion) => 'Se deshizo. $direccion vuelve a como estaba.';

  /// «Deshacer» no pudo: la visita sigue guardada.
  static const noPudimosDeshacer = 'No pudimos deshacer. La visita quedó guardada.';

  /// Lo que lee el lector de pantalla de un renglón: «No contestó. Guarda y vuelve al mapa».
  static String renglonParaLector(String titulo, String ayuda) => '$titulo. $ayuda';
}
