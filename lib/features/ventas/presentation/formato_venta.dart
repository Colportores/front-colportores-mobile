import '../../catalogo/presentation/formato_precios.dart' show FormatoPrecios;
import '../domain/usecases/registrar_venta_use_case.dart' show RegistrarVentaUseCase;

/// Los textos de la vista 27 (Registrar venta, HU-VEN-001): los del canvas tal cual, y los que el
/// canvas no dibuja marcados «A confirmar» (mapa §2: texto).
abstract final class TextosVenta {
  // --- Del canvas (27A·01 a 27A·14) ---
  static const eyebrow = 'REGISTRAR VENTA';
  static const titulo = 'Nueva venta';
  static const talonario = 'Nº DE TALONARIO';
  static const enLaVenta = 'EN LA VENTA';
  static const agregar = '+ Agregar';
  static const total = 'Total';
  static const cambiarElMonto = 'Cambiar el monto';
  static const registrarVenta = 'Registrar venta';
  static const reintentar = 'Reintentar';
  static const calculado = 'Calculado';
  static const montoDeLaVenta = 'MONTO DE LA VENTA';
  static const avisoMonto = 'Tu coordinador va a ver que lo cambiaste.';
  static const errorAlGuardar =
      'No pudimos guardar la venta en tu teléfono. No se perdió nada de lo que cargaste: '
      'probá de nuevo.';
  static const armarLaColeccion = 'Armar la colección';
  static const colecciones = 'Colecciones';
  static const libros = 'Libros';
  static const misioneros = 'Misioneros';
  static const revistas = 'Revistas';

  static const eyebrowColeccion = 'NUEVA VENTA · COLECCIÓN';
  static const siempreVan = 'SIEMPRE VAN';
  static const librosQueElegis = 'LIBROS QUE ELEGÍS';
  static const elegirDelCatalogo = 'Elegir del catálogo';
  static const cambiar = 'Cambiar';
  static const agregarALaVenta = 'Agregar a la venta';

  static const buscar = 'Buscar por nombre o código';
  static const listo = 'Listo';

  static const eyebrowAgregar = 'NUEVA VENTA · AGREGAR';
  static const tituloAgregar = 'Agregar productos';
  static const sinCobrar = 'Sin cobrar';

  static const volver = 'Volver';
  static const tituloRegistrada = 'Venta registrada';
  static const entrega = 'ENTREGA';
  static const entregarAhora = 'Entregar ahora';
  static const entregarAhoraSub = 'Tenés el material a mano';
  static const entregarOtroDia = 'Entregar otro día';
  static const entregarOtroDiaSub = 'Agendamos la visita de entrega';
  static const cobro = 'COBRO';
  static const cobrarAhora = 'Cobrar ahora';
  static const cobrarAhoraSub = 'Efectivo, tarjeta o transferencia';
  static const continuar = 'Continuar';
  static const terminarSinNada = 'Terminar sin entregar ni cobrar';

  // --- De la decisión de Cristian (P3 de #158) ---
  static const avisoMotivo = 'Tu coordinador va a leer este motivo. No pongas datos del cliente.';
  static const motivo = 'MOTIVO DEL CAMBIO';

  // --- A confirmar (mapa §2: texto) ---
  static const motivoFalta = 'Escribí por qué cambiaste el monto.';
  static const montoInvalido = 'Escribí un monto válido, por ejemplo 8.500.';
  static const talonarioVacio = 'Escribí el número del talonario para registrar la venta.';
  static const talonarioRepetidoNota = 'Revisá el número del talonario para registrar la venta.';
  static const guardando = 'Guardando la venta';
  static const sinProductos = 'Elegí al menos un producto para registrar la venta.';
  static const cargandoPrecios = 'Cargando los precios';
  static const errorPrecios = 'No pudimos leer los precios guardados en tu teléfono.';
  static const sinPreciosVigentes = 'No tenés precios vigentes';
  static const sinProductosEnLaCategoria = 'No hay productos en esta categoría';
  static const salidaSinPrecio = 'Pedile al coordinador que configure el precio.';
  static const sinProductosEnLaCategoriaSub =
      'Si esperabas verlos, puede que no tengan precio en esta ciudad. $salidaSinPrecio';
  static const sinResultados = 'No encontramos ese libro';
  static const sinLibrosParaElegir = 'No hay libros para elegir en esta ciudad';
  static const quitar = 'Quitar de la venta';
  static const salirTitulo = 'Esta venta todavía no se registró';
  static const salirCuerpo = 'Si salís, se pierde lo que cargaste.';
  static const salirSeguir = 'Seguir con la venta';
  static const salirSalir = 'Salir';
  static const cerrar = 'Cerrar';
  static const subtituloLibroBonificable = 'Libro · ◆ Bonificable';
  static const subtituloLibro = 'Libro';
  static const misionero = '✦ Misionero';
  static const revista = 'Revista';

  /// El aviso cuando la venta no se guardó porque algo cargado no es válido (reintentar sin cambiar
  /// nada no lo arregla): dice qué es y qué hacer.
  static String revisaLoCargado(String detalle) {
    final sinPunto = detalle.trimRight().replaceFirst(RegExp(r'\.+$'), '');
    return '$sinPunto. Revisá lo que cargaste y probá de nuevo.';
  }

  /// Cuando la persona de la venta ya no está en el teléfono: editar lo cargado no lo arregla, hay
  /// que volver y elegirla de nuevo.
  static const personaYaNoEsta =
      'La persona de esta venta ya no está en tu teléfono. Volvé atrás y elegí a la persona de nuevo.';

  static String ubicacion(String ciudad) => '◉ Precios de $ciudad, según la casa del cliente.';

  static String coleccionDe(int libros) =>
      'Colección de $libros ${libros == 1 ? 'libro' : 'libros'}';

  static String librosAElegir(int n) => '$n ${n == 1 ? 'libro' : 'libros'} a elegir';

  static String eyebrowTalonario(String numero) => 'VENTA $numero';

  static String libroN(int n) => 'LIBRO $n';

  static String elegiElLibro(int n) => 'Elegí el libro $n para seguir.';

  static String tituloHojaLibro(int n, {required bool yaElegido}) =>
      yaElegido ? 'Cambiar el libro $n' : 'Libro $n';

  static String precioEn(String monto, String ciudad) => '$monto en $ciudad';

  static String terminoEl(String campania, DateTime dia) =>
      '$campania terminó el ${FormatoPrecios.diaMes(dia)}';

  static const terminadaSub =
      'Sus precios ya no se usan para vender. Si estás en otra campaña en curso en esta ciudad, '
      'se usan los de esa.';

  static String clienteYMonto(String nombre, String monto) => '$nombre · $monto';

  static String mas(String base) => '+ $base';
}

abstract final class FormatoVenta {
  /// «$ 8.900», o «$ 8.900,50».
  static String monto(int centavos) => FormatoPrecios.monto(centavos);

  /// Lo que la colportora escribió en «Monto de la venta» en centavos, o `null` si no es un monto:
  /// acepta «8500», «8.500», «$ 8.500» y «8.500,50» (punto de miles, coma decimal, hasta dos
  /// decimales); nada de negativos.
  static int? parsearMonto(String texto) {
    var t = texto.trim().replaceAll(r'$', '').replaceAll(RegExp(r'\s'), '');
    if (t.isEmpty) return null;
    var decimales = '';
    final coma = t.indexOf(',');
    if (coma >= 0) {
      decimales = t.substring(coma + 1);
      t = t.substring(0, coma);
      if (decimales.length > 2 || !RegExp(r'^\d*$').hasMatch(decimales)) return null;
    }
    // Puntos de miles: solo entre grupos de tres cifras («8.500», «1.234.567»).
    if (t.contains('.') && !RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(t)) return null;
    t = t.replaceAll('.', '');
    if (!RegExp(r'^\d+$').hasMatch(t)) return null;
    final pesos = int.tryParse(t);
    if (pesos == null || pesos > 21474836) return null;
    final centavos = decimales.isEmpty ? 0 : int.parse(decimales.padRight(2, '0'));
    final total = pesos * 100 + centavos;
    // Lo más que cabe en el entero del servidor: 21.474.836,47 (el último peso no llega a los 99).
    return total > RegistrarVentaUseCase.maximoCentavos ? null : total;
  }

  /// Lo que se escribe en el campo de monto cuando se abre: «8.900» o «8.900,50».
  static String montoParaEditar(int centavos) => monto(centavos).replaceFirst(r'$ ', '');
}
