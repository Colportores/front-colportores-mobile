import 'dart:convert';

/// El `iat` más alto que se acepta, en segundos: el máximo que representa `DateTime`. Más allá,
/// multiplicar por 1000 desborda el entero y daría una fecha inventada.
const _iatMaximo = 8640000000000;

/// Cuándo emitió el servidor [jwt] (claim `iat`, con el reloj del servidor), o `null` si no se
/// puede leer. No valida la firma: solo sirve para medir la ventana de la sesión (HU-AUTH-007).
///
/// Nunca lanza: un `FormatException` de `jsonDecode`/`base64` lleva un pedazo del texto de origen
/// en su `toString()` —acá, el token— y no puede terminar en un log (revisión de #44). Un `iat`
/// negativo, no finito o fuera del rango de `DateTime` también da `null`.
DateTime? emisionDelJwt(String jwt) {
  final partes = jwt.split('.');
  if (partes.length != 3) return null;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))));
    final iat = payload is Map<String, Object?> ? payload['iat'] : null;
    if (iat is! num || !iat.isFinite || iat < 0 || iat > _iatMaximo) return null;
    return DateTime.fromMillisecondsSinceEpoch(iat.toInt() * 1000, isUtc: true);
  } on Object {
    return null;
  }
}
