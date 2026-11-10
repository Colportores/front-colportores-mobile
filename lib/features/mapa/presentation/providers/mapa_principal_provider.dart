import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../mapa_base/modelo_mapa_base.dart';

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

/// Se está sumando una casa con el pin (N·01 a N·03 de la 39, grupo 41A). [punto] es donde está el
/// pin; `null` mientras no se marcó (41A·02, sin GPS).
final class ColocandoPin extends ModoMapaPrincipal {
  const ColocandoPin({this.punto});

  final Coordenadas? punto;

  @override
  List<Object?> get props => [punto];
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

  @override
  ModoMapaPrincipal build() => const Explorando();

  /// El mapa principal está armado: desde ahora las capas mueven su cámara.
  void registrar(ControladorMapaBase controlador) => _controlador = controlador;

  /// El mapa principal se desarmó. Si en el medio se armó otro (al reconstruirse la pestaña), el
  /// controlador nuevo queda.
  void soltar(ControladorMapaBase controlador) {
    if (identical(_controlador, controlador)) _controlador = null;
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

  /// Pasa al modo [modo]. Cambiar de modo **no** mueve la cámara.
  void cambiarModo(ModoMapaPrincipal modo) => state = modo;

  /// Vuelve al mapa libre.
  void volverAExplorar() => state = const Explorando();
}

/// El modo del mapa principal y su cámara (#655). No se libera solo: lo usan la pestaña Mapa y las
/// hojas que van encima.
final mapaPrincipalProvider = NotifierProvider<MapaPrincipalNotifier, ModoMapaPrincipal>(
  MapaPrincipalNotifier.new,
);
