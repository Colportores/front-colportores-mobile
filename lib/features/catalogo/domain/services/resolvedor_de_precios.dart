import '../entities/catalogo_local.dart';
import '../entities/item_de_precio.dart';

/// La regla de precios de HU-CAT-006 (R-CT05 y R-CT06), sin pantalla y sin red.
///
/// El precio de un producto o de un combo en una ciudad es **el de la excepción de la ciudad si la
/// hay y vale hoy; si no, el precio general que vale hoy; sin ninguno de los dos no se ofrece**
/// (decisión de Cristian, 06/10, «Precio gral.», y 21/10, C9). Un combo es un solo ítem con su precio
/// y sus componentes (C10).
abstract final class ResolvedorDePrecios {
  /// Todo lo que la colportora puede cotizar en la ciudad de [catalogo] el día [dia] (`AAAA-MM-DD`,
  /// ver [diaDeMontevideo]): los combos de menos a más libros a elegir y después los productos por
  /// nombre. El material de trabajo no se vende, así que no está.
  static List<ItemDePrecio> resolver(CatalogoLocal catalogo, {required String dia}) {
    final porProducto = <String, PrecioDelCatalogo>{};
    final porCombo = <String, PrecioDelCatalogo>{};
    final generalesProducto = <String, PrecioDelCatalogo>{};
    final generalesCombo = <String, PrecioDelCatalogo>{};
    _mejores(catalogo.excepciones, dia, porProducto, porCombo);
    _mejores(catalogo.generales, dia, generalesProducto, generalesCombo);

    final productosPorId = {for (final p in catalogo.productos) p.id: p};

    final productos = <PrecioDeProducto>[];
    for (final p in catalogo.productos) {
      if (p.dadoDeBaja || !_seVende(p.tipo)) continue;
      final excepcion = porProducto[p.id];
      final precio = excepcion ?? generalesProducto[p.id];
      if (precio == null) continue;
      productos.add(
        PrecioDeProducto(
          id: p.id,
          nombre: p.nombre,
          centavos: precio.centavos,
          origen: excepcion != null ? OrigenDelPrecio.ciudad : OrigenDelPrecio.general,
          tipo: p.tipo,
          esBonificable: p.esBonificable,
          esMisionero: p.esMisionero,
          codigoEditor: _codigoONulo(p.codigoEditor),
        ),
      );
    }
    productos.sort((a, b) => _comparar(a.nombre, b.nombre, a.id, b.id));

    final combos = <PrecioDeCombo>[];
    for (final c in catalogo.combos) {
      if (c.dadoDeBaja) continue;
      final excepcion = porCombo[c.id];
      final precio = excepcion ?? generalesCombo[c.id];
      if (precio == null) continue;
      combos.add(
        PrecioDeCombo(
          id: c.id,
          nombre: c.nombre,
          centavos: precio.centavos,
          origen: excepcion != null ? OrigenDelPrecio.ciudad : OrigenDelPrecio.general,
          librosAElegir: c.librosAElegir,
          // Un componente cuyo producto todavía no llegó al teléfono no se puede nombrar: se omite
          // y el combo se ofrece igual (un combo no desaparece por una fila que falta).
          componentes: [
            for (final componente in c.componentes)
              if (productosPorId[componente.productoId] case final producto?)
                ComponenteDeCombo(nombre: producto.nombre, cantidad: componente.cantidad),
          ],
        ),
      );
    }
    combos.sort((a, b) {
      final porLibros = a.librosAElegir.compareTo(b.librosAElegir);
      return porLibros != 0 ? porLibros : _comparar(a.nombre, b.nombre, a.id, b.id);
    });

    return [...combos, ...productos];
  }

  /// Los ítems de la pestaña [categoria].
  static List<ItemDePrecio> deLaCategoria(List<ItemDePrecio> items, CategoriaDePrecios categoria) =>
      [
        for (final item in items)
          if (switch (item) {
            PrecioDeCombo() => categoria == CategoriaDePrecios.colecciones,
            final PrecioDeProducto producto => producto.categoria == categoria,
          })
            item,
      ];

  /// Los productos de [items] cuyo nombre o código contiene todas las palabras de [consulta], sin
  /// distinguir mayúsculas ni tildes. Una consulta vacía deja todos.
  static List<ItemDePrecio> buscar(List<ItemDePrecio> items, String consulta) {
    final palabras = normalizar(consulta).split(' ').where((p) => p.isNotEmpty).toList();
    if (palabras.isEmpty) return items;
    return [
      for (final item in items)
        if (item is PrecioDeProducto && _coincide(item, palabras)) item,
    ];
  }

  static bool _coincide(PrecioDeProducto producto, List<String> palabras) {
    final nombre = normalizar(producto.nombre);
    final codigo = normalizar(producto.codigoEditor ?? '');
    return palabras.every((p) => nombre.contains(p) || (codigo.isNotEmpty && codigo.contains(p)));
  }

  /// Minúsculas, sin tildes ni diéresis (la ñ cuenta como n) y con los espacios colapsados.
  static String normalizar(String texto) {
    final buffer = StringBuffer();
    for (final rune in texto.toLowerCase().runes) {
      buffer.write(_sinTilde[String.fromCharCode(rune)] ?? String.fromCharCode(rune));
    }
    return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static const _sinTilde = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
  };

  /// El día de Montevideo (`AAAA-MM-DD`) en el que cae [instante]: las vigencias de los precios las
  /// fija el servidor por ese día, no por el huso del teléfono. Uruguay es UTC−3 todo el año (sin
  /// horario de verano desde 2015).
  static String diaDeMontevideo(DateTime instante) {
    final d = instante.toUtc().subtract(const Duration(hours: 3));
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${dos(d.month)}-${dos(d.day)}';
  }

  static bool _seVende(TipoDeProducto tipo) =>
      tipo == TipoDeProducto.libro ||
      tipo == TipoDeProducto.revista ||
      tipo == TipoDeProducto.misionero;

  /// Un código en blanco es «sin código».
  static String? _codigoONulo(String? codigo) {
    final limpio = codigo?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  /// De cada producto y cada combo, el precio que vale [dia]. Si por un dato roto valen dos, gana el
  /// que empezó después (y, empatados, el de `id` mayor): siempre el mismo, nunca el azar.
  static void _mejores(
    List<PrecioDelCatalogo> precios,
    String dia,
    Map<String, PrecioDelCatalogo> deProductos,
    Map<String, PrecioDelCatalogo> deCombos,
  ) {
    for (final precio in precios) {
      if (!precio.valeEl(dia)) continue;
      final destino = precio.productoId != null ? deProductos : deCombos;
      final clave = (precio.productoId ?? precio.comboId)!;
      final actual = destino[clave];
      if (actual == null || _esMejor(precio, actual)) destino[clave] = precio;
    }
  }

  static bool _esMejor(PrecioDelCatalogo a, PrecioDelCatalogo b) {
    final porInicio = a.validoDesde.compareTo(b.validoDesde);
    return porInicio != 0 ? porInicio > 0 : a.id.compareTo(b.id) > 0;
  }

  static int _comparar(String a, String b, String idA, String idB) {
    final porNombre = normalizar(a).compareTo(normalizar(b));
    return porNombre != 0 ? porNombre : idA.compareTo(idB);
  }
}
