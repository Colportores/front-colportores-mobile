import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Los nombres de las pantallas que son una capa del propio mapa: el alta y «Modificar» se abren
/// encima de la pestaña Mapa pero siguen siendo el mapa (decisión de Cristian del 05/11: el alta es
/// un overlay sobre el mapa principal), así que el seguimiento de la ubicación (#670) sigue con
/// ellas encima.
abstract final class RutasCapaDelMapa {
  static const alta = 'mapa/alta_ubicacion';
  static const modificar = 'mapa/modificar_ubicacion';

  static const todas = {alta, modificar};
}

/// Sabe qué pantallas hay apiladas en el navegador de la app, para decidir si el seguimiento de la
/// ubicación sigue (#670, decisión del 05/11 sobre la revisión de QA): si arriba de la pestaña Mapa
/// hay otra pantalla que no es una capa del mapa (la ficha de una persona, el detalle de una agenda,
/// la cobranza…), el stream del GPS se apaga —batería— y vuelve al cerrarla, en el mismo modo.
///
/// Solo cuenta las pantallas enteras ([PageRoute]); los diálogos y las hojas de abajo son parte de
/// la pantalla que los abre. Se enchufa en `navigatorObservers` de la app.
final class PantallasSobreElMapa extends NavigatorObserver {
  final _pila = <Route<dynamic>>[];

  /// Cambia cada vez que se apila o se desapila una pantalla entera.
  final cambios = ValueNotifier<int>(0);

  /// ¿Hay, encima de [ruta], alguna pantalla que no sea una capa del mapa?
  bool hayPantallaAjenaSobre(Route<dynamic>? ruta) {
    final posicion = ruta == null ? -1 : _pila.indexOf(ruta);
    if (posicion < 0) return false;
    return _pila.skip(posicion + 1).any((r) => !RutasCapaDelMapa.todas.contains(r.settings.name));
  }

  void _avisar() => cambios.value++;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute<dynamic>) return;
    _pila.add(route);
    _avisar();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pila.remove(route)) _avisar();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pila.remove(route)) _avisar();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final posicion = oldRoute == null ? -1 : _pila.indexOf(oldRoute);
    if (posicion >= 0) _pila.removeAt(posicion);
    if (newRoute is PageRoute<dynamic>) {
      _pila.insert(posicion >= 0 ? posicion : _pila.length, newRoute);
    }
    if (posicion >= 0 || newRoute is PageRoute<dynamic>) _avisar();
  }
}

/// El observador de la app: [ColportoresApp] lo mete en `navigatorObservers` y la pestaña Mapa lo lee.
final pantallasSobreElMapaProvider = Provider<PantallasSobreElMapa>((ref) {
  final observador = PantallasSobreElMapa();
  ref.onDispose(observador.cambios.dispose);
  return observador;
});
