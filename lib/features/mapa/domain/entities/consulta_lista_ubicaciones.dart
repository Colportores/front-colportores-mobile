import 'package:equatable/equatable.dart';

import '../value_objects/coordenadas.dart';
import 'estado_casa.dart';
import 'ubicacion.dart';

/// Orden de la lista de ubicaciones (HU-UBI-002).
enum OrdenListaUbicaciones {
  /// `updated_at DESC`: la que se tocó último, primero. Es el orden por defecto de la HU.
  recientes,

  /// Distancia ascendente desde la posición del GPS. Sin posición se cae a [recientes].
  cercania,
}

/// Qué lista de ubicaciones quiere ver el colportor (HU-UBI-002).
///
/// Todos los filtros son opcionales y **se combinan con Y**: una ubicación tiene que cumplirlos
/// todos. Dentro de un filtro de varios valores (tipo, estado) alcanza con uno: «Casa» y
/// «Negocio» muestran las dos. El filtro por estado (`house_status`) filtra por el
/// `UbicacionConResumen.estado` que trae el repositorio: una ubicación de estado desconocido
/// (`null`) no cumple ningún estado pedido.
final class ConsultaListaUbicaciones extends Equatable {
  const ConsultaListaUbicaciones({
    required this.colportorId,
    this.tipos = const {},
    this.estados = const {},
    this.ciudadId,
    this.incluirBajas = false,
    this.busqueda,
    this.orden = OrdenListaUbicaciones.recientes,
    this.posicion,
    this.radioMaxMetros,
    this.limite = tamanoPagina,
  });

  /// Ubicaciones por página (Supuesto S14: lazy loading de 50 en 50).
  static const tamanoPagina = 50;

  /// Dueño de las ubicaciones (`created_by`): la lista es "las que registré".
  final String colportorId;

  /// Vacío = todos los tipos.
  final Set<TipoUbicacion> tipos;

  /// Vacío = todos los estados (también las de estado desconocido).
  final Set<EstadoCasa> estados;

  final String? ciudadId;

  /// Toggle "Mostrar bajas": suma las `deleted_at != NULL`, que vuelven marcadas como baja.
  final bool incluirBajas;

  /// Texto libre sobre calle + número (solo local). Vacío o en blanco = sin búsqueda.
  final String? busqueda;

  final OrdenListaUbicaciones orden;

  /// Posición actual del GPS, si hay. Habilita el orden por cercanía, la distancia de cada ítem
  /// y el filtro por proximidad. Una posición en (0, 0) o fuera de rango se trata como "sin GPS".
  final Coordenadas? posicion;

  /// Filtro de proximidad: solo las que están a esta distancia o menos de [posicion]. Sin
  /// posición se ignora. La HU no fija el radio: lo elige la vista (decisión pendiente).
  final double? radioMaxMetros;

  /// Cuántos ítems como máximo. La vista pide más (`limite + tamanoPagina`) al llegar al final.
  final int limite;

  /// [posicion] si sirve para calcular distancias; `null` si no hay GPS o la lectura es inválida.
  Coordenadas? get posicionValida {
    final p = posicion;
    if (p == null || p.sonCero || !p.estanEnRango) return null;
    return p;
  }

  @override
  List<Object?> get props => [
    colportorId,
    tipos,
    estados,
    ciudadId,
    incluirBajas,
    busqueda,
    orden,
    posicion,
    radioMaxMetros,
    limite,
  ];
}
