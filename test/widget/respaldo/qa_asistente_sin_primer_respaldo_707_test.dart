// QA de #707, ronda 2 (decisión del 12/11): el asistente de recuperación (vista 34) conecta Drive sin
// el primer respaldo, igual que «Recuperar mi respaldo» (16G·03). El implementador probó el camino
// feliz de 34·02 y de 34·09. Acá van los casos límite del mismo flujo con el primer respaldo «listo
// para salir» (`resultado = true`), para que cualquier llamada de más se note: Google falla o
// cancela, el almacén falla, la desconexión de la cuenta vieja falla, conexiones superpuestas,
// reentrada a la pantalla y los tamaños del canvas con el aviso en pantalla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInExceptionCode;

import '../../helpers/recuperacion_arnes.dart';
import '../../helpers/respaldo_drive_falsos.dart';

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tocar(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.tap(objetivo);
  await _asentar(tester);
}

bool _apagado(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed == null;

void main() {
  late ArnesRecuperacion arnes;

  setUp(() {
    arnes = ArnesRecuperacion();
    // Si se pidiera, saldría bien: así una llamada de más no pasaría inadvertida.
    arnes.primerRespaldo.resultado = true;
  });

  group('34·02 conecta sin subir el teléfono vacío', () {
    setUp(() => arnes.servicio.busqueda = const DriveSinPermiso());

    testWidgets('dado que Google falla (no cancela), cuando reintenta, ninguna de las dos '
        'conexiones pide el primer respaldo y el botón nunca queda trabado', (tester) async {
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);
      await abrirAsistente(tester, arnes);

      await _tocar(tester, cta);
      expect(textoDe(cta), 'Reintentar');
      expect(_apagado(tester, cta), isFalse);
      expect(arnes.primerRespaldo.llamadas, 0);
      expect(arnes.servicio.busquedas, 1, reason: 'sin conectar no se vuelve a buscar');

      arnes.drive.google.errorAlConectar = null;
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      await _tocar(tester, cta);

      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      expect(arnes.drive.google.conexiones, 2);
      expect(arnes.primerRespaldo.llamadas, 0);
    });

    testWidgets('dado que el almacén seguro no deja anotar la cuenta, cuando conecta, no se '
        'sube nada, el botón vuelve a habilitarse y reintenta al volver el almacén', (
      tester,
    ) async {
      arnes.drive.almacen.alEscribir = true;
      await abrirAsistente(tester, arnes);

      await _tocar(tester, cta);
      expect(arnes.primerRespaldo.llamadas, 0);
      expect(textoDe(cta), 'Reintentar');
      expect(_apagado(tester, cta), isFalse);
      expect(tester.takeException(), isNull);

      arnes.drive.almacen.alEscribir = false;
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      await _tocar(tester, cta);

      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      expect(arnes.primerRespaldo.llamadas, 0);
    });

    testWidgets('dado que cancela en Google dos veces seguidas y la tercera conecta, nunca '
        'se pide el primer respaldo', (tester) async {
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await abrirAsistente(tester, arnes);

      await _tocar(tester, cta);
      await _tocar(tester, cta);
      expect(find.text(const FailureDriveCancelado().mensaje), findsOneWidget);
      expect(arnes.drive.google.conexiones, 2);

      arnes.drive.google.errorAlConectar = null;
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      await _tocar(tester, cta);

      expect(arnes.primerRespaldo.llamadas, 0);
      expect(find.text(const FailureDriveCancelado().mensaje), findsNothing);
    });

    testWidgets('dado que Google tarda y el teléfono pierde la red, cuando vuelve, se puede '
        'reintentar y no se pide el primer respaldo', (tester) async {
      await abrirAsistente(tester, arnes);
      final compuerta = Completer<void>();
      arnes.drive.google.compuertaConectar = compuerta;

      await tester.tap(cta);
      await tester.pump();
      arnes.conexion.cambiarA(TipoConexion.sinConexion);
      await _asentar(tester);
      arnes.conexion.cambiarA(TipoConexion.wifi);
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      compuerta.complete();
      await _asentar(tester);

      expect(arnes.primerRespaldo.llamadas, 0);
      expect(tester.takeException(), isNull);
      expect(_apagado(tester, cta), isFalse, reason: 'nada quedó en «Conectando…»');
    });

    testWidgets('dado que la pantalla se vuelve a abrir tras conectar, cuando el asistente '
        'busca de nuevo, sigue sin subir el teléfono vacío', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      await _tocar(tester, cta);
      expect(arnes.primerRespaldo.llamadas, 0);

      // Reentrada: otra pantalla con el mismo arnés (Drive ya conectado en el repositorio).
      arnes.servicio.busqueda = const DriveSinPermiso();
      await abrirAsistente(tester, arnes);
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      await _tocar(tester, cta);

      expect(arnes.drive.google.conexiones, 2);
      expect(arnes.primerRespaldo.llamadas, 0);
    });
  });

  group('34·09 «Probar con otra cuenta» conecta sin subir el teléfono vacío', () {
    setUp(() => arnes.servicio.busqueda = const SinRespaldoEnDrive());

    testWidgets('dado que Google falla con la otra cuenta, cuando reintenta, vuelve a 34·02 '
        'con el aviso y no se pide el primer respaldo', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);

      await _tocar(tester, cta);

      expect(tester.widget<Text>(titulo).data, 'Buscá tu respaldo');
      expect(_apagado(tester, cta), isFalse);
      expect(arnes.primerRespaldo.llamadas, 0);

      arnes.drive.google.errorAlConectar = null;
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);
      await _tocar(tester, cta);

      expect(tester.widget<Text>(titulo).data, 'Encontramos un respaldo');
      expect(arnes.primerRespaldo.llamadas, 0);
    });

    testWidgets('dado que no se puede desconectar la cuenta anterior, cuando prueba con otra, '
        'igual conecta, sin primer respaldo y sin quedar trabado', (tester) async {
      await abrirAsistente(tester, arnes);
      arnes.drive.google.errorAlDesconectar = StateError('Google no soltó la cuenta');
      arnes.servicio.busqueda = RespaldoEncontrado(respaldoDePrueba);

      await _tocar(tester, cta);

      expect(arnes.primerRespaldo.llamadas, 0);
      expect(arnes.drive.google.conexiones, 1);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('recuperacion_cta')), findsOneWidget);
      expect(_apagado(tester, cta), isFalse);
    });

    testWidgets('dado que prueba con otra cuenta y otra más, cuando la segunda conecta, el '
        'primer respaldo no sale en ninguna', (tester) async {
      await abrirAsistente(tester, arnes);

      await _tocar(tester, cta);
      expect(tester.widget<Text>(titulo).data, 'No encontramos un respaldo');
      await _tocar(tester, cta);

      expect(arnes.drive.google.conexiones, 2);
      expect(arnes.drive.google.desconexiones, 2);
      expect(arnes.primerRespaldo.llamadas, 0);
    });
  });

  group('tamaños: 34·02 con el aviso de la falla de Google', () {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()} · texto $escala: sin '
            'overflow, con el aviso y «Reintentar» a mano', (tester) async {
          arnes.servicio.busqueda = const DriveSinPermiso();
          arnes.drive.google.errorAlConectar = falloDeGoogle(
            GoogleSignInExceptionCode.unknownError,
          );
          await abrirAsistente(tester, arnes, tamano: tamano, escala: escala);

          await _tocar(tester, cta);

          expect(tester.takeException(), isNull);
          expect(find.text(const FailureDriveNoConectado().mensaje), findsOneWidget);
          expect(textoDe(cta), 'Reintentar');
          await tester.ensureVisible(cta);
          expect(tester.getRect(cta).height, greaterThanOrEqualTo(48));
          expect(tester.getRect(cta).right, lessThanOrEqualTo(tamano.width));
        });
      }
    }
  });
}
