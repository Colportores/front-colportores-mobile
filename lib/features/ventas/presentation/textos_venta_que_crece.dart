import '../domain/entities/venta_abierta.dart';
import '../domain/services/reglas_de_venta.dart';
import 'formato_venta.dart';

/// Los textos de «Venta crece» (vista 42, artboards 42B·09A a 09D; HU-VEN-001): los del canvas tal
/// cual, y los que el canvas no dibuja marcados «A confirmar» (mapa §2: texto).
abstract final class TextosVentaQueCrece {
  // --- Del canvas (42B·09A) ---
  static const sumarUnLibro = 'Sumar un libro';

  /// «A la venta 0039 de Pedro, sin otro talonario»: con una sola venta abierta.
  static String aLaVenta(String numero, String? nombre) {
    final n = nombre?.trim() ?? '';
    return n.isEmpty
        ? 'A la venta $numero, sin otro talonario'
        : 'A la venta $numero de $n, sin otro talonario';
  }

  // --- Del canvas (42B·09B) ---
  static const aQueVenta = '¿A qué venta lo sumás?';
  static const sumarAEstaVenta = 'Sumar a esta venta';
  static const cancelar = 'Cancelar';

  /// «Venta 0039 · 23/10».
  static String ventaDel(VentaAbierta venta) =>
      'Venta ${venta.numeroTalonario} · ${_diaMes(ReglasDeVenta.diaDeMontevideo(venta.fecha))}';

  /// «Colección de 1 libro · saldo $ 800». Sin saldo (falta entregar), lo que falta (a confirmar).
  static String detalleDe(VentaAbierta venta) {
    final partes = [
      if (venta.descripcion.trim().isNotEmpty) venta.descripcion.trim(),
      if (venta.tieneSaldo) 'saldo ${FormatoVenta.monto(venta.saldoCentavos)}' else faltaEntregar,
    ];
    return partes.join(' · ');
  }

  // --- Del canvas (42B·09C) ---
  /// «VENTA 0039 · SUMAR UN LIBRO».
  static String eyebrow(String numero) => 'VENTA $numero · SUMAR UN LIBRO';

  /// «Venta 0039».
  static String titulo(String numero) => 'Venta $numero';

  /// «Pedro Gómez · Grecia 3307 · el mismo talonario».
  static String subtitulo(String nombre, String direccion) => [
    if (nombre.trim().isNotEmpty) nombre.trim(),
    if (direccion.trim().isNotEmpty) direccion.trim(),
    'el mismo talonario',
  ].join(' · ');

  /// «YA VENDIDO · 23/10 · NO SE CAMBIA».
  static String yaVendido(DateTime fechaDeLaVenta) =>
      'YA VENDIDO · ${_diaMes(ReglasDeVenta.diaDeMontevideo(fechaDeLaVenta))} · NO SE CAMBIA';

  static const seSumaHoy = 'SE SUMA HOY';
  static const nuevo = 'Nuevo';
  static const totalAnterior = 'Total anterior';
  static const total = 'Total';
  static const pagado = 'Pagado';
  static const saldo = 'Saldo';

  /// «Sumar a la venta 0039».
  static String sumarALaVenta(String numero) => 'Sumar a la venta $numero';

  /// «Con sus 3 libros»: lo que traía el combo ya vendido.
  static String conSusLibros(int libros) => libros == 1 ? 'Con su libro' : 'Con sus $libros libros';

  /// «entregada el 23/10».
  static String entregadaEl(DateTime dia) =>
      'entregada el ${_diaMes(ReglasDeVenta.diaDeMontevideo(dia))}';

  // --- Del canvas (42B·09D) ---
  /// «VENTA 0039».
  static String eyebrowCierre(String numero) => 'VENTA $numero';

  /// «Libro sumado a la venta 0039»; con más de un libro, en plural (a confirmar).
  static String tituloCierre(String numero, int unidades) =>
      unidades == 1 ? 'Libro sumado a la venta $numero' : 'Libros sumados a la venta $numero';

  /// «Pedro Gómez · total $ 1.600 · saldo $ 1.200».
  static String subtituloCierre(String nombre, int totalCentavos, int saldoCentavos) => [
    if (nombre.trim().isNotEmpty) nombre.trim(),
    'total ${FormatoVenta.monto(totalCentavos)}',
    'saldo ${FormatoVenta.monto(saldoCentavos)}',
  ].join(' · ');

  static const entregaDelLibroNuevo = 'ENTREGA DEL LIBRO NUEVO';

  /// «Saldo de la venta: $ 1.200».
  static String saldoDeLaVenta(int saldoCentavos) =>
      'Saldo de la venta: ${FormatoVenta.monto(saldoCentavos)}';

  /// El aviso en el mapa: «Libro sumado a la venta 0039. Saldo $ 1.200.». Sin saldo, sin la cuenta
  /// (a confirmar); con más de un libro, en plural (a confirmar).
  static String aviso(String numero, int unidades, int saldoCentavos) {
    final hecho = unidades == 1
        ? 'Libro sumado a la venta $numero.'
        : 'Libros sumados a la venta $numero.';
    return saldoCentavos > 0 ? '$hecho Saldo ${FormatoVenta.monto(saldoCentavos)}.' : hecho;
  }

  // --- A confirmar (mapa §2: texto) ---
  /// La fila con más de una venta abierta de la persona.
  static String aUnaDeSusVentas(String? nombre) {
    final n = nombre?.trim() ?? '';
    return n.isEmpty
        ? 'A una de sus ventas abiertas, sin otro talonario'
        : 'A una venta abierta de $n, sin otro talonario';
  }

  static const faltaEntregar = 'falta entregar';

  /// Ya no quedan ventas abiertas (se pagaron y entregaron mientras la hoja estaba abierta).
  static String sinVentaAbierta(String? nombre) {
    final n = nombre?.trim() ?? '';
    return n.isEmpty
        ? 'Ya no hay una venta abierta. Para otro libro, registrá una venta nueva.'
        : '$n ya no tiene una venta abierta. Para otro libro, registrá una venta nueva.';
  }

  static const noPudimosLeer =
      'No pudimos leer las ventas guardadas en tu teléfono. Probá de nuevo en unos segundos.';
  static const noPudimosAbrir = 'No pudimos abrir «Sumar un libro». Probá de nuevo.';

  static const montoDeLoQueSumas = 'MONTO DE LO QUE SUMÁS';

  /// La venta ya tiene un motivo del monto a mano: lo que se suma va al precio de la lista (pendiente
  /// de decisión: una venta lleva un solo motivo).
  static const yaTieneMotivo =
      'Esta venta ya tiene el monto cambiado a mano: lo que sumás va con el precio de la lista.';

  static const misioneros =
      'Los misioneros no se suman a una venta: anotalos al terminar la entrevista, en «Lo que '
      'dejaste».';

  static const salirTitulo = 'Todavía no sumaste el libro';
  static const salirCuerpo = 'Si salís, se pierde lo que cargaste. La venta queda como estaba.';
  static const salirSeguir = 'Seguir sumando';

  static const modificarCuotas = 'Modificar cuotas';

  /// «Repartí el saldo nuevo de $ 1.200 en las cuotas».
  static String modificarCuotasSub(int saldoCentavos) =>
      'Repartí el saldo nuevo de ${FormatoVenta.monto(saldoCentavos)} en las cuotas';

  /// Lo que lee el lector de pantalla de una opción de «¿A qué venta lo sumás?».
  static String opcionParaLector(VentaAbierta venta) => [
    ventaDel(venta),
    detalleDe(venta),
    'Total ${FormatoVenta.monto(venta.montoTotalCentavos)}',
  ].join('. ');

  static String _diaMes(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
