import 'dart:async';

/// Turno único para los flujos que tocan la DB local y su DEK: inicializar, recuperar con la
/// contraseña y empezar de nuevo (HU-AUTH-009, ADR-006).
///
/// Sin él, dos flujos en paralelo se pisan: el segundo `descartar()` borra la DEK del primero, y la
/// DB queda cifrada con una DEK que no está guardada en ningún lado —pérdida total— (revisión del
/// PR #81). Con el turno, el segundo espera a que termine el primero y recién ahí mira el estado,
/// que ya refleja lo que hizo el otro.
///
/// Una sola instancia para toda la app (el cableado lo da `keepAlive`). Es Dart puro: no sabe de
/// qué se trata cada flujo, solo los pone en fila.
final class TurnoDbLocal {
  Future<void>? _enCurso;

  /// Corre [flujo] cuando no haya otro en curso. Espera en vez de rechazar: quien llama no controla
  /// el solapamiento (un login y una sesión restaurada que llegan juntos, dos toques).
  Future<T> enExclusiva<T>(Future<T> Function() flujo) async {
    // `_enCurso` se toma antes del primer `await` del flujo: no hay ventana entre mirar y tomar.
    // El `while` vuelve a mirar porque varios que esperan despiertan juntos.
    while (_enCurso != null) {
      await _enCurso;
    }
    final turno = Completer<void>();
    _enCurso = turno.future;
    try {
      return await flujo();
    } finally {
      _enCurso = null;
      turno.complete();
    }
  }
}
