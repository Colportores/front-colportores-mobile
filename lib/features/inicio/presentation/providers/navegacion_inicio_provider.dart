import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/barra_pestanas_inicio.dart' show PestanaInicio;

/// Qué le pide al mapa principal quien llama a [NavegacionInicioNotifier.irALaCasa] o a
/// [NavegacionInicioNotifier.volverAlMapa].
///
/// Es una clase sin `==` a propósito: pedir dos veces lo mismo (la misma casa) es una intención nueva
/// y los `ref.listen` tienen que enterarse.
final class IntencionDelMapa {
  const IntencionDelMapa._(this.ubicacionId, {required this.conSuHoja});

  /// La casa a la que se lleva al mapa.
  final String ubicacionId;

  /// `true`: «ir a la casa» (C·01): el mapa la centra, la selecciona y sube su hoja. `false`: «tras
  /// guardar» (decisión de Cristian, 05/11): el mapa queda libre, sin hoja, con la casa a la vista
  /// y su marcador en el color nuevo.
  final bool conSuHoja;
}

/// La navegación de la pantalla principal: la pestaña a la vista y lo que se le pidió al mapa.
class NavegacionInicio {
  const NavegacionInicio({this.actual = PestanaInicio.hoy, this.intencion});

  /// La pestaña a la vista de la barra inferior.
  final PestanaInicio actual;

  /// Lo que el mapa principal todavía no atendió. Queda pendiente mientras el mapa no esté listo (la
  /// pestaña se arma al abrirse y el mapa nativo tarda en crearse) y el mapa la toma al atenderla.
  final IntencionDelMapa? intencion;
}

/// El shell de Inicio (`InicioPage`): la pestaña actual y las intenciones sobre el mapa principal.
///
/// Hay **un solo mapa general** y todo lo demás son hojas y modos encima (decisión de Cristian,
/// 04/11): las otras pestañas no abren mapas propios, le piden al shell que lleve a la casa al mapa
/// principal. La cámara solo se mueve por una intención explícita de acá, nunca por un cambio de datos.
class NavegacionInicioNotifier extends Notifier<NavegacionInicio> {
  @override
  NavegacionInicio build() => const NavegacionInicio();

  /// Vuelve a «Hoy» y suelta lo pendiente. Lo hace la pantalla principal al armarse: como el provider
  /// vive toda la sesión, sin esto una sesión nueva (cerrar sesión y entrar) arrancaría en la
  /// pestaña donde quedó la anterior.
  void reiniciar() {
    if (state.actual == PestanaInicio.hoy && state.intencion == null) return;
    state = const NavegacionInicio();
  }

  /// Cambia de pestaña. Una intención que el mapa no llegó a atender se descarta: no se aplica de
  /// golpe cuando el colportor vuelva al mapa por su cuenta.
  void ir(PestanaInicio pestana) {
    if (state.actual == pestana && state.intencion == null) return;
    state = NavegacionInicio(actual: pestana);
  }

  /// «Ir a la casa» (C·01): lleva a [ubicacionId] al mapa principal, desde cualquier pestaña. El mapa
  /// la centra, la selecciona y sube su hoja (el resumen). Si el mapa todavía no se armó, la
  /// intención queda pendiente y se aplica cuando está listo.
  void irALaCasa(String ubicacionId) => state = NavegacionInicio(
    actual: PestanaInicio.mapa,
    intencion: IntencionDelMapa._(ubicacionId, conSuHoja: true),
  );

  /// «Tras guardar» una acción de la hoja de la casa —el resultado de la visita, el fin de la
  /// entrevista, una venta, un cobro, una agenda— (decisión de Cristian, 05/11): deja la pestaña Mapa
  /// activa y libre, sin hoja, con [ubicacionId] a la vista y su color nuevo. Para seguir con la
  /// misma casa, la colportora la vuelve a tocar.
  void volverAlMapa(String ubicacionId) => state = NavegacionInicio(
    actual: PestanaInicio.mapa,
    intencion: IntencionDelMapa._(ubicacionId, conSuHoja: false),
  );

  /// El mapa atendió [intencion]. Si mientras tanto llegó otra, esa se conserva.
  void atendida(IntencionDelMapa intencion) {
    if (!identical(state.intencion, intencion)) return;
    state = NavegacionInicio(actual: state.actual);
  }
}

/// Ver [NavegacionInicioNotifier]. Vive toda la sesión (`keepAlive`): la pestaña que se eligió no
/// se pierde cuando el shell se reconstruye.
final navegacionInicioProvider = NotifierProvider<NavegacionInicioNotifier, NavegacionInicio>(
  NavegacionInicioNotifier.new,
);
