import '../../mapa/presentation/formato_baja.dart' show FormatoBaja;
import '../domain/entities/catalogo_local.dart' show TipoDeProducto;
import '../domain/entities/ciudad_consultable.dart';
import '../domain/entities/item_de_precio.dart';

/// Los textos de la consulta de precios (vista 26, HU-CAT-006). Los del canvas van letra por letra;
/// los que el canvas no dibuja están marcados «a confirmar» (mapa §2: texto) y se listan en el PR.
abstract final class TextosPrecios {
  // --- Del canvas (26·01 a 26·11) ---
  static const eyebrow = 'VENTAS';
  static const titulo = 'Precios';
  static const volver = 'Volver';

  static const ciudadSegunDondeEstas = 'SEGÚN DÓNDE ESTÁS';
  static const ciudadOtra = 'ESTÁS VIENDO OTRA CIUDAD';
  static const ciudadDeTuZonaSinGps = 'CIUDAD DE TU ZONA · SIN GPS';
  static const verOtra = 'Ver otra';

  static const buscar = 'Buscar por nombre o código';
  static const borrarBusqueda = 'Borrar la búsqueda';

  static const bonificable = '◆ Bonificable';
  static const misionero = '✦ Misionero';
  static const revista = 'Revista';

  static const volverADondeEstoy = 'Volver a donde estoy';
  static const sinResultadosSub = 'Si esperabas verlo, puede que no tenga precio en esta ciudad.';

  static const errorLectura = 'No pudimos leer los precios guardados en tu teléfono.';
  static const reintentar = 'Reintentar';
  static const cargando = 'Cargando los precios';

  static const sinPreciosVigentes = 'No tenés precios vigentes';

  static const hojaOtraCiudadTitulo = 'Ver precios de';
  static const hojaOtraCiudadNota =
      'Solo campañas en curso o por empezar: las terminadas no se muestran.';
  static const hojaOtraCiudadAccion = 'Ver precios';
  static const dondeEstas = 'Donde estás';

  static const cerrar = 'Cerrar';
  static const siempreVan = 'Siempre van';
  static const librosAElegir = 'Libros a elegir';

  // --- A confirmar (mapa §2: texto) ---
  /// La marca de la ciudad de su zona en «Ver precios de» (26·04 solo dibuja «Donde estás»).
  static const tuZona = 'Tu zona';

  /// El rótulo de la tarjeta cuando eligió una ciudad sin tener una de entrada (sin zona ni GPS).
  static const ciudadElegida = 'CIUDAD QUE ELEGISTE';

  /// La acción de 26·05 cuando la ciudad de entrada es la de su zona y no donde está.
  static const volverAMiZona = 'Volver a mi zona';

  /// Sin zona ni GPS la colportora elige la ciudad (decisión de Cristian, 23/10): el canvas no dibuja
  /// esa pantalla.
  static const elegiUnaCiudadTitulo = 'Elegí una ciudad';
  static const elegiUnaCiudadSub =
      'No sabemos dónde estás ni tenés una zona asignada. Elegí la ciudad de la que querés ver '
      'los precios.';
  static const elegiUnaCiudadAccion = 'Ver otra ciudad';

  /// Una pestaña sin ítems con precio en la ciudad (sin búsqueda): el canvas solo dibuja la búsqueda
  /// sin resultados (26·07).
  static const pestanaVaciaSub = 'Si esperabas verlos, puede que no tengan precio en esta ciudad.';

  /// 26·11 cuando ni siquiera hay una campaña terminada que nombrar.
  static const sinCampaniaSub = 'Cuando te inscriban en una campaña, vas a ver sus precios acá.';
}

/// Cómo se escriben los precios y las ciudades en la vista 26.
abstract final class FormatoPrecios {
  /// «$ 4.800», o «$ 1.450,50» si no son pesos justos.
  static String monto(int centavos) => FormatoBaja.monto(centavos).replaceFirst(r'$U', r'$');

  /// «22/10 a las 18:00», en hora local.
  static String fechaYHora(DateTime momento) {
    final m = momento.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(m.day)}/${dos(m.month)} a las ${dos(m.hour)}:${dos(m.minute)}';
  }

  /// «22/10».
  static String diaMes(DateTime momento) {
    final m = momento.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(m.day)}/${dos(m.month)}';
  }

  /// 26·09, «Sin conexión. Son los precios que recibiste el 22/10 a las 18:00.»
  static String sinConexion(DateTime? ultimaBajada) => ultimaBajada == null
      ? 'Sin conexión. Son los precios guardados en tu teléfono.'
      : 'Sin conexión. Son los precios que recibiste el ${fechaYHora(ultimaBajada)}.';

  /// 26·09 cuando pasaron los N días de la decisión «Precio viejo» (a confirmar, mapa §2: texto):
  /// pide conectarse y deja claro que la venta sigue.
  static String preciosViejos(DateTime ultimaBajada, int dias) =>
      'Sin conexión. Tus precios son del ${fechaYHora(ultimaBajada)} y tienen $dias '
      '${dias == 1 ? 'día' : 'días'}. Conectate para actualizarlos; mientras tanto podés '
      'seguir vendiendo.';

  /// 26·05.
  static String viendoOtraCiudad({required String viendo, required String enQueVende}) =>
      'Estos son los precios de $viendo. Si vendés en $enQueVende, se usan los de $enQueVende.';

  /// 26·06.
  static String sinUbicacion(String ciudad) =>
      'No sabemos dónde estás. Te mostramos $ciudad, la ciudad de tu zona.';

  /// 26·07 y la pestaña vacía.
  static String sinResultados(CategoriaDePrecios categoria, String ciudad) =>
      '${switch (categoria) {
        CategoriaDePrecios.colecciones => 'Ninguna colección',
        CategoriaDePrecios.libros => 'Ningún libro',
        CategoriaDePrecios.misioneros => 'Ningún misionero',
        CategoriaDePrecios.revistas => 'Ninguna revista',
      }} con precio en $ciudad coincide';

  /// Una pestaña sin ítems con precio, sin búsqueda (a confirmar, mapa §2: texto).
  static String pestanaVacia(CategoriaDePrecios categoria, String ciudad) =>
      'No hay ${switch (categoria) {
        CategoriaDePrecios.colecciones => 'colecciones',
        CategoriaDePrecios.libros => 'libros',
        CategoriaDePrecios.misioneros => 'misioneros',
        CategoriaDePrecios.revistas => 'revistas',
      }} con precio en $ciudad';

  static String categoria(CategoriaDePrecios categoria) => switch (categoria) {
    CategoriaDePrecios.colecciones => 'Colecciones',
    CategoriaDePrecios.libros => 'Libros',
    CategoriaDePrecios.misioneros => 'Misioneros',
    CategoriaDePrecios.revistas => 'Revistas',
  };

  /// 26·11, «Primavera 2026 terminó el 15/12 y sus precios ya no se usan. Cuando te inscriban en otra
  /// campaña, vas a ver sus precios acá.»
  static String campaniaTerminada(CampaniaTerminada campania) =>
      '${campania.nombre} terminó el ${diaMes(campania.terminoEl)} y sus precios ya no se usan. '
      'Cuando te inscriban en otra campaña, vas a ver sus precios acá.';

  /// El subtítulo de una ciudad en «Ver precios de» (26·04): «Donde estás · Primavera 2026».
  static String ciudadEnLaHoja(CiudadConsultable ciudad, {String? marca}) =>
      marca == null ? ciudad.campaniaNombre : '$marca · ${ciudad.campaniaNombre}';

  /// 26·01, «Colección de 2 libros».
  static String libros(int n) => n == 1 ? '1 libro' : '$n libros';

  /// Lo que lleva un combo, para el subtítulo de su fila: «Misionero, revista, El Deseado + 2 a
  /// elegir».
  static String componentes(PrecioDeCombo combo) {
    final fijos = [
      for (final c in combo.componentes) c.cantidad > 1 ? '${c.cantidad} × ${c.nombre}' : c.nombre,
    ].join(', ');
    final aElegir = combo.librosAElegir > 0 ? '${combo.librosAElegir} a elegir' : null;
    if (fijos.isEmpty) return aElegir ?? '';
    return aElegir == null ? fijos : '$fijos + $aElegir';
  }

  /// «$ 4.450 por libro»: el precio de la colección dividido los libros que se eligen; `null` si el
  /// combo no tiene libros a elegir.
  static String? porLibro(PrecioDeCombo combo) {
    if (combo.librosAElegir <= 0) return null;
    return '${monto((combo.centavos / combo.librosAElegir).round())} por libro';
  }

  /// El texto de la hoja del combo (26·03).
  static String textoDelCombo(PrecioDeCombo combo) {
    final n = combo.librosAElegir;
    if (n <= 0) return 'Se vende como un solo ítem. Descuenta del stock cada producto.';
    return 'Se vende como un solo ítem. Al venderla elegís ${n == 1 ? '1 libro' : 'los $n libros'} '
        'del catálogo; descuenta del stock cada producto.';
  }

  /// Lo que lee el lector de pantalla de una fila.
  static String etiquetaDeFila(ItemDePrecio item) {
    final precio = monto(item.centavos);
    return switch (item) {
      PrecioDeProducto() => [
        item.nombre,
        ?(item.codigoEditor == null ? null : 'código ${item.codigoEditor}'),
        if (item.esBonificable) 'bonificable',
        if (item.esMisionero) 'misionero',
        if (item.tipo == TipoDeProducto.revista) 'revista',
        precio,
      ].join(', '),
      final PrecioDeCombo combo => [
        item.nombre,
        componentes(combo),
        ?porLibro(combo),
        precio,
        'Ver qué lleva',
      ].where((p) => p.isNotEmpty).join(', '),
    };
  }
}
