import '../seguridad_dispositivo.dart';

/// [SeguridadDispositivo] con respuestas fijas.
///
/// **No es código de producción.** Sirve para los tests y para correr la app sin el canal nativo
/// (por ejemplo, en un entorno sin Android ni iOS), igual que `AlmacenSeguroEnMemoria`.
final class SeguridadDispositivoFija implements SeguridadDispositivo {
  SeguridadDispositivoFija({this.bloqueoPantalla = true, this.nivel = NivelAlmacenSeguro.hardware});

  bool bloqueoPantalla;
  NivelAlmacenSeguro nivel;

  /// Si es `true`, las dos consultas lanzan [SeguridadDispositivoException].
  bool simularFalla = false;

  @override
  Future<bool> tieneBloqueoPantalla() async {
    if (simularFalla) throw const SeguridadDispositivoException(operacion: 'bloqueoPantalla');
    return bloqueoPantalla;
  }

  @override
  Future<NivelAlmacenSeguro> nivelAlmacenSeguro() async {
    if (simularFalla) throw const SeguridadDispositivoException(operacion: 'nivelAlmacen');
    return nivel;
  }
}
