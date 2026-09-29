import 'package:equatable/equatable.dart';

import 'consulta_lista_ubicaciones.dart';
import 'ubicacion.dart';

/// Una fila de la lista de ubicaciones.
final class ItemListaUbicacion extends Equatable {
  const ItemListaUbicacion({required this.ubicacion, this.distanciaMetros});

  final Ubicacion ubicacion;

  /// Distancia en metros desde la posición del GPS; `null` si no había posición.
  final double? distanciaMetros;

  /// Está dada de baja (soft delete): la vista la etiqueta "Baja".
  bool get esBaja => ubicacion.estaBorrada;

  /// Una baja no permite visitas ni ventas (HU-UBI-002, escenario "incluir bajas").
  bool get esInteractiva => !esBaja;

  @override
  List<Object?> get props => [ubicacion, distanciaMetros];
}

/// Resultado de [ConsultaListaUbicaciones]: la página pedida y los contadores.
final class ListaUbicaciones extends Equatable {
  const ListaUbicaciones({
    required this.items,
    required this.total,
    required this.porTipo,
    required this.hayMas,
    required this.ordenAplicado,
    required this.sinUbicaciones,
  });

  /// Como mucho `consulta.limite` ítems, ya ordenados.
  final List<ItemListaUbicacion> items;

  /// Cuántas ubicaciones cumplen **todos** los filtros, contando las que no entraron en la
  /// página ("los contadores indican el total").
  final int total;

  /// Cuántas habría por tipo si no se filtrara por tipo pero sí por todo lo demás: sirve para el
  /// número al lado de cada chip de tipo. Están los tres tipos, aunque sea con 0.
  final Map<TipoUbicacion, int> porTipo;

  /// Hay más ubicaciones que las devueltas: la vista puede pedir la página siguiente.
  final bool hayMas;

  /// El orden que se usó: es [OrdenListaUbicaciones.recientes] aunque se haya pedido cercanía si
  /// no había posición del GPS (la vista lo avisa).
  final OrdenListaUbicaciones ordenAplicado;

  /// El colportor no tiene **ninguna** ubicación que mostrar, antes de aplicar la búsqueda, la
  /// ciudad, el radio y el tipo. Solo esto justifica el empty state de la HU con "Registrar tu
  /// primera ubicación". Sí respeta el toggle de bajas: si todas sus ubicaciones están dadas de
  /// baja y "Mostrar bajas" está apagado, es `true` (no hay nada que listar) y la vista puede
  /// ofrecer activar el toggle en vez de, o además de, el CTA de alta.
  final bool sinUbicaciones;

  /// No hay filas que mostrar (`total == 0`), sea por [sinUbicaciones] o por los filtros.
  bool get estaVacia => total == 0;

  /// Hay ubicaciones, pero ninguna cumple los filtros: la vista muestra "sin resultados" (con
  /// limpiar filtros), **no** el empty state de alta.
  bool get sinResultados => total == 0 && !sinUbicaciones;

  @override
  List<Object?> get props => [items, total, porTipo, hayMas, ordenAplicado, sinUbicaciones];
}
