// QA de la vista 16, artboards 16G (#691): «Recuperar mi respaldo» en Configuración.
//
// Inventario del canvas (`16 Configuracion.dc.html`, grupo G): 16G·01 fila con Drive · 16G·02 hoja
// «Antes de empezar» · 16G·03 sin Drive conectado · 16G·04 apagada con el motivo. Más lo que el
// canvas no dibuja: Drive ilegible, datos cargados con la hoja abierta, correo largo, falla a mitad.
//
// Matriz de nueve estados × 360×640 / 412×915 × texto 1,0 / 2,0 con las fuentes reales. Las guías de
// accesibilidad están en `qa_vista16g_recuperar_respaldo_691_guias_test.dart` (fuente de prueba:
// con las reales `textContrastGuideline` da falsos negativos). Capturas con
// `--dart-define=QA_CAPTURAS=true`.
import 'dart:async';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_recuperar_respaldo.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInExceptionCode;

import '../../helpers/qa_vista16g_691_arnes.dart';
import '../../helpers/recuperacion_arnes.dart';
import '../../helpers/respaldo_drive_falsos.dart';

// Los literales del canvas.
const _filaTitulo = 'Recuperar mi respaldo';
const _detalleConDrive = 'Traé a este teléfono lo que guardaste en tu Drive';
const _detalleSinDrive = 'Conectá tu Drive para buscar tu respaldo';
const _motivoApagada = 'No disponible: ya cargaste datos en este teléfono';
const _tituloHoja = 'Recuperar tu respaldo';
const _textoHoja =
    'Traemos a este teléfono lo que guardaste en ana.gomez@gmail.com. Se puede mientras no '
    'cargues nada acá.';

void _esperaDelEstado(WidgetTester tester, Estado16G estado) {
  switch (estado) {
    case Estado16G.fila01:
      expect(find.text(_detalleConDrive), findsOneWidget);
      expect(tester.widget<ListTile>(filaRecuperarRespaldo).enabled, isTrue);
    case Estado16G.hoja02:
      expect(hojaRecuperarRespaldo, findsOneWidget);
      expect(find.text(_tituloHoja), findsOneWidget);
      expect(find.text(_textoHoja), findsOneWidget);
      expect(find.text('Empezar'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);
    case Estado16G.fila03:
      expect(find.text(_detalleSinDrive), findsOneWidget);
      expect(tester.widget<ListTile>(filaRecuperarRespaldo).enabled, isTrue);
    case Estado16G.conexion03:
      expect(hojaConectar, findsOneWidget);
      expect(conectarConGoogle, findsOneWidget);
    case Estado16G.cancelado03:
      expect(avisoCancelado, findsOneWidget);
      expect(hojaConectar, findsNothing);
    case Estado16G.fila04:
      expect(find.text(_motivoApagada), findsOneWidget);
      expect(tester.widget<ListTile>(filaRecuperarRespaldo).enabled, isFalse);
    case Estado16G.errorDrive:
      expect(avisoNo, findsOneWidget);
      expect(
        find.text('No pudimos ver el estado de tu Drive. Probá de nuevo en unos minutos.'),
        findsOneWidget,
      );
    case Estado16G.hayDatos:
      expect(avisoNo, findsOneWidget);
      expect(find.text(_motivoApagada), findsOneWidget);
    case Estado16G.hojaCorreoLargo:
      expect(hojaRecuperarRespaldo, findsOneWidget);
      expect(
        find.descendant(
          of: hojaRecuperarRespaldo,
          matching: find.textContaining('colportora.de.la.zona.cerro.norte'),
        ),
        findsOneWidget,
      );
  }
}

/// Lo que se tiene que poder tocar en cada estado, con la hoja o la página scrolleada hasta ahí.
List<Finder> _tocablesDelEstado(Estado16G estado) => switch (estado) {
  Estado16G.hoja02 || Estado16G.hojaCorreoLargo => [hojaRecuperarEmpezar, hojaRecuperarAhoraNo],
  Estado16G.conexion03 => [conectarConGoogle, conectarAhoraNo],
  Estado16G.fila01 || Estado16G.fila03 || Estado16G.cancelado03 => [filaRecuperarRespaldo],
  Estado16G.fila04 || Estado16G.errorDrive || Estado16G.hayDatos => [],
};

void main() {
  late ArnesRecuperacion arnes;

  setUp(() => arnes = ArnesRecuperacion());

  group('Matriz: cada estado en cada tamaño, sin desborde y con todo alcanzable', () {
    for (final estado in Estado16G.values) {
      for (final (nombre, ancho, alto, escala) in tamanos) {
        testWidgets('${estado.rotulo} · $nombre', (tester) async {
          await abrirApp(tester, arnes, ancho: ancho, alto: alto, escala: escala);
          await armarEstado(tester, arnes, estado);

          expect(tester.takeException(), isNull, reason: 'sin overflow');
          _esperaDelEstado(tester, estado);
          for (final f in _tocablesDelEstado(estado)) {
            await tester.ensureVisible(f);
            await tester.pump();
            expect(f.hitTestable(), findsOneWidget, reason: '$f se puede tocar a $nombre');
            final caja = tester.getRect(f);
            expect(caja.height, greaterThanOrEqualTo(48), reason: 'alto de toque de $f');
            expect(caja.bottom, lessThanOrEqualTo(alto + 0.5));
          }
          expect(tester.takeException(), isNull);
          await capturar691(tester, '${estado.name}_$nombre');
        });
      }
    }
  });

  group('Textos literales del canvas', () {
    testWidgets('16G·03: título y detalle sin Drive tal cual (y no el de con Drive)', (
      tester,
    ) async {
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      expect(find.text(_filaTitulo), findsOneWidget);
      expect(find.text(_detalleSinDrive), findsOneWidget);
      expect(find.text(_detalleConDrive), findsNothing);
    });

    testWidgets('16G·02: título, cuerpo con la cuenta y los dos botones tal cual', (tester) async {
      await abrirApp(tester, arnes);
      await armarEstado(tester, arnes, Estado16G.hoja02);
      expect(find.text(_tituloHoja), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('configuracion_hoja_recuperar_texto'))).data,
        _textoHoja,
      );
      expect(find.text('Empezar'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);
    });
  });

  group('Lector de pantalla', () {
    testWidgets('16G·01 y 16G·03: la fila se anuncia con su detalle y se puede activar', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      var nodo = tester.getSemantics(filaRecuperarRespaldo);
      expect(nodo.label, contains(_filaTitulo));
      expect(nodo.label, contains(_detalleSinDrive));
      expect(nodo, isSemantics(hasTapAction: true, isEnabled: true, hasEnabledState: true));

      await conectarDriveDeLaApp(tester);
      await asentar(tester);
      nodo = tester.getSemantics(filaRecuperarRespaldo);
      expect(nodo.label, contains(_detalleConDrive));
      expect(nodo, isSemantics(hasTapAction: true, isEnabled: true, hasEnabledState: true));
      semantica.dispose();
    });

    testWidgets('16G·02: el título es encabezado y los dos botones tienen nombre y acción', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await abrirApp(tester, arnes);
      await armarEstado(tester, arnes, Estado16G.hoja02);
      expect(
        tester.getSemantics(find.text(_tituloHoja)),
        isSemantics(label: _tituloHoja, isHeader: true),
      );
      for (final (boton, rotulo) in [
        (hojaRecuperarEmpezar, 'Empezar'),
        (hojaRecuperarAhoraNo, 'Ahora no'),
      ]) {
        final nodo = tester.getSemantics(boton);
        expect(nodo.label, rotulo);
        expect(nodo, isSemantics(hasTapAction: true, isButton: true, isEnabled: true));
      }
      semantica.dispose();
    });

    testWidgets('el aviso de «no pudimos ver tu Drive» se anuncia solo (región viva)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await abrirApp(tester, arnes);
      await armarEstado(tester, arnes, Estado16G.errorDrive);
      final nodo = tester.getSemantics(
        find.text('No pudimos ver el estado de tu Drive. Probá de nuevo en unos minutos.'),
      );
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });
  });

  group('Casos límite', () {
    testWidgets('tocar fuera de la hoja la cierra: no reinicia y la fila vuelve a abrirla', (
      tester,
    ) async {
      await abrirApp(tester, arnes);
      await armarEstado(tester, arnes, Estado16G.hoja02);

      await tester.tapAt(const Offset(195, 20));
      await asentar(tester);

      expect(hojaRecuperarRespaldo, findsNothing);
      expect(asistente, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);
      await tocar(tester, filaRecuperarRespaldo);
      expect(hojaRecuperarRespaldo, findsOneWidget);
    });

    testWidgets('salir de Configuración mientras se lee el Drive: al terminar no abre nada', (
      tester,
    ) async {
      await abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      final compuerta = Completer<void>();
      arnes.drive.almacen.compuertaLeer = compuerta;
      raiz(tester).invalidate(estadoRespaldoDriveProvider);
      await irAConfiguracion(tester);

      await tester.tap(filaRecuperarRespaldo);
      await asentar(tester);
      await tester.ensureVisible(atrasConfiguracion);
      await tester.tap(atrasConfiguracion);
      await asentar(tester);
      expect(configuracion, findsNothing);

      arnes.drive.almacen.compuertaLeer = null;
      compuerta.complete();
      await asentar(tester);

      expect(tester.takeException(), isNull);
      expect(hojaRecuperarRespaldo, findsNothing);
      expect(asistente, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);
    });

    testWidgets('falla a mitad (no se puede quitar la marca): avisa, no reinicia y la fila se '
        'puede volver a tocar', (tester) async {
      await abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await irAConfiguracion(tester);
      arnes.resuelta.errorAlDesmarcar = StateError('disco');

      await tocar(tester, filaRecuperarRespaldo);
      await tocar(tester, hojaRecuperarEmpezar);

      expect(asistente, findsNothing);
      expect(avisoNo, findsOneWidget);
      expect(find.textContaining('Probá de nuevo'), findsOneWidget);
      expect(tester.widget<ListTile>(filaRecuperarRespaldo).enabled, isTrue);

      arnes.resuelta.errorAlDesmarcar = null;
      await tocar(tester, filaRecuperarRespaldo);
      expect(hojaRecuperarRespaldo, findsOneWidget, reason: 'la guarda se soltó');
      await tocar(tester, hojaRecuperarEmpezar);
      expect(asistente, findsOneWidget);
    });

    testWidgets('falla a mitad (no se puede mirar la base): avisa y no reinicia', (tester) async {
      await abrirApp(tester, arnes);
      await conectarDriveDeLaApp(tester);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      arnes.lector.errorAlMirar = StateError('base');

      await tocar(tester, hojaRecuperarEmpezar);

      expect(asistente, findsNothing);
      expect(arnes.resuelta.desmarcas, 0, reason: 'no se quita la marca sobre algo que no se miró');
      expect(avisoNo, findsOneWidget);
    });

    testWidgets('16G·03: Google falla (no cancela): la hoja queda con el error y «Reintentar»; '
        'al reintentar sigue al asistente', (tester) async {
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);
      await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      await tocar(tester, conectarConGoogle);

      expect(hojaConectar, findsOneWidget, reason: 'la hoja sigue abierta con el error');
      expect(asistente, findsNothing);
      expect(arnes.resuelta.desmarcas, 0);

      arnes.drive.google.errorAlConectar = null;
      await tocar(tester, conectarConGoogle);
      await asentar(tester);
      expect(asistente, findsOneWidget);
    });

    testWidgets('16G·03 sin conexión del teléfono: la hoja dice qué necesita y no conecta', (
      tester,
    ) async {
      final telefono = await abrirApp(tester, arnes);
      await irAConfiguracion(tester);
      telefono.conexion.cambiarA(TipoConexion.sinConexion);
      await asentar(tester);

      await tocar(tester, filaRecuperarRespaldo);

      expect(hojaConectar, findsOneWidget);
      expect(find.text('Necesitás conexión para conectar Google Drive.'), findsOneWidget);
      expect(arnes.drive.google.conexiones, 0);
      expect(asistente, findsNothing);

      telefono.conexion.cambiarA(TipoConexion.wifi);
      await asentar(tester);
      await tocar(tester, conectarConGoogle);
      await asentar(tester);
      expect(asistente, findsOneWidget);
    });

    testWidgets('la hoja con datos que se cargan: la fila queda apagada y no reabre la hoja', (
      tester,
    ) async {
      await abrirApp(tester, arnes);
      await armarEstado(tester, arnes, Estado16G.hayDatos);

      await tester.tap(filaRecuperarRespaldo, warnIfMissed: false);
      await asentar(tester);

      expect(hojaRecuperarRespaldo, findsNothing);
      expect(hojaConectar, findsNothing);
      expect(asistente, findsNothing);
    });

    testWidgets('reentrar a Configuración después de un aviso: la fila sigue sin trabarse', (
      tester,
    ) async {
      await abrirApp(tester, arnes);
      await armarEstado(tester, arnes, Estado16G.errorDrive);
      await tester.ensureVisible(atrasConfiguracion);
      await tester.tap(atrasConfiguracion);
      await asentar(tester);

      arnes.drive.almacen.alLeer = false;
      raiz(tester).invalidate(estadoRespaldoDriveProvider);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);

      expect(hojaRecuperarRespaldo, findsOneWidget);
    });
  });

  group('Privacidad', () {
    test('el correo de la cuenta no sale en el toString de la hoja', () {
      const hoja = HojaRecuperarRespaldo(cuentaDrive: 'ana.gomez@gmail.com');
      expect(hoja.toString(), isNot(contains('ana.gomez')));
      expect(hoja.toStringShort(), isNot(contains('ana.gomez')));
    });
  });
}
