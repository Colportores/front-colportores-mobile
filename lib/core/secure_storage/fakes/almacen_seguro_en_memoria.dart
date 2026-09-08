import '../almacen_seguro.dart';

/// [AlmacenSeguro] en memoria: se pierde al reiniciar la app, a propósito.
///
/// **No es código de producción.** Sirve para los tests y para correr la app en un entorno sin
/// Keystore/Keychain, igual que `AuthLocalDataSourceEnMemoria` en auth.
final class AlmacenSeguroEnMemoria implements AlmacenSeguro {
  AlmacenSeguroEnMemoria([Map<ClaveSegura, String>? inicial]) : _valores = {...?inicial};

  final Map<ClaveSegura, String> _valores;

  /// Si es `true`, toda operación lanza [AlmacenSeguroException]. Simula el dispositivo donde ni
  /// el Keystore ni el fallback de software funcionan (HU-AUTH-009, escenario de error).
  bool simularFalla = false;

  /// Contenido actual, para que los tests puedan verificar **qué** quedó guardado —
  /// en particular, que la clave de la DB no se persiste nunca.
  Map<ClaveSegura, String> get contenido => Map.unmodifiable(_valores);

  @override
  Future<String?> leer(ClaveSegura clave) async {
    _fallarSiCorresponde('leer', clave);
    return _valores[clave];
  }

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    _fallarSiCorresponde('escribir', clave);
    _valores[clave] = valor;
  }

  @override
  Future<void> borrar(ClaveSegura clave) async {
    _fallarSiCorresponde('borrar', clave);
    _valores.remove(clave);
  }

  @override
  Future<void> borrarTodo() async {
    _fallarSiCorresponde('borrarTodo', null);
    _valores.clear();
  }

  void _fallarSiCorresponde(String operacion, ClaveSegura? clave) {
    if (simularFalla) {
      throw AlmacenSeguroException(operacion: operacion, clave: clave);
    }
  }
}
