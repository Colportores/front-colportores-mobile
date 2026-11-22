import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// ¿[error] es una falla de la red (sin conexión, DNS, TLS, conexión cortada, tiempo agotado) y no
/// un error de programación? Los adaptadores HTTP de los mapas la convierten en `ErrorRedTiles`.
bool esFallaDeRed(Object error) {
  return error is IOException || error is http.ClientException || error is TimeoutException;
}
