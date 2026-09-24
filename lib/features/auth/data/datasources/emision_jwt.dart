import 'dart:convert';

/// Cuándo emitió el servidor [jwt] (claim `iat`, con el reloj del servidor), o `null` si no se
/// puede leer. No valida la firma: solo sirve para medir la ventana de la sesión (HU-AUTH-007).
///
/// Nunca lanza: un `FormatException` de `jsonDecode`/`base64` lleva un pedazo del texto de origen
/// en su `toString()` —acá, el token— y no puede terminar en un log (revisión de #44).
DateTime? emisionDelJwt(String jwt) {
  final partes = jwt.split('.');
  if (partes.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))));
    final iat = payload is Map<String, Object?> ? payload['iat'] : null;
    return iat is num ? DateTime.fromMillisecondsSinceEpoch(iat.toInt() * 1000, isUtc: true) : null;
  } on FormatException {
    return null;
  }
}
