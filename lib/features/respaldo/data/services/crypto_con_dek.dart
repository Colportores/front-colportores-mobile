import 'package:sync_engine/adapters.dart';

import '../../../../core/secure_storage/clave_db.dart';

/// El cifrado del backup (ADR-006, «Backups»): gzip y AES-256-GCM con la DEK de la DB, en el
/// teléfono y antes de que nada salga a la red.
///
/// La DEK **no se guarda en esta clase**: se pide al almacén seguro en cada operación, se usa y se
/// destruye al terminar. Así no queda una copia de la clave viva en memoria entre un backup y el
/// siguiente. Si no hay DEK (sin sesión, el almacén falla), lanza y el backup no sube nada.
final class CryptoConDek extends CompressingCrypto {
  CryptoConDek(this._leerDek, {super.isolateThreshold});

  /// Lee la DEK del almacén seguro (`CustodiaClaveDb.leerDek`).
  final Future<ClaveDb?> Function() _leerDek;

  @override
  Future<List<int>> encryptBytes(List<int> plaintext) =>
      _conLaClave((cripto) => cripto.encryptBytes(plaintext));

  @override
  Future<List<int>> decryptBytes(List<int> ciphertext) =>
      _conLaClave((cripto) => cripto.decryptBytes(ciphertext));

  Future<List<int>> _conLaClave(Future<List<int>> Function(AesGcmCrypto cripto) operacion) async {
    final dek = await _leerDek();
    if (dek == null) {
      throw StateError('no hay DEK para cifrar el backup');
    }
    try {
      // `AesGcmCrypto` copia la clave a su propia `SecretKey`: sin copias míos de los bytes, y la
      // DEK que leí se pisa al terminar.
      return await operacion(AesGcmCrypto(dek.bytes));
    } finally {
      dek.destruir();
    }
  }
}
