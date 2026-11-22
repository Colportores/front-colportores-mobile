// QA de #707 (vista 16, artboard 16G·03): «Recuperar mi respaldo» conecta Drive sin el primer
// respaldo del teléfono vacío (decisión de Cristian, 11/11, «Resp. vacío»). La app entera, con el
// arnés de #691. El implementador probó el camino feliz, la cancelación y la fila «Cuenta Drive»;
// acá van los casos límite: falla y reintento dentro de la hoja, sin conexión, doble toque,
// acciones superpuestas con la fila «Cuenta Drive», datos que se cargan mientras se conecta y los
// tamaños del canvas (360×640 y 412×915, texto 1,0 y 2,0).
import 'dart:async';

import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInExceptionCode;

import '../../helpers/qa_vista16g_691_arnes.dart';
import '../../helpers/recuperacion_arnes.dart';
import '../../helpers/respaldo_drive_falsos.dart';

const _avisoConPrimero = 'Listo. Hicimos el primer respaldo en tu Drive.';
const _avisoSinPrimero = 'Backup configurado. Próximo backup nocturno.';
const _yaHayDatos =
    'Ya hay datos cargados en este teléfono, así que no se puede traer el respaldo.';

final _filaDrive = find.byKey(const Key('configuracion_drive_fila'));
final _avisoConectado = find.byKey(const Key('configuracion_drive_conectado'));

void main() {
  late ArnesRecuperacion arnes;

  setUp(() {
    arnes = ArnesRecuperacion();
    // Si se pidiera, saldría bien: así el aviso de «primer respaldo hecho» sería visible.
    arnes.primerRespaldo.resultado = true;
  });

  DriveConectada? driveDe(WidgetTester tester) {
    final estado = raiz(tester).read(estadoRespaldoDriveProvider).value;
    return estado is DriveConectada ? estado : null;
  }

  group('16G·03 conecta para recuperar, sin subir el teléfono vacío', () {
    testWidgets('dado que Google falla (no cancela), cuando reintenta en la misma hoja, '
        'tampoco se pide el primer respaldo y sigue al asistente', (tester) async {
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      await tocar(tester, conectarConGoogle);
      expect(hojaConectar, findsOneWidget, reason: 'la hoja queda con el error y «Reintentar»');
      expect(arnes.primerRespaldo.llamadas, 0);

      arnes.drive.google.errorAlConectar = null;
      await tocar(tester, conectarConGoogle);
      await asentar(tester);

      expect(asistente, findsOneWidget);
      expect(arnes.primerRespaldo.llamadas, 0);
      expect(driveDe(tester), isNotNull);
      expect(find.text(_avisoConPrimero), findsNothing);
      expect(find.text(_avisoSinPrimero), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado que el almacén falla al anotar la cuenta, cuando reintenta, no queda '
        'trabada la hoja y el reintento conecta sin primer respaldo', (tester) async {
      arnes.drive.almacen.alEscribir = true;
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      await tocar(tester, conectarConGoogle);

      expect(hojaConectar, findsOneWidget);
      expect(tester.widget<FilledButton>(conectarConGoogle).onPressed, isNotNull);
      expect(arnes.primerRespaldo.llamadas, 0);
      expect(driveDe(tester), isNull, reason: 'no queda una cuenta a medias');

      arnes.drive.almacen.alEscribir = false;
      await tocar(tester, conectarConGoogle);
      await asentar(tester);

      expect(asistente, findsOneWidget);
      expect(arnes.primerRespaldo.llamadas, 0);
    });

    testWidgets('dado que el teléfono no tiene red, cuando vuelve y conecta, tampoco se pide '
        'el primer respaldo', (tester) async {
      final telefono = await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await asentar(tester);
      await tocar(tester, filaRecuperarRespaldo);
      expect(find.text('Necesitás conexión para conectar Google Drive.'), findsOneWidget);

      telefono.conexion.cambiarA(TipoConexion.wifi);
      await asentar(tester);
      await tocar(tester, conectarConGoogle);
      await asentar(tester);

      expect(asistente, findsOneWidget);
      expect(arnes.primerRespaldo.llamadas, 0);
    });

    testWidgets('dado que toca «Conectar con Google» dos veces seguidas, cuando Google tarda, '
        'se abre una sola conexión y no se pide el primer respaldo', (tester) async {
      final compuerta = Completer<void>();
      arnes.drive.google.compuertaConectar = compuerta;
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);

      await tester.tap(conectarConGoogle);
      await tester.pump();
      await tester.tap(conectarConGoogle, warnIfMissed: false);
      await tester.pump();
      expect(arnes.drive.google.conexiones, 1);

      compuerta.complete();
      await asentar(tester);

      expect(arnes.drive.google.conexiones, 1);
      expect(arnes.primerRespaldo.llamadas, 0);
      expect(asistente, findsOneWidget);
    });

    testWidgets('dado que otra conexión ya está en curso, cuando conecta para recuperar, la '
        'segunda no se pisa: es «ocupado», no hace el primer respaldo y no pierde la primera', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      arnes.drive.google.compuertaConectar = compuerta;
      await abrirApp(tester, arnes);
      final notificador = raiz(tester).read(estadoRespaldoDriveProvider.notifier);
      await raiz(tester).read(estadoRespaldoDriveProvider.future);

      final primera = notificador.conectar(conPrimerRespaldo: false);
      final segunda = await notificador.conectar();
      expect(segunda, isA<DriveOcupado>());

      compuerta.complete();
      final resultado = await tester.runAsync(() => primera);
      expect(resultado, isA<DriveQuedoConectado>());
      expect((resultado! as DriveQuedoConectado).primerRespaldoHecho, isFalse);
      expect(arnes.primerRespaldo.llamadas, 0);
      expect(arnes.drive.google.conexiones, 1);
    });

    testWidgets('dado que cancela en Google al recuperar, cuando después conecta desde la fila '
        '«Cuenta Drive», esa sí hace el primer respaldo y lo avisa', (tester) async {
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      await tocar(tester, conectarConGoogle);
      expect(avisoCancelado, findsOneWidget);
      expect(arnes.primerRespaldo.llamadas, 0);

      arnes.drive.google.errorAlConectar = null;
      await tocar(tester, _filaDrive);
      await tocar(tester, conectarConGoogle);
      await asentar(tester);

      expect(arnes.primerRespaldo.llamadas, 1, reason: 'la bandera no se pega entre intentos');
      expect(find.text(_avisoConPrimero), findsOneWidget);
      expect(_avisoConectado, findsOneWidget);
      expect(asistente, findsNothing);
    });

    testWidgets('dado que se cargan datos mientras elige la cuenta, cuando termina de conectar, '
        'avisa que ya no se puede recuperar, Drive queda conectado y no se sube nada', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      arnes.drive.google.compuertaConectar = compuerta;
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      await tester.tap(conectarConGoogle);
      await tester.pump();

      arnes.lector.sinDatos = false;
      compuerta.complete();
      await asentar(tester);

      expect(avisoNo, findsOneWidget);
      expect(find.text(_yaHayDatos), findsOneWidget);
      expect(asistente, findsNothing);
      expect(driveDe(tester), isNotNull, reason: 'la conexión que se hizo no se deshace');
      expect(arnes.primerRespaldo.llamadas, 0);
      expect(arnes.resuelta.desmarcas, 0);
      // La fila de recuperación queda apagada con el motivo, y se puede volver a tocar el resto.
      await tester.ensureVisible(filaRecuperarRespaldo);
      expect(motivoFila, findsOneWidget);
    });

    testWidgets('dado que no se puede revisar la base, cuando termina de conectar, avisa y la '
        'fila no queda trabada para otro intento', (tester) async {
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      arnes.lector.errorAlMirar = StateError('base ilegible');
      await tocar(tester, filaRecuperarRespaldo);
      await tocar(tester, conectarConGoogle);
      await asentar(tester);

      expect(avisoNo, findsOneWidget);
      expect(
        find.text(
          'No pudimos revisar si este teléfono tiene datos. Probá de nuevo en unos minutos.',
        ),
        findsOneWidget,
      );
      expect(arnes.primerRespaldo.llamadas, 0);

      arnes.lector.errorAlMirar = null;
      await tester.ensureVisible(atrasConfiguracion);
      await tester.tap(atrasConfiguracion);
      await asentar(tester);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      await asentar(tester);
      // Con la cuenta ya conectada, el segundo intento abre la hoja 16G·02 (no vuelve a conectar).
      expect(arnes.drive.google.conexiones, 1);
      expect(find.text('Empezar'), findsOneWidget);
    });

    testWidgets('dado que reentra a Configuración después de conectar para recuperar, la fila '
        '«Cuenta Drive» muestra la cuenta conectada, sin aviso de primer respaldo', (tester) async {
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      // Se cargan datos justo antes del reinicio: la conexión queda y Configuración sigue abierta.
      arnes.lector.sinDatos = false;
      await tocar(tester, conectarConGoogle);
      await asentar(tester);
      expect(asistente, findsNothing);

      await tester.ensureVisible(_filaDrive);
      expect(
        find.descendant(of: _filaDrive, matching: find.text('ana.gomez@gmail.com')),
        findsOneWidget,
      );
      expect(find.text(_avisoConPrimero), findsNothing);
      expect(find.text(_avisoSinPrimero), findsNothing);
    });
  });

  group('Tamaños del canvas: la conexión de 16G·03 se completa sin desborde', () {
    for (final (nombre, ancho, alto, escala) in tamanos) {
      testWidgets('conecta y sigue al asistente · $nombre', (tester) async {
        await abrirApp(tester, arnes, ancho: ancho, alto: alto, escala: escala);
        await irAConfiguracion(tester);
        await tocar(tester, filaRecuperarRespaldo);
        expect(hojaConectar, findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'sin overflow en la hoja');
        await tocar(tester, conectarConGoogle);
        await asentar(tester);

        expect(asistente, findsOneWidget);
        expect(arnes.primerRespaldo.llamadas, 0);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
