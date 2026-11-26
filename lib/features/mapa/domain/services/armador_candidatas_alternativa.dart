import 'package:equatable/equatable.dart';

import '../entities/ubicacion.dart';
import '../value_objects/coordenadas.dart';
import 'criterio_duplicado_ubicacion.dart';

/// Una ubicación entre las que se elige la alternativa de cobranza, con la distancia desde donde está
/// quien cobra (`null` sin GPS).
final class CandidataAlternativa extends Equatable {
  const CandidataAlternativa({required this.ubicacion, this.distanciaMetros});

  final Ubicacion ubicacion;
  final double? distanciaMetros;

  @override
  List<Object?> get props => [ubicacion, distanciaMetros];
}

/// Lo que muestra el selector de la ubicación alternativa (vista 22A·02, 22A·04 y 22A·05).
final class ListaCandidatasAlternativa extends Equatable {
  const ListaCandidatasAlternativa({
    required this.items,
    required this.hayCandidatas,
    required this.porCercania,
  });

  /// Las que coinciden con la búsqueda, en orden.
  final List<CandidataAlternativa> items;

  /// Hay al menos una ubicación para elegir, sin mirar la búsqueda: `false` es 22A·04 («No tenés otra
  /// ubicación para elegir»); `true` con [items] vacía es 22A·05 («Ninguna ubicación coincide»).
  final bool hayCandidatas;

  /// Van por cercanía (hay GPS): el rótulo de la lista lo dice y cada fila trae su distancia. Sin GPS
  /// van por dirección y el rótulo no promete una cercanía que no hay.
  final bool porCercania;

  @override
  List<Object?> get props => [items, hayCandidatas, porCercania];
}

/// HU-UBI-013 — busca y ordena las ubicaciones entre las que se elige la alternativa de cobranza.
/// Función pura: el repositorio ya trajo las que se pueden elegir (las activas que registró quien
/// cobra, sin la del propio espacio).
///
/// La búsqueda pide que cada palabra aparezca en «calle número tipo» (sin acentos ni mayúsculas): una
/// ubicación no tiene otro nombre que su dirección y su tipo («Casa», «Negocio», «Edificio»).
abstract final class ArmadorCandidatasAlternativa {
  static final _espacios = RegExp(r'\s+');

  static ListaCandidatasAlternativa armar(
    Iterable<Ubicacion> candidatas, {
    String busqueda = '',
    Coordenadas? posicion,
  }) {
    final todas = candidatas.toList(growable: false);
    final desde = posicion != null && !posicion.sonCero && posicion.estanEnRango ? posicion : null;
    final normal = CriterioDuplicadoUbicacion.normalizar(busqueda);
    final terminos = normal.isEmpty ? const <String>[] : normal.split(_espacios);

    final items = <CandidataAlternativa>[
      for (final u in todas)
        if (_coincide(u, terminos))
          CandidataAlternativa(
            ubicacion: u,
            distanciaMetros: desde?.distanciaMetrosA(u.coordenadas),
          ),
    ];
    if (desde != null) {
      items.sort((a, b) {
        final porDistancia = a.distanciaMetros!.compareTo(b.distanciaMetros!);
        return porDistancia != 0 ? porDistancia : _porDireccion(a.ubicacion, b.ubicacion);
      });
    } else {
      items.sort((a, b) => _porDireccion(a.ubicacion, b.ubicacion));
    }
    return ListaCandidatasAlternativa(
      items: List.unmodifiable(items),
      hayCandidatas: todas.isNotEmpty,
      porCercania: desde != null,
    );
  }

  static int _porDireccion(Ubicacion a, Ubicacion b) {
    final porCalle = CriterioDuplicadoUbicacion.normalizar(
      a.calle ?? '',
    ).compareTo(CriterioDuplicadoUbicacion.normalizar(b.calle ?? ''));
    if (porCalle != 0) return porCalle;
    final porNumero = CriterioDuplicadoUbicacion.normalizar(
      a.numero ?? '',
    ).compareTo(CriterioDuplicadoUbicacion.normalizar(b.numero ?? ''));
    return porNumero != 0 ? porNumero : a.id.compareTo(b.id);
  }

  static bool _coincide(Ubicacion u, List<String> terminos) {
    if (terminos.isEmpty) return true;
    final texto = CriterioDuplicadoUbicacion.normalizar(
      '${u.calle ?? ''} ${u.numero ?? ''} ${u.tipo.name}',
    );
    return terminos.every(texto.contains);
  }
}
