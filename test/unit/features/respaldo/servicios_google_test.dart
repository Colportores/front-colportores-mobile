// HU-SYNC-004 — Lo que está entre la app y Google: la comprobación del permiso y el servicio sin
// configurar.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/core/config/config_google.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/data/services/verificador_alcance_google.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('VerificadorAlcanceGoogle', () {
    const drive = 'https://www.googleapis.com/auth/drive.appdata';

    VerificadorAlcanceGoogle con(Future<http.Response> Function(http.Request) respuesta) =>
        VerificadorAlcanceGoogle(cliente: MockClient(respuesta));

    test('el token con el permiso de Drive entre sus permisos: sí', () async {
      late http.Request pedido;
      final v = con((r) async {
        pedido = r;
        return http.Response('{"scope": "openid email $drive"}', 200);
      });
      expect(await v.incluye('ya29.abc', drive), isTrue);
      expect(pedido.method, 'POST');
      expect(pedido.url.toString(), 'https://oauth2.googleapis.com/tokeninfo');
      expect(pedido.bodyFields, {'access_token': 'ya29.abc'});
    });

    test('Escenario: la persona desmarcó el permiso de Drive: no', () async {
      final v = con((_) async => http.Response('{"scope": "openid email profile"}', 200));
      expect(await v.incluye('t', drive), isFalse);
    });

    test('un permiso parecido no cuenta: se compara entero', () async {
      final v = con((_) async => http.Response('{"scope": "${drive}x"}', 200));
      expect(await v.incluye('t', drive), isFalse);
    });

    test('token vencido o inválido (no 200), cuerpo ilegible o sin scope: no', () async {
      expect(await con((_) async => http.Response('{}', 400)).incluye('t', drive), isFalse);
      expect(await con((_) async => http.Response('no json', 200)).incluye('t', drive), isFalse);
      expect(await con((_) async => http.Response('[]', 200)).incluye('t', drive), isFalse);
      expect(
        await con((_) async => http.Response('{"scope": 3}', 200)).incluye('t', drive),
        isFalse,
      );
    });

    test('las fallas de red salen tal cual, para que el repositorio diga «sin conexión»', () async {
      final sinRed = con((_) async => throw const SocketException('sin red'));
      await expectLater(sinRed.incluye('t', drive), throwsA(isA<SocketException>()));

      final lento = VerificadorAlcanceGoogle(
        cliente: MockClient((_) => Completer<http.Response>().future),
        espera: const Duration(milliseconds: 10),
      );
      await expectLater(lento.incluye('t', drive), throwsA(isA<TimeoutException>()));
    });
  });

  group('ServicioGoogleSinConfigurar', () {
    test('no se puede conectar, y lo dice', () async {
      await expectLater(const ServicioGoogleSinConfigurar().conectar(), throwsA(isA<StateError>()));
    });

    test('no da token y desconectar no hace nada', () async {
      const s = ServicioGoogleSinConfigurar();
      expect(await s.tokenSilencioso(), isNull);
      await s.desconectar();
    });
  });

  group('ConfigGoogle', () {
    test('sin --dart-define no está configurada y pide solo el permiso de Drive', () {
      expect(ConfigGoogle.configurada, isFalse);
      expect(ConfigGoogle.alcanceDrive, 'https://www.googleapis.com/auth/drive.appdata');
    });
  });
}
