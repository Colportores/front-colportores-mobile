import 'dart:convert';

import 'package:http/http.dart' as http;

/// Pregunta a Google qué permisos tiene un token de acceso (`oauth2/v3/tokeninfo`).
///
/// Hace falta porque Google deja desmarcar un permiso al dar la autorización: la cuenta queda
/// «conectada» y el primer respaldo se estrella con `403`. Mejor enterarse al conectar.
class VerificadorAlcanceGoogle {
  VerificadorAlcanceGoogle({http.Client? cliente, this.espera = const Duration(seconds: 15)})
    : _cliente = cliente ?? http.Client();

  final http.Client _cliente;
  final Duration espera;

  static final Uri _punto = Uri.parse('https://oauth2.googleapis.com/tokeninfo');

  /// `true` si el token de [accessToken] incluye [alcance]. Con una respuesta que no es `200`
  /// (token vencido o inválido) o ilegible, `false`: ante la duda no se da por concedido. Las
  /// excepciones de red salen tal cual.
  Future<bool> incluye(String accessToken, String alcance) async {
    final respuesta = await _cliente
        .post(_punto, body: {'access_token': accessToken})
        .timeout(espera);
    if (respuesta.statusCode != 200) return false;
    final Object? json;
    try {
      json = jsonDecode(respuesta.body);
    } on FormatException {
      return false;
    }
    if (json is! Map<String, dynamic>) return false;
    final scope = json['scope'];
    if (scope is! String) return false;
    return scope.split(' ').contains(alcance);
  }
}
