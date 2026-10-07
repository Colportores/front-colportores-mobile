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

  MapaUbicacionesState copyWith({
    ListaUbicaciones? lista,
    bool? fallaLectura,
    EstadoGpsLista? gps,
    LecturaGps? lectura,
    MotivoSinGps? motivoSinGps,
    bool borrarMotivo = false,
    String? seleccionadaId,
    bool borrarSeleccion = false,
  }) => MapaUbicacionesState(
    lista: lista ?? this.lista,
    fallaLectura: fallaLectura ?? this.fallaLectura,
    gps: gps ?? this.gps,
    lectura: lectura ?? this.lectura,
    motivoSinGps: borrarMotivo ? null : (motivoSinGps ?? this.motivoSinGps),
    seleccionadaId: borrarSeleccion ? null : (seleccionadaId ?? this.seleccionadaId),
  );

  @override
  List<Object?> get props => [lista, fallaLectura, gps, lectura, motivoSinGps, seleccionadaId];
}
