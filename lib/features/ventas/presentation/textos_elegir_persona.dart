/// Los textos de «+ Registrar venta» desde la pestaña Ventas: elegir a la persona (HU-VEN-001).
///
/// El diseño no dibuja esta lista (Cristian eligió reusar las piezas aprobadas, 28/10): lo que no
/// sale del canvas es «A confirmar (mapa §2: texto)».
abstract final class TextosElegirPersona {
  /// El botón de la pestaña Ventas (bosquejo de `App Colportor`).
  static const registrarVenta = '+ Registrar venta';

  static const eyebrow = 'NUEVA VENTA';
  static const titulo = '¿A quién le vendés?';

  // --- A confirmar (mapa §2: texto) ---
  static const buscar = 'Buscar por nombre o dirección';
  static const borrarBusqueda = 'Borrar búsqueda';
  static const sinNombre = 'Sin nombre';
  static const cargando = 'Cargando las personas';
  static const errorLectura = 'No pudimos leer tus personas. No se perdió nada: probá de nuevo.';
  static const reintentar = 'Reintentar';
  static const sinPersonas = 'Todavía no tenés personas cargadas';
  static const sinPersonasAyuda =
      'Para registrar una venta, primero sumá a la persona en su casa: tocá la casa en el mapa y '
      'agregala desde «Personas».';
  static const irAlMapa = 'Ir al mapa';
  static const sinResultados = 'No encontramos a nadie';
  static const sinResultadosAyuda =
      'Revisá el nombre o la dirección, o borrá la búsqueda para ver a todas las personas.';

  /// «PERSONAS · 3».
  static String personas(int cantidad) => 'PERSONAS · $cantidad';

  /// El aviso al volver a la pestaña Ventas con la venta ya guardada.
  static String ventaGuardada(String numero) => 'Venta $numero guardada.';
}
