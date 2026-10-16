import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../domain/services/fuente_mapa.dart';
import '../../domain/value_objects/camara_mapa.dart';
import '../../domain/value_objects/coordenadas.dart';

/// Colores del mapa que no salen del tema: los del canvas de Claude Design (los mismos del estilo
/// de backend, `tiles/paleta.json`) y los de los puntos.
abstract final class ColoresMapa {
  /// La tierra del estilo: el fondo liso cuando no hay tiles y mientras cargan.
  static const fondo = Color(0xFFF6F5F0);
  static const puntoGps = Color(0xFF2F6FD1);
  static const bordeContexto = Color(0xFF6B7688);
  static const bordeCandidata = Color(0xFF4A5A72);
  static const tinta = Color(0xFF2A3A52);

  /// El círculo de un grupo de ubicaciones (vista 06): el azul casi negro del canvas.
  static const tintaOscura = Color(0xFF0E1A2B);

  /// El aro exterior del marcador seleccionado (vista 06).
  static const aroSeleccion = Color(0xFF002856);
}

/// Cómo se dibuja un [PuntoMapa].
enum EstiloPunto {
  /// Una ubicación que ya existe, sin estado de visita: círculo blanco con borde gris.
  contexto,

  /// «Tu ubicación»: el punto azul del GPS.
  gps,

  /// La ubicación que se está dando de alta: círculo del color primario con borde blanco.
  nuevo,

  /// Una ubicación ya registrada que se compara con la nueva (A, B…): círculo blanco con borde
  /// oscuro y, si tiene, su [PuntoMapa.letra] adentro.
  candidata,

  /// Una ubicación a menos de 60 m del GPS (vista 06): el marcador crece y muestra su número de
  /// puerta ([PuntoMapa.etiqueta]). Nunca se agrupa: quien está al lado se ve uno por uno.
  cercano,

  /// La ubicación que el colportor tocó y cuya vista previa está abierta (vista 06): el marcador
  /// con un aro doble, blanco y azul, por encima de los demás. Nunca se agrupa.
  seleccionado;

  /// Va en la fuente de puntos que no se agrupa: el punto del GPS, el de la ubicación nueva, el que
  /// se tocó y los que están al lado del GPS tienen que verse siempre tal cual, no absorbidos por el
  /// grupo de las ubicaciones que tienen cerca.
  bool get sinAgrupar => this != contexto && this != candidata;
}

/// Un marcador del mapa. Se dibuja como capa del estilo (no como widget): no hay un widget por
/// marcador, así que miles de puntos no cuestan un árbol de widgets.
final class PuntoMapa extends Equatable {
  const PuntoMapa({
    required this.id,
    required this.coordenadas,
    this.estilo = EstiloPunto.contexto,
    this.letra,
    this.etiqueta,
  });

  /// Identifica al punto cuando el colportor lo toca (`MapaBase.alTocarPunto`).
  final String id;
  final Coordenadas coordenadas;
  final EstiloPunto estilo;

  /// El texto de adentro del círculo, de [EstiloPunto.candidata]: «A», «B»…
  final String? letra;

  /// El texto de [EstiloPunto.cercano] y [EstiloPunto.seleccionado]: el número de puerta.
  final String? etiqueta;

  @override
  List<Object?> get props => [id, coordenadas, estilo, letra, etiqueta];
}

/// El radio de precisión del GPS: un círculo en metros alrededor de [centro].
final class CirculoPrecision extends Equatable {
  const CirculoPrecision({required this.centro, required this.radioMetros});

  final Coordenadas centro;
  final double radioMetros;

  @override
  List<Object?> get props => [centro, radioMetros];
}

/// El área de «cerca tuyo» (vista 06): un círculo punteado de [radioMetros] alrededor de [centro].
final class CirculoCercania extends Equatable {
  const CirculoCercania({required this.centro, required this.radioMetros});

  final Coordenadas centro;
  final double radioMetros;

  @override
  List<Object?> get props => [centro, radioMetros];
}

/// Qué gestos del colportor mueven el mapa. Rotar e inclinar no existen: el norte siempre arriba.
final class InteraccionMapa extends Equatable {
  const InteraccionMapa({this.desplazar = true, this.zoom = true});

  /// El mapa es una imagen: no responde a ningún gesto, ni siquiera deja de pasarle los toques al
  /// scroll de la pantalla donde esté.
  static const ninguna = InteraccionMapa(desplazar: false, zoom: false);

  final bool desplazar;
  final bool zoom;

  bool get hay => desplazar || zoom;

  @override
  List<Object?> get props => [desplazar, zoom];
}

/// Todo lo que le hace falta a la vista nativa para dibujar `MapaBase` (lo arma `MapaBase`).
final class ConfigVistaMapa extends Equatable {
  const ConfigVistaMapa({
    required this.fuente,
    required this.camaraInicial,
    required this.zoomMinimo,
    required this.zoomMaximo,
    required this.interaccion,
    required this.dobleToqueZoom,
    required this.fondo,
    required this.colorNuevo,
    required this.puntos,
    required this.agruparPuntos,
    required this.precision,
    required this.cercania,
    required this.puntosTocables,
  });

  final FuenteMapa fuente;
  final CamaraMapa camaraInicial;
  final double zoomMinimo;
  final double zoomMaximo;
  final InteraccionMapa interaccion;

  /// Un doble toque acerca el mapa sobre el punto tocado.
  final bool dobleToqueZoom;
  final Color fondo;

  /// El color de [EstiloPunto.nuevo] (el primario del tema).
  final Color colorNuevo;
  final List<PuntoMapa> puntos;

  /// Los puntos cercanos se juntan en un círculo con su cantidad.
  final bool agruparPuntos;
  final CirculoPrecision? precision;

  /// El círculo punteado de «cerca tuyo»; `null` si no se dibuja.
  final CirculoCercania? cercania;

  /// Quien usa el mapa quiere saber qué punto se tocó.
  final bool puntosTocables;

  @override
  List<Object?> get props => [
    fuente,
    camaraInicial,
    zoomMinimo,
    zoomMaximo,
    interaccion,
    dobleToqueZoom,
    fondo,
    colorNuevo,
    puntos,
    agruparPuntos,
    precision,
    cercania,
    puntosTocables,
  ];
}

/// Lo que `MapaBase` le puede pedir a la vista nativa.
abstract interface class PuertoVistaMapa {
  /// Deja la cámara en [camara] sin animación.
  Future<void> moverCamara(CamaraMapa camara);
}

/// Lo que la vista nativa le avisa a `MapaBase`.
abstract interface class EventosVistaMapa {
  /// La vista existe y se le puede hablar por [puerto].
  void listo(PuertoVistaMapa puerto);

  /// La cámara cambió (por un gesto, o porque `MapaBase` la movió).
  void camaraMovida(CamaraMapa camara);

  /// La cámara dejó de moverse.
  void camaraQuieta(CamaraMapa camara);

  /// Se tocó el mapa (no un punto) en [coordenadas].
  void toque(Coordenadas coordenadas);

  /// Se tocó el punto [id].
  void toquePunto(String id);

  /// El colportor mantuvo el dedo apoyado en [coordenadas], donde no hay ningún punto ni grupo.
  void toqueLargo(Coordenadas coordenadas);
}

/// Construye la vista nativa de [config]. Es lo único de `MapaBase` que no se puede probar en un
/// test de widgets (la vista nativa no se dibuja): el test la reemplaza por una falsa.
typedef ConstructorVistaMapa =
    Widget Function(BuildContext context, ConfigVistaMapa config, EventosVistaMapa eventos);

/// Lo que `MapaBase` le da a quien lo usa para mover la cámara.
abstract interface class ControladorMapaBase {
  /// La última cámara conocida (la inicial, mientras la vista no avisó otra).
  CamaraMapa get camara;

  /// Mueve la cámara sin animación. No cuenta como un gesto del colportor: no se avisa por
  /// `alMoverCamara`.
  Future<void> moverCamara(CamaraMapa camara);
}
