import 'dart:ui' show Rect;

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/proyeccion_mercator.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../mapa_base/modelo_mapa_base.dart';
import 'alta_ubicacion_notifier.dart' show ParametrosAlta;

/// Lo que está haciendo el mapa principal, el de la pestaña Mapa (vista 41, #655): hay **un solo
/// mapa** y el alta, el aviso de duplicado, la edición, «Mover el punto» y comparar un par son modos
/// y hojas encima de él, con la misma cámara y el mismo GPS (decisión de Cristian del 04/11).
sealed class ModoMapaPrincipal extends Equatable {
  const ModoMapaPrincipal();

  @override
  List<Object?> get props => const [];
}

/// El mapa libre: se mira, se elige una casa o se suelta el pin.
final class Explorando extends ModoMapaPrincipal {
  const Explorando();
}

/// Hay una casa elegida y su hoja está abierta (C·01 de la 39, 41C·01).
final class CasaElegida extends ModoMapaPrincipal {
  const CasaElegida(this.ubicacionId);

  final String ubicacionId;

  @override
  List<Object?> get props => [ubicacionId];
}

/// Se está sumando una casa con el pin (N·01 y N·02 de la 39, grupos 41A y 41B). [alta] identifica
/// el alta en curso: el pin, la dirección, la ciudad y las candidatas a duplicado viven en su estado
/// (`altaUbicacionProvider(alta)`), que leen a la vez el mapa (para dibujar el pin y las candidatas)
/// y la hoja de encima.
final class ColocandoPin extends ModoMapaPrincipal {
  const ColocandoPin(this.alta);

  final ParametrosAlta alta;

  @override
  List<Object?> get props => [alta];
}

/// «Mover el punto» de una ubicación (41C·03): [antes] es la posición guardada, que el mapa deja
/// marcada con un recuadro punteado, y [nueva] la que se eligió arrastrando o tocando el mapa
/// (`null` mientras no se movió).
final class MoviendoPunto extends ModoMapaPrincipal {
  const MoviendoPunto({required this.ubicacionId, required this.antes, this.nueva});

  final String ubicacionId;
  final Coordenadas antes;
  final Coordenadas? nueva;

  @override
  List<Object?> get props => [ubicacionId, antes, nueva];
}

/// Dos ubicaciones a la vista juntas, cada una con su letra: el aviso de duplicado al soltar el pin
/// (41B) o un posible duplicado que se revisa desde la Lista (41D). [a] se conserva y [b] es la otra.
final class ComparandoDuplicado extends ModoMapaPrincipal {
  const ComparandoDuplicado({required this.a, required this.b});

  final String a;
  final String b;

  @override
  List<Object?> get props => [a, b];
}

/// Por qué se mueve la cámara del mapa principal. **Regla de la cámara** (04/11 y 05/11, vista 41):
/// el mapa se mueve solo cuando la colportora lo pide; nunca por un cambio de datos, de ciudad, de
/// fuente o por el teclado. Por eso no hay forma de mover la cámara desde afuera sin decir cuál de
/// estos pedidos la mueve.
enum IntencionCamara {
  /// Eligió una casa (en el mapa, en la Lista, o el shell pidió «ir a la casa»).
  elegirCasa,

  /// Tocó «Mi ubicación».
  miUbicacion,

  /// Tocó «Confirmar posición» en el alta: el único momento en que la cámara acomoda el pin arriba
  /// de la hoja (41A).
  confirmarPosicion,

  /// Tocó «Revisar» en un posible duplicado: el mapa encuadra el par (41D·01).
  revisarPar,
}

/// El dueño del modo del mapa principal y de su cámara. Vive mientras vive la app (no se libera al
/// cambiar de pestaña ni al abrir una hoja): el modo y la cámara no se pierden por eso.
///
/// La pestaña Mapa le entrega su [ControladorMapaBase] al crearse el mapa ([registrar]) y lo suelta
/// al irse ([soltar]); las hojas que van encima piden mover la cámara con [llevarA], siempre con una
/// [IntencionCamara].
final class MapaPrincipalNotifier extends Notifier<ModoMapaPrincipal> {
  ControladorMapaBase? _controlador;
  Rect? Function()? _area;

  @override
  ModoMapaPrincipal build() => const Explorando();

  /// El mapa principal está armado: desde ahora las capas mueven su cámara. [area] dice dónde está el
  /// mapa en la pantalla (en coordenadas globales): con ella una hoja de encima sabe qué parte del mapa
  /// tapa ([acomodarArribaDe]).
  void registrar(ControladorMapaBase controlador, {Rect? Function()? area}) {
    _controlador = controlador;
    _area = area;
  }

  /// El mapa principal se desarmó. Si en el medio se armó otro (al reconstruirse la pestaña), el
  /// controlador nuevo queda.
  void soltar(ControladorMapaBase controlador) {
    if (!identical(_controlador, controlador)) return;
    _controlador = null;
    _area = null;
  }

  /// ¿Está armado el mapa principal?
  bool hayMapa() => _controlador != null;

  /// La cámara del mapa principal, o `null` si no está armado.
  CamaraMapa? camara() => _controlador?.camara;

  /// Lleva la cámara a [destino] porque la colportora lo pidió ([por]). Devuelve `false` si el mapa
  /// principal no está armado (no se mueve nada).
  Future<bool> llevarA(CamaraMapa destino, {required IntencionCamara por}) async {
    final controlador = _controlador;
    if (controlador == null) return false;
    await controlador.moverCamara(destino);
    return true;
  }

  /// Lleva [punto] al medio de la parte del mapa que queda libre arriba de una hoja cuyo borde de
  /// arriba está en [bordeDeLaHoja] (coordenada `y` global), sin cambiar el zoom ni el rumbo: es lo
  /// que hace «Confirmar posición» (41A), el único momento en que la cámara acomoda el pin arriba de
  /// la hoja. Con [zoomMinimo] además acerca hasta ese zoom si estaba más lejos. Devuelve `false` si
  /// el mapa principal no está armado o no se sabe dónde está.
  Future<bool> acomodarArribaDe(
    Coordenadas punto, {
    required double bordeDeLaHoja,
    required IntencionCamara por,
    double zoomMinimo = 0,
  }) async {
    final controlador = _controlador;
    final area = _area?.call();
    if (controlador == null || area == null || area.isEmpty) return false;
    final libreHasta = bordeDeLaHoja.clamp(area.top, area.bottom).toDouble();
    // Dónde tiene que caer el punto, medido desde el centro de la vista del mapa.
    final deseada = (area.top + libreHasta) / 2;
    final desplazamiento = deseada - area.center.dy;
    final camara = controlador.camara;
    final zoom = camara.zoom < zoomMinimo ? zoomMinimo : camara.zoom;
    final centro = ProyeccionMercator.centroQueDejaEn(
      punto,
      zoom: zoom,
      rumbo: camara.rumbo,
      desplazamientoY: desplazamiento,
    );
    await controlador.moverCamara(CamaraMapa(centro: centro, zoom: zoom, rumbo: camara.rumbo));
    return true;
  }

  /// ¿[punto] se ve en la parte del mapa que deja libre una hoja cuyo borde de arriba está en
  /// [bordeDeLaHoja] (coordenada `y` global)? Con [margen] dp: un punto pegado al borde no cuenta.
  /// `false` si el mapa principal no está armado o no se sabe dónde está.
  bool estaALaVista(Coordenadas punto, {required double bordeDeLaHoja, double margen = 40}) {
    final controlador = _controlador;
    final area = _area?.call();
    if (controlador == null || area == null || area.isEmpty) return false;
    final (:x, :y) = ProyeccionMercator.aPantalla(
      punto,
      controlador.camara,
      ancho: area.width,
      alto: area.height,
    );
    final abajo = bordeDeLaHoja.clamp(area.top, area.bottom).toDouble() - area.top;
    return x >= margen && x <= area.width - margen && y >= margen && y <= abajo - margen;
  }

  /// Pasa al modo [modo]. Cambiar de modo **no** mueve la cámara.
  void cambiarModo(ModoMapaPrincipal modo) => state = modo;

  /// Vuelve al mapa libre.
  void volverAExplorar() => state = const Explorando();

  /// Terminó el alta [alta]: si el mapa sigue colocando su pin, vuelve al mapa libre. Si ya está en
  /// otro modo (otra alta, una casa elegida) no lo toca. No necesita a la pestaña Mapa: se puede
  /// llamar aunque se haya desmontado mientras el alta estaba abierta.
  void terminarAlta(ParametrosAlta alta) {
    if (state == ColocandoPin(alta)) state = const Explorando();
  }
}

/// El modo del mapa principal y su cámara (#655). No se libera solo: lo usan la pestaña Mapa y las
/// hojas que van encima.
final mapaPrincipalProvider = NotifierProvider<MapaPrincipalNotifier, ModoMapaPrincipal>(
  MapaPrincipalNotifier.new,
);
