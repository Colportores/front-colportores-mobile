// Fake del puerto de derivación (Argon2id) de la clave que envuelve la DEK, compartido por los tests
// de HU-AUTH-009. El cifrado de la DEK sí es el real (`CriptoSodium`): es instantáneo.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';

/// Derivación **de juguete** para tests: mezcla sal y contraseña, determinista y con 32 bytes.
/// **No es Argon2id** ni se parece: la real es `CriptoSodium`, con su propio test.
///
/// Deja controlar el momento en que termina ([pausar] + [continuar]) para poder cerrar la sesión
/// "mientras envuelve la DEK", y fallar a pedido con [falla].
final class ProveedorClaveDbFalso implements ProveedorClaveDb {
  Completer<void>? _pausa;
  Completer<void> _pedido = Completer<void>();

  /// Si está, [derivar] la lanza.
  Exception? falla;

  /// Claves entregadas, en orden.
  final entregadas = <ClaveEnvoltorio>[];

  /// Parámetros con los que se pidió cada derivación, en orden.
  final parametrosPedidos = <ParametrosArgon2id>[];

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
  Future<ClaveEnvoltorio> derivar({
    required String password,
    required Uint8List sal,
    required ParametrosArgon2id parametros,
  }) async {
    parametrosPedidos.add(parametros);
    if (!_pedido.isCompleted) _pedido.complete();
    await _pausa?.future;
    final error = falla;
    if (error != null) throw error;

    final p = utf8.encode(password);
    final clave = ClaveEnvoltorio(
      Uint8List.fromList(
        List<int>.generate(32, (i) => sal[i % sal.length] ^ p[i % p.length] ^ (i * 7)),
      ),
    );
    entregadas.add(clave);
    return clave;
  }
}
