import 'package:flutter/material.dart';

import '../../../jornada/presentation/formato_jornada.dart';

/// Los textos de la entrevista en curso (vista 39: R·05 «Entrevista en curso», R·06 «Finalizar:
/// horas y ¿hubo venta?» y R·07 «Sin inicio registrado»; HU-VIS-005).
///
/// Los de R·05, R·06 y R·07 son los del canvas, letra por letra. **Propuesta** (no están en el
/// canvas ni en la HU): el aviso fijo sobre el mapa, los avisos de «elegí la hora» y de error, y el
/// «Guardado…» (pendiente de #450, «mapa §2: texto/aviso»).
abstract final class TextosEntrevista {
  // R·05 — entrevista en curso.
  static const enCursoTitulo = 'Entrevista en curso';
  static const enCurso = 'EN CURSO';
  static const notaDeLaVisita = '✎  Nota de la visita';
  static const finalizar = 'Finalizar entrevista';

  /// «Desde las 14:23».
  static String desdeLas(String hora) => 'Desde las $hora';

  /// La hora de [hora], con el día delante si no es de hoy: «14:23» o «Lunes 19 · 14:23». Una
  /// entrevista que quedó abierta de días atrás no se confunde con otra (decisión del 23/10 sobre
  /// la pregunta 2 del QA de #450). Lo que se guarda no cambia.
  static String horaConDia(DateTime hora, DateTime ahora) {
    final h = hora.toLocal();
    final a = ahora.toLocal();
    final esHoy = h.year == a.year && h.month == a.month && h.day == a.day;
    return esHoy ? horaCorta(h) : '${diaCorto(h)} · ${horaCorta(h)}';
  }

  /// «Desde las 14:23» si empezó hoy; «Desde Lunes 19 · 14:23» si no.
  static String desde(DateTime inicio, DateTime ahora) {
    final texto = horaConDia(inicio, ahora);
    return texto == horaCorta(inicio) ? desdeLas(texto) : 'Desde $texto';
  }

  // R·06 y R·07 — terminó la entrevista.
  static const terminoTitulo = 'Terminó la entrevista';
  static const entrada = 'Entrada';
  static const salida = 'Salida';
  static const duracion = 'Duración';
  static const hayVenta = '¿HUBO VENTA?';
  static const registrarVenta = 'Sí, registrar la venta';
  static const guardarYVolver = 'No, guardar y volver al mapa';

  /// R·07: «No registramos el inicio. Tomamos la hora de tu visita anterior (14:10). Revisala.»
  static String sinInicio(String hora) =>
      'No registramos el inicio. Tomamos la hora de tu visita anterior ($hora). Revisala.';

  // Propuesta: «Elegí la hora» (nunca se inventa una hora).
  static const elegirLaHora = 'Elegir';

  /// Propuesta: la salida no se supone cuando la app se cerró o se termina la jornada con la
  /// entrevista abierta (decisión de Cristian, 23/10, #450).
  static const pedirSalida =
      'Elegí a qué hora terminó la entrevista para seguir: no la inventamos por vos.';

  /// Propuesta: R·07 sin ninguna visita anterior de la que tomar la hora.
  static const pedirEntrada =
      'No registramos el inicio ni tenemos una visita anterior. Elegí a qué hora empezó para seguir.';

  /// Propuesta: ambas horas faltan.
  static const pedirAmbas =
      'No registramos el inicio. Elegí a qué hora empezó y a qué hora terminó la entrevista para '
      'seguir.';

  static const preguntaEntrada = '¿A qué hora empezó la entrevista?';
  static const campoEntrada = 'HORA DE ENTRADA';
  static const preguntaSalida = '¿A qué hora terminó la entrevista?';
  static const campoSalida = 'HORA DE SALIDA';

  static const guardando = 'Guardando…';

  /// Propuesta: falla al guardar. Dice qué pasó y qué hacer; la entrevista no se pierde.
  static const noPudimosGuardar =
      'No pudimos guardar la entrevista. Probá de nuevo; no perdiste nada.';

  /// Propuesta («Sin salida», 25/10): la casa de la entrevista ya no está en el teléfono, no hay dónde
  /// guardar la visita. Dice qué pasó y que puede seguir.
  static const sinLugar =
      'La casa de esta entrevista ya no está en tu teléfono, así que la entrevista se cerró sin '
      'guardar. Podés seguir.';

  /// Propuesta: ya no hay entrevista (otro toque la terminó).
  static const yaNoHayEntrevista = 'Esta entrevista ya no está en curso.';

  // «Sí, registrar la venta» (#428). Propuesta del orquestador (23/10, «Entrevista fuera»): dicen
  // qué pasó y qué hacer (mapa §2: texto/aviso).

  /// «Venta 0039 guardada.» (R·08).
  static String ventaGuardada(String numero) => 'Venta $numero guardada.';

  /// La venta no se completó: la entrevista sigue en curso. «La venta no se guardó. La entrevista con
  /// Pedro sigue en curso.»
  static String ventaNoGuardada(String persona) => persona.trim().isEmpty
      ? 'La venta no se guardó. La entrevista sigue en curso.'
      : 'La venta no se guardó. La entrevista con ${persona.trim()} sigue en curso.';

  /// Lo mismo cuando se vino de «Finalizar jornada»: la jornada no se cierra con una entrevista abierta.
  static String ventaNoGuardadaEnLaJornada(String persona) =>
      '${ventaNoGuardada(persona)} Terminala para poder cerrar la jornada.';

  /// Una falla que ya explica qué pasó y qué hacer ([mensaje]): se le antepone que la venta no se
  /// guardó.
  static String ventaNoGuardadaCon(String mensaje) => 'La venta no se guardó. $mensaje';

  /// Cuando se desconoce el nombre de a quién se le vende.
  static const sinNombre = 'Sin nombre';

  /// La venta quedó guardada pero la entrevista no se pudo cerrar del teléfono.
  static const ventaGuardadaEntrevistaAbierta =
      'La venta se guardó, pero la entrevista sigue abierta. Terminala con «No, guardar y volver al '
      'mapa» para cerrarla.';

  // Nota de la visita.
  static const campoNota = 'NOTA DE LA VISITA (OPCIONAL)';

  /// Propuesta (como el «Guardado…» de R·01): «Guardado. Grecia 3307 quedó como «Entrevista dada».»
  static String guardada(String direccion) => 'Guardado. $direccion quedó como «Entrevista dada».';

  // Aviso fijo sobre el mapa (propuesta: el canvas no lo dibuja).
  static const volverALaEntrevista = 'Volver a la entrevista';

  /// «Entrevista en curso · Grecia 3307 · 12 min».
  static String avisoEnCurso(String direccion, String duracion) =>
      direccion.isEmpty ? '$enCursoTitulo · $duracion' : '$enCursoTitulo · $direccion · $duracion';

  /// «Grecia 3307 · Pedro Gómez», o solo lo que se sabe.
  static String lugarYPersona(String direccion, String persona) =>
      [if (direccion.isNotEmpty) direccion, if (persona.isNotEmpty) persona].join(' · ');
}

/// Las claves de la entrevista en curso, para los tests y para quien las monta.
abstract final class ClavesEntrevista {
  static const hojaEnCurso = Key('entrevista_hoja_en_curso');
  static const tiempo = Key('entrevista_tiempo');
  static const botonNota = Key('entrevista_boton_nota');
  static const campoNota = Key('entrevista_campo_nota');
  static const finalizar = Key('entrevista_finalizar');

  static const hojaTermino = Key('entrevista_hoja_termino');
  static const filaEntrada = Key('entrevista_fila_entrada');
  static const filaSalida = Key('entrevista_fila_salida');
  static const duracion = Key('entrevista_duracion');
  static const avisoSinInicio = Key('entrevista_aviso_sin_inicio');
  static const avisoPedirHora = Key('entrevista_aviso_pedir_hora');
  static const avisoError = Key('entrevista_aviso_error');
  static const registrarVenta = Key('entrevista_registrar_venta');
  static const guardarYVolver = Key('entrevista_guardar_y_volver');

  static const avisoFijo = Key('entrevista_aviso_fijo');
}
