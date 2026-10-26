import '../domain/entities/ubicacion.dart';
import 'providers/alta_ubicacion_notifier.dart';

/// Los textos de sumar una casa arrastrando el pin (vista 39, N·01 a N·03). Los literales salen del
/// canvas (`39 Casa en el Mapa.dc.html`); los que el canvas no dibuja son propuestas que guían (qué
/// pasa y qué hacer) y están anotados en el pendiente del issue #451.
abstract final class TextosAltaPorPin {
  // El pin (M·01): el botón de abajo a la derecha.
  /// Lo que dice el lector de pantalla del botón (el nombre del canvas), con la alternativa al
  /// arrastre: tocarlo lo deja en el centro del mapa (WCAG 2.5.7, movimientos de arrastre).
  static const pin =
      'Pin: arrastralo al mapa para sumar una casa. Tocalo para ponerlo en el centro del mapa.';

  /// La leyenda que el canvas pone junto al pin (M·01).
  static const pinLeyenda = 'Arrastrá para sumar una casa';

  /// Se soltó el pin sobre la lista o fuera del mapa: no se suma nada.
  static const soltalo = 'Soltá el pin sobre el mapa, arriba de la lista.';

  /// El pin que se está arrastrando o ya está puesto (lo dice el lector de pantalla).
  static const pinDeLaCasaNueva = 'Casa nueva. Arrastralo para moverla.';

  // N·01 «Soltar el pin: ¿está acá?»
  static const confirmarPosicion = 'Confirmar posición';
  static const cancelar = 'Cancelar';
  static const ayudaPosicion = 'Tocá el mapa o arrastrá el pin para ajustar el lugar.';
  static const buscandoDireccion = 'Buscando la dirección…';
  static const sinDireccion = 'Sin dirección en el mapa';

  // N·02 «¿Qué hay acá?»
  static const queHayAca = '¿Qué hay acá?';
  static const seguir = 'Seguir';
  static const volver = 'Volver';
  static const registrando = 'Registrando…';
  static const numero = 'NÚMERO';
  static const calle = 'CALLE · OPCIONAL';
  static const numeroDelMapa = 'Sacado del mapa. Corregilo si no coincide.';
  static const numeroSinMapa =
      'El mapa no tiene el número de este lugar. Podés ponerlo ahora o después.';
  static const numeroBuscando = 'Buscando el número en el mapa…';
  static const calleSinMapa = 'El mapa no tiene la calle de este lugar. Escribila si querés.';
  static const elegirCiudad = 'Elegir';
  static const sinCiudad = 'Sin ciudad';

  /// Cada tipo con su ayuda, tal cual el bloque `tipo` del canvas.
  static String ayudaDelTipo(TipoUbicacion tipo) => switch (tipo) {
    TipoUbicacion.casa => 'Una o varias personas',
    TipoUbicacion.edificio => 'Varios deptos',
    TipoUbicacion.negocio => 'Un comercio',
  };

  /// La dirección que se ve en el título de N·01 y debajo de «¿Qué hay acá?»: «Grecia 3307». Vacía si
  /// el mapa no tiene ni la calle ni el número.
  static String direccion(AltaUbicacionState estado) =>
      [estado.calle.texto.trim(), estado.numero.texto.trim()].where((p) => p.isNotEmpty).join(' ');
}
