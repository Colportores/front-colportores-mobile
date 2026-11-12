/// Puerto: cuándo bajó el teléfono por última vez los precios (26·09: «Son los precios que recibiste
/// el 22/10 a las 18:00»). `null` si no se sabe (todavía no bajó nada o no se pudo leer): la
/// pantalla lo dice sin inventar una fecha.
abstract interface class FechaDeLosPrecios {
  Future<DateTime?> ultimaBajada();
}

/// Los días del aviso fuerte (`parametro_global.dias_antiguedad_precios`, decisión de Cristian,
/// 23/10, «Precio viejo»): los cambia Administración y bajan con el pull. Mientras esa réplica no
/// esté en el teléfono rigen los 15 de siempre.
abstract interface class DiasDeAntiguedadDePrecios {
  Future<int> dias();
}
