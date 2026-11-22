import 'dart:convert';
import 'dart:io';

import '../../../../core/logging/app_logger.dart';
import '../../domain/services/geocodificador_inverso.dart';
import '../../domain/value_objects/coordenadas.dart';

/// Lee [url] y devuelve el cuerpo, o `null` si no se pudo (sin red, tiempo agotado, no 200).
typedef LectorHttp = Future<String?> Function(Uri url);

/// [LectorHttp] sobre `dart:io`, con tiempo límite y el `User-Agent` que exige la política de uso
/// de Nominatim.
LectorHttp lectorHttpIo({
  Duration limite = const Duration(seconds: 5),
  String userAgent = 'ColportoresApp/0.1',
}) {
  return (url) async {
    final cliente = HttpClient()..connectionTimeout = limite;
    try {
      final pedido = await cliente.getUrl(url).timeout(limite);
      pedido.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final respuesta = await pedido.close().timeout(limite);
      if (respuesta.statusCode != 200) {
        await respuesta.drain<void>();
        return null;
      }
      return await respuesta.transform(utf8.decoder).join().timeout(limite);
    } on Object {
      return null;
    } finally {
      cliente.close(force: true);
    }
  };
}

/// [GeocodificadorInverso] sobre Nominatim público (ADR-011: respaldo cuando no está el índice
/// offline de Photon, que todavía no se descarga en la app). Pide una dirección por vez y solo
/// cuando el punto se asienta (la pantalla espera a que el mapa deje de moverse), que es lo que
/// permite su límite de 1 consulta por segundo.
///
/// Nunca lanza. Loguea en `[MAP]` sin coordenadas ni direcciones.
final class GeocodificadorNominatim implements GeocodificadorInverso {
  GeocodificadorNominatim(this._leer, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final LectorHttp _leer;
  final AppLogger _log;

  static final _base = Uri.parse('https://nominatim.openstreetmap.org/reverse');

  @override
  Future<DireccionDelPunto?> direccionDe(Coordenadas punto) async {
    try {
      final url = _base.replace(
        queryParameters: {
          'format': 'jsonv2',
          'lat': '${punto.lat}',
          'lon': '${punto.lon}',
          'zoom': '18',
          'addressdetails': '1',
          'accept-language': 'es',
        },
      );
      final cuerpo = await _leer(url);
      if (cuerpo == null) return null;
      return interpretar(cuerpo);
    } on Object catch (e) {
      _log.warn(LogModulo.map, 'GEOCODING_FAIL', 'no se pudo geocodificar el punto', {
        'causa': e.runtimeType.toString(),
      });
      return null;
    }
  }

  /// La calle y el número de una respuesta `jsonv2` de Nominatim; `null` si no hay ninguno.
  static DireccionDelPunto? interpretar(String cuerpo) {
    final json = jsonDecode(cuerpo);
    if (json is! Map<String, Object?>) return null;
    final direccion = json['address'];
    if (direccion is! Map<String, Object?>) return null;
    String? texto(String clave) {
      final valor = direccion[clave];
      if (valor is! String) return null;
      final limpio = valor.trim();
      return limpio.isEmpty ? null : limpio;
    }

    final calle = texto('road') ?? texto('pedestrian') ?? texto('footway');
    final numero = texto('house_number');
    final resultado = DireccionDelPunto(calle: calle, numero: numero);
    return resultado.estaVacia ? null : resultado;
  }
}
