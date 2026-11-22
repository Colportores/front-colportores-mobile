import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';
import 'lista_ubicaciones_state.dart' show EstadoGpsLista;

export 'lista_ubicaciones_state.dart' show EstadoGpsLista;

/// Todo lo que muestra el mapa de ubicaciones (vista 06, HU-UBI-003): las ubicaciones del colportor
/// por cercanía, su GPS y cuál tocó.
final class MapaUbicacionesState extends Equatable {
  const MapaUbicacionesState({
    this.lista,
    this.fallaLectura = false,
    this.gps = EstadoGpsLista.sinPedir,
    this.lectura,
    this.motivoSinGps,
    this.seleccionadaId,
    this.candidatasIds = const [],
  });

  /// «Cerca tuyo» (canvas, 06C·01): a menos de esta distancia del GPS el marcador crece y muestra
  /// el número de puerta, y alrededor se dibuja el círculo punteado.
  static const radioCercaMetros = 60.0;

  /// La última lista que emitió la base (todas las ubicaciones activas, de la más cercana a la más
  /// lejana); `null` hasta la primera emisión.
  final ListaUbicaciones? lista;

  /// La lectura de la base falló (se muestra el error con «Reintentar»).
  final bool fallaLectura;

  final EstadoGpsLista gps;
  final LecturaGps? lectura;
  final MotivoSinGps? motivoSinGps;

  /// La ubicación cuya vista previa pidió el colportor (un toque en un marcador, o el alta que
  /// acaba de registrar). Solo cuenta si está en [lista]: si deja de estar (una baja, otra sesión),
  /// no hay vista previa.
  final String? seleccionadaId;

  /// Las ubicaciones entre las que hay que elegir (vista 39, E·06 «3 ubicaciones acá»): los `id`, de
  /// la más cercana al toque a la más lejana. Vacía si no hay nada que elegir. Nunca hay a la vez una
  /// [seleccionadaId] y candidatas: o se eligió una, o se está eligiendo.
  final List<String> candidatasIds;

  /// La posición con la que se ordena y se mide, si hay.
  Coordenadas? get posicion => lectura?.coordenadas;

  /// Todavía no llegó la primera lista.
  bool get cargando => lista == null && !fallaLectura;

  /// La fila de la ubicación seleccionada, o `null` si no hay selección o ya no está en la lista.
  ItemListaUbicacion? get seleccionada {
    final id = seleccionadaId;
    final items = lista?.items;
    if (id == null || items == null) return null;
    for (final item in items) {
      if (item.ubicacion.id == id) return item;
    }
    return null;
  }

  /// Las filas de las candidatas que siguen en [lista], en el orden de [candidatasIds]. Una que ya no
  /// está (una baja, otra sesión) sale de la elección.
  List<ItemListaUbicacion> get candidatas {
    final items = lista?.items;
    if (candidatasIds.isEmpty || items == null) return const [];
    return [
      for (final id in candidatasIds)
        for (final item in items)
          if (item.ubicacion.id == id) item,
    ];
  }

  /// Hay una hoja de la casa que mostrar: la de la seleccionada o la elección entre candidatas.
  bool get hayVistaPrevia => seleccionada != null || candidatas.isNotEmpty;

  MapaUbicacionesState copyWith({
    ListaUbicaciones? lista,
    bool? fallaLectura,
    EstadoGpsLista? gps,
    LecturaGps? lectura,
    MotivoSinGps? motivoSinGps,
    bool borrarMotivo = false,
    String? seleccionadaId,
    bool borrarSeleccion = false,
    List<String>? candidatasIds,
    bool borrarCandidatas = false,
  }) => MapaUbicacionesState(
    lista: lista ?? this.lista,
    fallaLectura: fallaLectura ?? this.fallaLectura,
    gps: gps ?? this.gps,
    lectura: lectura ?? this.lectura,
    motivoSinGps: borrarMotivo ? null : (motivoSinGps ?? this.motivoSinGps),
    seleccionadaId: borrarSeleccion ? null : (seleccionadaId ?? this.seleccionadaId),
    candidatasIds: borrarCandidatas ? const [] : (candidatasIds ?? this.candidatasIds),
  );

  @override
  List<Object?> get props => [
    lista,
    fallaLectura,
    gps,
    lectura,
    motivoSinGps,
    seleccionadaId,
    candidatasIds,
  ];
}
