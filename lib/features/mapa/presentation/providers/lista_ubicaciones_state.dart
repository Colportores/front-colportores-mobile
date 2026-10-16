import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/consulta_lista_ubicaciones.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';

/// Las distancias que ofrece el filtro «Proximidad» (vista 05: «100 m, 300 m y 1 km»).
enum ProximidadLista {
  cualquiera(null),
  cien(100),
  trescientos(300),
  unKilometro(1000);

  const ProximidadLista(this.metros);

  /// El radio en metros; `null` = sin filtro.
  final double? metros;
}

/// Qué ve la lista de ubicaciones: todos los filtros, el orden, la búsqueda y cuánto se cargó
/// (HU-UBI-002).
final class FiltrosLista extends Equatable {
  const FiltrosLista({
    this.tipos = const {},
    this.estados = const {},
    this.ciudadId,
    this.incluirBajas = false,
    this.proximidad = ProximidadLista.cualquiera,
    this.orden = OrdenListaUbicaciones.recientes,
    this.busqueda = '',
    this.limite = ConsultaListaUbicaciones.tamanoPagina,
  });

  final Set<TipoUbicacion> tipos;
  final Set<EstadoCasa> estados;
  final String? ciudadId;
  final bool incluirBajas;
  final ProximidadLista proximidad;
  final OrdenListaUbicaciones orden;
  final String busqueda;
  final int limite;

  /// El número del botón «Filtros»: uno por cada chip (tipo, estado, ciudad, proximidad y bajas).
  /// El orden y la búsqueda no cuentan: no son un filtro de la hoja.
  int get cantidadActivos =>
      tipos.length +
      estados.length +
      (ciudadId != null ? 1 : 0) +
      (proximidad != ProximidadLista.cualquiera ? 1 : 0) +
      (incluirBajas ? 1 : 0);

  /// Hay algún filtro de la hoja puesto.
  bool get hayFiltros => cantidadActivos > 0;

  /// Hay algo que limpiar: un filtro o una búsqueda.
  bool get hayFiltrosOBusqueda => hayFiltros || busqueda.trim().isNotEmpty;

  /// El pedido al caso de uso. [limite] se pisa para contar sin traer filas.
  ConsultaListaUbicaciones consulta({
    required String colportorId,
    Coordenadas? posicion,
    int? limite,
  }) => ConsultaListaUbicaciones(
    colportorId: colportorId,
    tipos: tipos,
    estados: estados,
    ciudadId: ciudadId,
    incluirBajas: incluirBajas,
    busqueda: busqueda,
    orden: orden,
    posicion: posicion,
    radioMaxMetros: proximidad.metros,
    limite: limite ?? this.limite,
  );

  /// Lo mismo, con otros valores. [ciudadId] `null` no cambia la ciudad: para quitarla, [sinCiudad].
  FiltrosLista copyWith({
    Set<TipoUbicacion>? tipos,
    Set<EstadoCasa>? estados,
    String? ciudadId,
    bool sinCiudad = false,
    bool? incluirBajas,
    ProximidadLista? proximidad,
    OrdenListaUbicaciones? orden,
    String? busqueda,
    int? limite,
  }) => FiltrosLista(
    tipos: tipos ?? this.tipos,
    estados: estados ?? this.estados,
    ciudadId: sinCiudad ? null : (ciudadId ?? this.ciudadId),
    incluirBajas: incluirBajas ?? this.incluirBajas,
    proximidad: proximidad ?? this.proximidad,
    orden: orden ?? this.orden,
    busqueda: busqueda ?? this.busqueda,
    limite: limite ?? this.limite,
  );

  /// Sin ningún filtro de la hoja; conserva la búsqueda y el orden.
  FiltrosLista sinFiltros() => FiltrosLista(orden: orden, busqueda: busqueda);

  @override
  List<Object?> get props => [
    tipos,
    estados,
    ciudadId,
    incluirBajas,
    proximidad,
    orden,
    busqueda,
    limite,
  ];
}

/// Qué pasa con el GPS de la lista (el «◎ GPS ±8 m» de arriba y los controles que lo necesitan).
enum EstadoGpsLista {
  /// Todavía no se pidió: la pestaña no se abrió.
  sinPedir,

  /// Esperando la primera lectura.
  buscando,

  /// Hay una lectura utilizable ([ListaUbicacionesState.lectura]).
  conLectura,

  /// Permiso denegado, ubicación apagada o sin señal ([ListaUbicacionesState.motivoSinGps]).
  sinGps,
}

/// Todo lo que muestra la lista de ubicaciones (vista 05).
final class ListaUbicacionesState extends Equatable {
  const ListaUbicacionesState({
    this.filtros = const FiltrosLista(),
    this.lista,
    this.fallaLectura = false,
    this.gps = EstadoGpsLista.sinPedir,
    this.lectura,
    this.motivoSinGps,
  });

  final FiltrosLista filtros;

  /// La última lista que emitió la base; `null` hasta la primera emisión. Al cambiar un filtro se
  /// conserva la anterior hasta que llega la nueva, para que la pantalla no parpadee.
  final ListaUbicaciones? lista;

  /// La lectura de la base falló (se muestra el error con «Reintentar»).
  final bool fallaLectura;

  final EstadoGpsLista gps;
  final LecturaGps? lectura;
  final MotivoSinGps? motivoSinGps;

  /// La posición con la que se ordena y se mide, si hay.
  Coordenadas? get posicion => lectura?.coordenadas;

  /// Todavía no llegó la primera lista.
  bool get cargando => lista == null && !fallaLectura;

  ListaUbicacionesState copyWith({
    FiltrosLista? filtros,
    ListaUbicaciones? lista,
    bool? fallaLectura,
    EstadoGpsLista? gps,
    LecturaGps? lectura,
    bool borrarLectura = false,
    MotivoSinGps? motivoSinGps,
    bool borrarMotivo = false,
  }) => ListaUbicacionesState(
    filtros: filtros ?? this.filtros,
    lista: lista ?? this.lista,
    fallaLectura: fallaLectura ?? this.fallaLectura,
    gps: gps ?? this.gps,
    lectura: borrarLectura ? null : (lectura ?? this.lectura),
    motivoSinGps: borrarMotivo ? null : (motivoSinGps ?? this.motivoSinGps),
  );

  @override
  List<Object?> get props => [filtros, lista, fallaLectura, gps, lectura, motivoSinGps];
}
