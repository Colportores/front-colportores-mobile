// Dónde vive la sesión entre arranques, y —sobre todo— entre isolates.
//
// El trabajo en segundo plano (RF-SY07) corre en un isolate propio: no tiene la
// pantalla, ni los controllers, ni nada de lo que la app tenga en memoria. Si
// la URL del BFF y el token viven en un `TextField`, el ciclo de background no
// tiene con qué hablar ni con qué autenticarse.
//
// Van al Keystore y no a `SharedPreferences` porque uno de los dos es un token
// de sesión: RD-08.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _url = 'colportaje.bff.url';
const _token = 'colportaje.sesion.token';

const _almacen = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

/// Lo que hace falta para hablar con el BFF desde cualquier isolate.
typedef Sesion = ({String url, String token});

Future<void> guardarSesion({required String url, required String token}) async {
  await _almacen.write(key: _url, value: url);
  await _almacen.write(key: _token, value: token);
}

/// `null` si todavía no se configuró: el ciclo de segundo plano no tiene nada
/// que hacer y no es un error.
Future<Sesion?> leerSesion() async {
  final url = await _almacen.read(key: _url);
  final token = await _almacen.read(key: _token);
  if (url == null || url.isEmpty || token == null || token.isEmpty) return null;
  return (url: url, token: token);
}
