/// Lo que hay en la base de este teléfono, para el asistente de recuperación (HU-SYNC-006, vista 34).
abstract interface class LectorDeLoRecuperado {
  /// `true` si la base no tiene nada de lo que la persona carga a mano (jornadas, ubicaciones,
  /// personas, ventas, cobros, visitas, agendas, notas, depósitos), ni siquiera dado de baja: es un
  /// teléfono sin datos, que es cuando se ofrece recuperar. Con algo guardado no se ofrece: la
  /// recuperación nunca pisa lo que ya hay. Lanza si no se pudo mirar.
  Future<bool> baseSinDatos();

  /// Cuánto trajo la recuperación: el resumen de «Tus datos están de vuelta» (34·08). Lanza si no se
  /// pudo mirar.
  Future<ResumenDeLoRecuperado> resumen();
}

/// Cuántas filas hay de cada cosa que la persona reconoce (las dadas de baja no cuentan).
final class ResumenDeLoRecuperado {
  const ResumenDeLoRecuperado({
    required this.ubicaciones,
    required this.personas,
    required this.ventas,
    required this.cobros,
  });

  final int ubicaciones;
  final int personas;
  final int ventas;
  final int cobros;
}
