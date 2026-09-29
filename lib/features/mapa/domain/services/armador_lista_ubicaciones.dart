import '../entities/consulta_lista_ubicaciones.dart';
import '../entities/lista_ubicaciones.dart';
import '../entities/ubicacion.dart';
import 'criterio_duplicado_ubicacion.dart';

/// HU-UBI-002 — arma la lista a partir de las ubicaciones del colportor: filtra, busca, ordena,
/// cuenta y corta la página. Función pura: el repositorio ya trajo lo del colportor, la ciudad y
/// las bajas (lo que se puede resolver en SQL); acá queda lo que necesita Dart (distancias,
/// búsqueda sin acentos). Vuelve a aplicar esos tres filtros, así que es correcta sola.
abstract final class ArmadorListaUbicaciones {
  static final _espacios = RegExp(r'\s+');

  static ListaUbicaciones armar(Iterable<Ubicacion> ubicaciones, ConsultaListaUbicaciones c) {
    final posicion = c.posicionValida;
    final terminos = _terminos(c.busqueda);
    final radio = posicion == null ? null : c.radioMaxMetros;

    // Todos los filtros menos el de tipo: con esto se cuentan los tipos.
    final candidatas = <ItemListaUbicacion>[];
    for (final u in ubicaciones) {
      if (u.auditoria.createdBy != c.colportorId) continue;
      if (c.ciudadId != null && u.ciudadId != c.ciudadId) continue;
      if (u.estaBorrada && !c.incluirBajas) continue;
      if (!_coincide(u, terminos)) continue;
      final distancia = posicion?.distanciaMetrosA(u.coordenadas);
      if (radio != null && distancia! > radio) continue;
      candidatas.add(ItemListaUbicacion(ubicacion: u, distanciaMetros: distancia));
    }

    final porTipo = {for (final t in TipoUbicacion.values) t: 0};
    for (final i in candidatas) {
      porTipo[i.ubicacion.tipo] = porTipo[i.ubicacion.tipo]! + 1;
    }

    final filtradas = c.tipos.isEmpty
        ? candidatas
        : [
            for (final i in candidatas)
              if (c.tipos.contains(i.ubicacion.tipo)) i,
          ];

    final porCercania = c.orden == OrdenListaUbicaciones.cercania && posicion != null;
    filtradas.sort(porCercania ? _porCercania : _porRecientes);

    final limite = c.limite < 0 ? 0 : c.limite;
    return ListaUbicaciones(
      items: filtradas.take(limite).toList(growable: false),
      total: filtradas.length,
      porTipo: porTipo,
      hayMas: filtradas.length > limite,
      ordenAplicado: porCercania ? OrdenListaUbicaciones.cercania : OrdenListaUbicaciones.recientes,
    );
  }

  static int _porRecientes(ItemListaUbicacion a, ItemListaUbicacion b) {
    final porFecha = b.ubicacion.auditoria.updatedAt.compareTo(a.ubicacion.auditoria.updatedAt);
    return porFecha != 0 ? porFecha : a.ubicacion.id.compareTo(b.ubicacion.id);
  }

  static int _porCercania(ItemListaUbicacion a, ItemListaUbicacion b) {
    final porDistancia = a.distanciaMetros!.compareTo(b.distanciaMetros!);
    return porDistancia != 0 ? porDistancia : _porRecientes(a, b);
  }

  /// Cada palabra de la búsqueda tiene que aparecer (como substring) en "calle número": así
  /// "rivadavia 12" encuentra Rivadavia 1234 y "1234" encuentra por número. Sin acentos ni
  /// mayúsculas, como el criterio de duplicados.
  static List<String> _terminos(String? busqueda) {
    if (busqueda == null) return const [];
    final normal = CriterioDuplicadoUbicacion.normalizar(busqueda);
    return normal.isEmpty ? const [] : normal.split(_espacios);
  }

  static bool _coincide(Ubicacion u, List<String> terminos) {
    if (terminos.isEmpty) return true;
    final direccion = CriterioDuplicadoUbicacion.normalizar('${u.calle ?? ''} ${u.numero ?? ''}');
    return terminos.every(direccion.contains);
  }
}
