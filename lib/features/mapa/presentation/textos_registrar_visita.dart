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

  /// «Registrar visita» sobre un edificio: el depto se elige antes (#452) y todavía no está.
  static const edificioSinDepto =
      'Todavía no se pueden registrar visitas en un edificio desde acá.';

  /// «+ Agendar» sobre un edificio (hoja de la casa y selector de la pestaña Agenda): el depto se
  /// elige antes (#452) y todavía no está.
  static const edificioSinDeptoParaAgendar =
      'Todavía no se puede agendar en un edificio desde acá.';

  /// El resultado se deshizo.
  static String seDeshizo(String direccion) => 'Se deshizo. $direccion vuelve a como estaba.';

  /// «Deshacer» no pudo: la visita sigue guardada.
  static const noPudimosDeshacer = 'No pudimos deshacer. La visita quedó guardada.';

  /// Lo que lee el lector de pantalla de un renglón: «No contestó. Guarda y vuelve al mapa».
  static String renglonParaLector(String titulo, String ayuda) => '$titulo. $ayuda';
}
