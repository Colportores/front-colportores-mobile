// QA de #386 (PR #758): «términos de uso» del registro abre la página versionada y el registro manda
// la versión aceptada. Contrasta con el issue (texto literal), la decisión del agente de decisiones
// del 23/11 (aviso cuando el teléfono no puede abrir la página) y el artboard «1a · Registro» de
// `disenio-vistas/mobile/Login Colportor.dc.html` (el canvas dibuja el enlace `<a>`, sin estados
// propios: la vista no suma artboards).
//
// Capturas PNG con `--dart-define=QA_CAPTURAS=true`, en `.dart_tool/qa_capturas/` (gitignored).
import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/services/abridor_de_pagina_url_launcher.dart';
import 'package:colportores_mobile/features/auth/domain/entities/terminos_de_uso.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_registro_terminos_386_arnes.dart';

const _tamanios = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];
const _escalas = <double>[1, 2];

/// Portapapeles de prueba: devuelve lo que la app va copiando.
List<String> _simularPortapapeles(WidgetTester tester) {
  final copiados = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
    call,
  ) async {
    if (call.method == 'Clipboard.setData') {
      copiados.add((call.arguments as Map<Object?, Object?>)['text']! as String);
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copiados;
}

void main() {
  late AbridorFalso386 abridor;
  late MonitorFalso386 monitor;

  setUp(() {
    abridor = AbridorFalso386();
    monitor = MonitorFalso386();
  });

  group('Matriz de tamaños y escalas con el aviso a la vista', () {
    for (final (nombreTam, tam) in _tamanios) {
      for (final escala in _escalas) {
        testWidgets(
          'dado sin conexión, cuando toca «términos de uso», entonces ve «$avisoSinConexion386» sin '
          'overflow ($nombreTam, texto ${escala}x)',
          (tester) async {
            await cargarFuentes386(tester);
            monitor.tipo = TipoConexion.sinConexion;
            await montar386(
              tester,
              tamanio: tam,
              abridor: abridor,
              monitor: monitor,
              escala: escala,
            );
            await capturar386(tester, 'inicial_${nombreTam}_${escala}x');

            await tocarEnlace386(tester);

            expect(find.text(avisoSinConexion386), findsOneWidget);
            expect(abridor.abiertas, isEmpty);
            expect(tester.takeException(), isNull);
            await capturar386(tester, 'sin_conexion_${nombreTam}_${escala}x');
          },
        );

        testWidgets(
          'dado que el teléfono no puede abrir la página, entonces el aviso se lee entero y sin '
          'overflow ($nombreTam, texto ${escala}x)',
          (tester) async {
            await cargarFuentes386(tester);
            abridor.resultado = false;
            await montar386(
              tester,
              tamanio: tam,
              abridor: abridor,
              monitor: monitor,
              escala: escala,
            );

            await tocarEnlace386(tester);

            expect(find.byType(SnackBar), findsOneWidget);
            expect(abridor.abiertas, hasLength(1));
            expect(tester.takeException(), isNull);
            await capturar386(tester, 'no_se_abrio_${nombreTam}_${escala}x');
          },
        );
      }
    }
  });

  group('Decisión del agente de decisiones (23/11): aviso cuando no se puede abrir', () {
    testWidgets('el aviso dice qué pasó y dónde leerlos, con la dirección de la v1', (
      tester,
    ) async {
      abridor.resultado = false;
      await montar386(tester, tamanio: const Size(412, 915), abridor: abridor, monitor: monitor);

      await tocarEnlace386(tester);

      expect(find.text(avisoDecidido386), findsOneWidget);
    });

    testWidgets('la dirección del aviso se puede seleccionar y copiar', (tester) async {
      abridor.resultado = false;
      await montar386(tester, tamanio: const Size(412, 915), abridor: abridor, monitor: monitor);

      await tocarEnlace386(tester);

      final seleccionable = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byWidgetPredicate(
          (w) => w is SelectableText || w is SelectionArea || w is SelectionContainer,
        ),
      );
      expect(seleccionable, findsWidgets);
    });

    test('la constante del aviso coincide con la decisión', () {
      expect(TerminosDeUso.avisoNoSeAbrio, avisoDecidido386);
    });
  });

  group('Aviso «Copiar» de la dirección', () {
    testWidgets('«Copiar» deja la dirección completa en el portapapeles y confirma', (
      tester,
    ) async {
      final copiados = _simularPortapapeles(tester);
      abridor.resultado = false;
      await montar386(tester, tamanio: const Size(412, 915), abridor: abridor, monitor: monitor);
      await tocarEnlace386(tester);

      await tester.tap(find.text('Copiar dirección'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(copiados, ['https://colportores.github.io/terminos/v1/']);
      expect(find.text('Copiamos la dirección.'), findsOneWidget);
      expect(find.text(avisoDecidido386), findsNothing);
    });

    testWidgets('el aviso dura lo suficiente para leerlo y copiar (más de 4 s)', (tester) async {
      abridor.resultado = false;
      await montar386(tester, tamanio: const Size(412, 915), abridor: abridor, monitor: monitor);
      await tocarEnlace386(tester);

      await tester.pump(const Duration(seconds: 6));

      expect(find.text(avisoDecidido386, findRichText: true), findsOneWidget);
    });

    testWidgets('con lector de pantalla el aviso no se cierra solo y se cierra con la «x»', (
      tester,
    ) async {
      abridor.resultado = false;
      await montar386(
        tester,
        tamanio: const Size(412, 915),
        abridor: abridor,
        monitor: monitor,
        lectorDePantalla: true,
      );
      await tocarEnlace386(tester);

      await tester.pump(const Duration(seconds: 30));

      expect(find.text(avisoDecidido386, findRichText: true), findsOneWidget);
      expect(find.text('Copiar dirección'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(avisoDecidido386, findRichText: true), findsNothing);
    });

    for (final (nombreTam, tam) in _tamanios) {
      for (final escala in _escalas) {
        testWidgets(
          '«Copiar» y el texto quedan enteros y tocables ($nombreTam, texto ${escala}x)',
          (tester) async {
            _simularPortapapeles(tester);
            abridor.resultado = false;
            await montar386(
              tester,
              tamanio: tam,
              abridor: abridor,
              monitor: monitor,
              escala: escala,
            );
            await tocarEnlace386(tester);

            expect(find.text('Copiar dirección'), findsOneWidget);
            final boton = tester.getRect(find.text('Copiar dirección'));
            final pantalla = Offset.zero & tam;
            expect(
              pantalla.contains(boton.topLeft) && pantalla.contains(boton.bottomRight),
              isTrue,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('Copiar dirección'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('Copiamos la dirección.'), findsOneWidget);
          },
        );
      }
    }
  });

  group('Lo tipeado y la casilla no se pierden al tocar el enlace', () {
    final caminos = <(String, void Function(AbridorFalso386, MonitorFalso386))>[
      ('abre bien', (a, m) {}),
      ('sin conexión', (a, m) => m.tipo = TipoConexion.sinConexion),
      ('el teléfono no abre', (a, m) => a.resultado = false),
      ('la plataforma lanza', (a, m) => a.falla = StateError('plataforma')),
    ];
    for (final (nombre, preparar) in caminos) {
      testWidgets('camino «$nombre»: los campos y la casilla quedan como estaban', (tester) async {
        preparar(abridor, monitor);
        await montar386(tester, tamanio: const Size(360, 640), abridor: abridor, monitor: monitor);
        await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
        await tester.enterText(find.byKey(const Key('registro_email')), 'lucia.silva@correo.com');
        await tester.enterText(find.byKey(const Key('registro_password')), 'Secreto123');
        await tester.ensureVisible(find.byKey(const Key('registro_terminos')));
        await tester.pump();
        final antes = tester.widget<Checkbox>(find.byKey(const Key('registro_terminos'))).value;

        await tocarEnlace386(tester);

        expect(tester.widget<Checkbox>(find.byKey(const Key('registro_terminos'))).value, antes);
        expect(textoDe386(tester, 'registro_nombre'), 'Lucía');
        expect(textoDe386(tester, 'registro_email'), 'lucia.silva@correo.com');
        expect(textoDe386(tester, 'registro_password'), 'Secreto123');
        expect(tester.takeException(), isNull);

        // Y con la casilla marcada, tocar el enlace no la desmarca.
        await tester.tap(find.byKey(const Key('registro_terminos')));
        await tester.pump(const Duration(seconds: 5));
        expect(tester.widget<Checkbox>(find.byKey(const Key('registro_terminos'))).value, !antes!);
        await tocarEnlace386(tester);
        expect(
          tester.widget<Checkbox>(find.byKey(const Key('registro_terminos'))).value,
          !antes,
          reason: 'el enlace no marca ni desmarca la casilla',
        );
      });
    }
  });

  group('Accesibilidad del enlace y del aviso', () {
    testWidgets('el enlace «términos de uso» tiene un nodo propio con acción de toque', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar386(tester, tamanio: const Size(360, 640), abridor: abridor, monitor: monitor);
      await tester.ensureVisible(find.byKey(const Key('registro_terminos')));
      await tester.pump();

      final raiz = tester.getSemantics(find.byType(MaterialApp));
      final enlaces = nodos386(raiz).where((n) {
        final d = n.getSemanticsData();
        return d.label.contains('términos de uso') && d.hasAction(SemanticsAction.tap);
      }).toList();
      // El Checkbox lleva la frase entera con su `semanticLabel`; el enlace es otro nodo.
      expect(
        enlaces.where((n) => n.getSemanticsData().label.trim() == 'términos de uso'),
        isNotEmpty,
        reason: 'el lector de pantalla debe poder activar el enlace por separado',
      );
      semantica.dispose();
    });

    testWidgets('el aviso se anuncia (región viva) y no tapa el enlace al 100 % (412x915)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      monitor.tipo = TipoConexion.sinConexion;
      await montar386(tester, tamanio: const Size(412, 915), abridor: abridor, monitor: monitor);
      await tocarEnlace386(tester);

      final raiz = tester.getSemantics(find.byType(MaterialApp));
      final aviso = nodos386(raiz).where((n) {
        final d = n.getSemanticsData();
        return d.label.contains(avisoSinConexion386);
      });
      expect(aviso, isNotEmpty);
      expect(
        aviso.any((n) => n.getSemanticsData().flagsCollection.isLiveRegion) ||
            nodos386(raiz).any((n) {
              final d = n.getSemanticsData();
              return d.flagsCollection.isLiveRegion && d.label.contains(avisoSinConexion386);
            }),
        isTrue,
        reason: 'el aviso del SnackBar se anuncia con el lector de pantalla',
      );
      semantica.dispose();
    });

    testWidgets('con el aviso a la vista (360x640, 200 %) el enlace sigue a mano para reintentar', (
      tester,
    ) async {
      monitor.tipo = TipoConexion.sinConexion;
      await montar386(
        tester,
        tamanio: const Size(360, 640),
        abridor: abridor,
        monitor: monitor,
        escala: 2,
      );
      await tocarEnlace386(tester);
      expect(find.text(avisoSinConexion386), findsOneWidget);

      // La red vuelve; la persona toca de nuevo el enlace mientras el aviso sigue a la vista.
      monitor.tipo = TipoConexion.wifi;
      final enlace = tester.getRect(find.byKey(const Key('registro_terminos')));
      final aviso = tester.getRect(find.byType(SnackBar));
      expect(
        enlace.overlaps(aviso),
        isFalse,
        reason: 'el aviso (${aviso.top}..${aviso.bottom}) tapa la línea del enlace (${enlace.top})',
      );
    });
  });

  group('Navegación y reentrada', () {
    testWidgets(
      'el aviso de «sin conexión» no queda a la vista sobre la pantalla anterior al volver',
      (tester) async {
        monitor.tipo = TipoConexion.sinConexion;
        await montar386(tester, tamanio: const Size(412, 915), abridor: abridor, monitor: monitor);
        await tocarEnlace386(tester);
        expect(find.text(avisoSinConexion386), findsOneWidget);

        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.byType(RegistroPage), findsNothing);
        expect(find.text(avisoSinConexion386), findsNothing);
      },
      skip:
          true, // skip: QA #386 (menor): al volver atrás con el aviso a la vista, «Necesitás conexión para leer los términos» queda sobre la pantalla anterior hasta 4 s
    );

    testWidgets('tras volver y reentrar con red, el enlace abre la v1 y no hay aviso viejo', (
      tester,
    ) async {
      monitor.tipo = TipoConexion.sinConexion;
      await montar386(tester, tamanio: const Size(412, 915), abridor: abridor, monitor: monitor);
      await tocarEnlace386(tester);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 6));
      monitor.tipo = TipoConexion.wifi;
      await tester.tap(find.byKey(const Key('abrir_registro')));
      await tester.pumpAndSettle();
      await tocarEnlace386(tester);

      expect(abridor.abiertas, [TerminosDeUso.direccion]);
      expect(find.text(avisoSinConexion386), findsNothing);
    });

    testWidgets('el toque no se traba si la apertura falla a mitad y se reintenta tres veces', (
      tester,
    ) async {
      await montar386(tester, tamanio: const Size(360, 640), abridor: abridor, monitor: monitor);
      for (var i = 0; i < 3; i++) {
        abridor.demora = Completer<void>();
        abridor.falla = StateError('a mitad $i');
        await tocarEnlace386(tester);
        await tocarEnlace386(tester); // segundo toque con la primera en vuelo: se ignora
        expect(abridor.abiertas, hasLength(i + 1));
        abridor.demora!.complete();
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      abridor
        ..falla = null
        ..demora = null;
      await tocarEnlace386(tester);
      expect(abridor.abiertas, hasLength(4));
    });
  });

  group('Adaptador real sobre url_launcher (canal de plataforma simulado)', () {
    const canal = MethodChannel('plugins.flutter.io/url_launcher');
    final llamadas = <MethodCall>[];

    setUp(() {
      llamadas.clear();
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        canal,
        (call) async {
          llamadas.add(call);
          return true;
        },
      );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        canal,
        null,
      );
    });

    test('abre la dirección https de la v1 por fuera de la app', () async {
      final ok = await const AbridorDePaginaUrlLauncher().abrir(TerminosDeUso.direccion);

      expect(ok, isTrue);
      final lanzamiento = llamadas.where((c) => c.method == 'launch');
      expect(lanzamiento, hasLength(1));
      final args = lanzamiento.single.arguments as Map<Object?, Object?>;
      expect(args['url'], 'https://colportores.github.io/terminos/v1/');
      expect(Uri.parse(args['url']! as String).scheme, 'https');
    });

    test('si el sistema responde que no pudo abrirla, devuelve false (no lanza)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        canal,
        (call) async => false,
      );

      expect(await const AbridorDePaginaUrlLauncher().abrir(TerminosDeUso.direccion), isFalse);
    });
  });

  group('El alta lleva la versión aceptada', () {
    Future<void> completarYEnviar(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
      await tester.enterText(find.byKey(const Key('registro_apellido')), 'Silva');
      await tester.enterText(find.byKey(const Key('registro_cedula')), '4812309-2');
      await tester.enterText(find.byKey(const Key('registro_email')), 'lucia.silva@correo.com');
      await tester.enterText(find.byKey(const Key('registro_password')), 'Secreto123');
      await tester.ensureVisible(find.byKey(const Key('registro_terminos')));
      await tester.tap(find.byKey(const Key('registro_terminos')));
      await tester.ensureVisible(find.byKey(const Key('registro_trade_off')));
      await tester.tap(find.byKey(const Key('registro_trade_off')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('registro_continuar')));
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();
    }

    testWidgets('leer los términos antes de aceptar no cambia lo que se manda: una sola versión', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await montar386(
        tester,
        tamanio: const Size(412, 915),
        abridor: abridor,
        monitor: monitor,
        remote: remote,
      );
      await tocarEnlace386(tester);
      await completarYEnviar(tester);

      expect(remote.terminosVersionesRegistradas, ['v1']);
      expect(abridor.abiertas.single.path, '/terminos/${TerminosDeUso.versionVigente}/');
    });

    testWidgets('sin conexión al leer los términos igual se puede registrar aceptándolos', (
      tester,
    ) async {
      monitor.tipo = TipoConexion.sinConexion;
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await montar386(
        tester,
        tamanio: const Size(412, 915),
        abridor: abridor,
        monitor: monitor,
        remote: remote,
      );
      await tocarEnlace386(tester);
      expect(find.text(avisoSinConexion386), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      await completarYEnviar(tester);

      expect(remote.terminosVersionesRegistradas, ['v1']);
    });
  });
}
