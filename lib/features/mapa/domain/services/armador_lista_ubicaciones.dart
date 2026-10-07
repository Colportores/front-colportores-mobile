import '../entities/consulta_lista_ubicaciones.dart';
import '../entities/estado_casa.dart';
import '../entities/lista_ubicaciones.dart';
import '../entities/ubicacion.dart';
import '../entities/ubicacion_con_resumen.dart';
import 'criterio_duplicado_ubicacion.dart';

/// HU-UBI-002 — arma la lista a partir de las ubicaciones del colportor: filtra, busca, ordena,
/// cuenta y corta la página. Función pura: el repositorio ya trajo lo del colportor y la ciudad
/// (lo que se puede resolver en SQL), con las bajas aunque no se pidan: acá se esconden si «Mostrar
/// bajas» está apagado, pero se cuentan ([ListaUbicaciones.bajasOcultas]) para que el vacío sepa si
/// el colportor solo tiene bajas. Queda lo que necesita Dart (distancias, búsqueda sin acentos).
/// Vuelve a aplicar esos filtros, así que es correcta sola.
abstract final class ArmadorListaUbicaciones {
  static final _espacios = RegExp(r'\s+');

  static ListaUbicaciones armar(
    Iterable<UbicacionConResumen> ubicaciones,
    ConsultaListaUbicaciones c,
  ) {
    final posicion = c.posicionValida;
    final terminos = _terminos(c.busqueda);
    // Un radio no positivo o no finito (NaN, infinito) no es un filtro: se ignora.
    final r = c.radioMaxMetros;
    final radio = posicion == null || r == null || !r.isFinite || r <= 0 ? null : r;

    // Todos los filtros menos los de tipo y estado: con esto se cuentan los dos.
    final candidatas = <ItemListaUbicacion>[];
    var propias = 0;
    var bajas = 0;
    var bajasOcultas = 0;
    var estadosConocidos = false;
    for (final fila in ubicaciones) {
      final u = fila.ubicacion;
      if (u.auditoria.createdBy != c.colportorId) continue;
      if (u.estaBorrada && !c.incluirBajas) {
        bajasOcultas++;
        continue;
      }
      propias++;
      if (u.estaBorrada) bajas++;
      if (fila.estado != null) estadosConocidos = true;
      if (c.ciudadId != null && u.ciudadId != c.ciudadId) continue;
      if (!_coincide(u, terminos)) continue;
      final distancia = posicion?.distanciaMetrosA(u.coordenadas);
      if (radio != null && distancia! > radio) continue;
      candidatas.add(
        ItemListaUbicacion(
          ubicacion: u,
          distanciaMetros: distancia,
          cantidadEspacios: fila.cantidadEspacios,
          estado: fila.estado,
          proximaEntrevista: fila.proximaEntrevista,
        ),
      );
    }

    bool cumpleTipo(ItemListaUbicacion i) => c.tipos.isEmpty || c.tipos.contains(i.ubicacion.tipo);
    // Una ubicación de estado desconocido no cumple ningún estado pedido.
    bool cumpleEstado(ItemListaUbicacion i) =>
        c.estados.isEmpty || (i.estado != null && c.estados.contains(i.estado));

    // Cada contador cuenta con los demás filtros aplicados.
    final porTipo = {for (final t in TipoUbicacion.values) t: 0};
    final porEstado = {for (final e in EstadoCasa.values) e: 0};
    final filtradas = <ItemListaUbicacion>[];
    for (final i in candidatas) {
      final tipoOk = cumpleTipo(i);
      final estadoOk = cumpleEstado(i);
      if (estadoOk) porTipo[i.ubicacion.tipo] = porTipo[i.ubicacion.tipo]! + 1;
      final estado = i.estado;
      if (tipoOk && estado != null) porEstado[estado] = porEstado[estado]! + 1;
      if (tipoOk && estadoOk) filtradas.add(i);
    }

    final porCercania = c.orden == OrdenListaUbicaciones.cercania && posicion != null;
    filtradas.sort(porCercania ? _porCercania : _porRecientes);

    final limite = c.limite < 0 ? 0 : c.limite;
    return ListaUbicaciones(
      items: filtradas.take(limite).toList(growable: false),
      total: filtradas.length,
      porTipo: porTipo,
      porEstado: porEstado,
      totalGeneral: propias,
      totalBajas: bajas,
      estadosConocidos: estadosConocidos,
      hayMas: filtradas.length > limite,
      ordenAplicado: porCercania ? OrdenListaUbicaciones.cercania : OrdenListaUbicaciones.recientes,
      sinUbicaciones: propias == 0,
      bajasOcultas: bajasOcultas,
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
