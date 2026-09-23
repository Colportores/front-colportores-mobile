// Fake del puerto de derivación de la clave de la DB, compartido por los tests de HU-AUTH-009.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:colportores_mobile/core/secure_storage/clave_db.dart';

/// Derivación **de juguete** para tests: `sal XOR contraseña`, determinista y con 32 bytes.
/// **No es Argon2id** ni se parece: la real está pendiente (Supuesto S11).
///
/// Deja controlar el momento en que termina ([pausar] + [continuar]) para poder cerrar la sesión
/// "mientras deriva", y fallar a pedido con [falla].
final class ProveedorClaveDbFalso implements ProveedorClaveDb {
  Completer<void>? _pausa;
  Completer<void> _pedido = Completer<void>();

  /// Si está, [derivar] la lanza.
  Exception? falla;

  /// Claves entregadas, en orden.
  final entregadas = <ClaveDb>[];

  /// A partir de acá, [derivar] espera a [continuar] antes de devolver.
  void pausar() {
    _pausa = Completer<void>();
    _pedido = Completer<void>();
  }

  /// Se completa cuando alguien llamó a [derivar] después del último [pausar].
  Future<void> get seEstaDerivando => _pedido.future;

  /// Libera la derivación pausada.
  void continuar() => _pausa?.complete();

  @override
  Future<ClaveDb> derivar({required String password, required Uint8List sal}) async {
    if (!_pedido.isCompleted) _pedido.complete();
    await _pausa?.future;
    final error = falla;
    if (error != null) throw error;

    final p = utf8.encode(password);
    final clave = ClaveDb(
      Uint8List.fromList(List<int>.generate(32, (i) => sal[i] ^ p[i % p.length])),
    );
    entregadas.add(clave);
    return clave;
  }
}
