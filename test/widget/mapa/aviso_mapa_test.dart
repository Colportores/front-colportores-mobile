// Los avisos del mapa de la vista 06 (artboards 06C·05, 06C·06 y 06C·07) y «No pudimos cargar el
// mapa de esta ciudad» (#190), con el descargador de paquetes REAL sobre puertos falsos
// (`mapa_descargas_arnes.dart`): ni el bucket `mapas` ni la red ni el disco son reales.
//
// Medidas con las fuentes reales del proyecto (con Ahem cada letra es un cuadrado).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/services/resolutores_mapa.dart'
    show FuenteTiles;
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_base_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/mapa_descargas_arnes.dart';
import '../../helpers/tiles_falsos.dart';

Finder get _tarjetaSinConexion => find.byKey(ClavesAvisoMapa.sinConexion);
Finder get _pildora => find.byKey(ClavesAvisoMapa.pildora);
Finder get _tarjetaDatos => find.byKey(ClavesAvisoMapa.datosMoviles);
Finder get _tarjetaNoCarga => find.byKey(ClavesAvisoMapa.noCarga);
Finder get _descargar => find.widgetWithText(FilledButton, 'Descargar mapa');
Finder get _descargarConPeso => find.widgetWithText(FilledButton, 'Descargar mapa · 1 MB');
Finder get _activarDatos => find.widgetWithText(OutlinedButton, 'Activar datos');
Finder get _ahoraNo => find.widgetWithText(TextButton, 'Ahora no');
Finder get _reintentar => find.widgetWithText(FilledButton, 'Reintentar');
Finder get _minimizar => find.byTooltip('Minimizar aviso');

/// Lo que dice el aviso entre tocar «Descargar mapa» y tener el mapa (decisión del 06/10, P1).
Finder get _enCola => find.text('Se descarga sola cuando vuelva la señal.');
Finder get _bajando => find.text('Descargando el mapa…');

/// [texto] dentro de [lugar] (una tarjeta o un aviso pasajero).
Finder _en(Finder lugar, Finder texto) => find.descendant(of: lugar, matching: texto);

/// Un disco que no escribe hasta que el test lo deja: la descarga queda «bajando» el tiempo que haga
/// falta. Si el test no la suelta, el cierre lo hace por él (el descargador no queda esperando).
Completer<void> _retenerElDisco(ArnesMapa arnes) {
  final compuerta = Completer<void>();
  arnes.archivos.compuerta = compuerta.future;
  addTearDown(() {
    if (!compuerta.isCompleted) compuerta.complete();
  });
  return compuerta;
}

/// El rectángulo decorado de una tarjeta (el que tiene el fondo, el borde y las esquinas).
Finder _fondoDe(Finder tarjeta) =>
    find.descendant(of: tarjeta, matching: find.byType(Container)).first;

BoxDecoration _decoracion(WidgetTester tester, Finder tarjeta) =>
    tester.widget<Container>(_fondoDe(tarjeta)).decoration! as BoxDecoration;

bool _habilitado(WidgetTester tester, Finder boton) {
  final widget = tester.widget(boton);
  return switch (widget) {
    FilledButton(:final onPressed) => onPressed != null,
    OutlinedButton(:final onPressed) => onPressed != null,
    TextButton(:final onPressed) => onPressed != null,
    _ => throw StateError('no es un botón: $widget'),
  };
}

void _ningunAviso() {
  expect(_tarjetaSinConexion, findsNothing);
  expect(_pildora, findsNothing);
  expect(_tarjetaDatos, findsNothing);
  expect(_tarjetaNoCarga, findsNothing);
  expect(find.textContaining('Sin conexión'), findsNothing);
}

/// El mapa de fondo que están usando las vistas ahora, para verificar que cada aviso va con el mapa
/// que dice.
FuenteTiles _fuente(WidgetTester tester, [AmbitoTrabajo ambito = ambitoMontevideo]) {
  final contenedor = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
  return contenedor.read(fuenteMapaProvider(ambito)).tipo;
}

void main() {
  setUpAll(cargarFuentesReales);

  group('06C·05 · Sin conexión (el aviso rojo)', () {
    testWidgets('los textos son los del canvas, letra por letra', (tester) async {
      await montarAviso(tester, conexion: TipoConexion.sinConexion);

      expect(find.text('Sin conexión a internet'), findsOneWidget);
      expect(
        find.text(
          'Tus ubicaciones se siguen viendo. Para ver las calles, activá tus datos móviles o '
          'descargá el mapa.',
        ),
        findsOneWidget,
      );
      expect(find.text('Descargar mapa'), findsOneWidget);
      expect(find.text('Activar datos'), findsOneWidget);
      expect(find.byTooltip('Minimizar aviso'), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
      // El mapa es el color liso, sin gris: lo dice el catálogo, no un texto de «escala de grises».
      expect(find.textContaining('grises'), findsNothing);
      expect(find.textContaining('Sin tiles'), findsNothing);
      expect(_fuente(tester), FuenteTiles.sinTiles);
    });

    testWidgets('geometría del canvas a 390×844: arriba 8, a 14 de los costados, esquinas de 16', (
      tester,
    ) async {
      await montarAviso(tester, conexion: TipoConexion.sinConexion);

      final tarjeta = tester.getRect(_fondoDe(_tarjetaSinConexion));
      expect(tarjeta.left, 14);
      expect(tarjeta.right, 390 - 14);
      expect(tarjeta.top, 8);

      final decoracion = _decoracion(tester, _tarjetaSinConexion);
      expect(decoracion.color, const Color(0xFFA8312A));
      expect(decoracion.borderRadius, BorderRadius.circular(16));

      // Padding de 14 arriba y 16 a los costados: la insignia de 26 y el título a 12 de ella.
      final insignia = tester.getRect(
        find.descendant(of: _tarjetaSinConexion, matching: find.text('!')).first,
      );
      expect(insignia.center.dx, closeTo(tarjeta.left + 16 + 13, 1));
      final titulo = tester.getTopLeft(find.text('Sin conexión a internet'));
      expect(titulo.dx, tarjeta.left + 16 + 26 + 12);
      expect(titulo.dy, tarjeta.top + 14);

      final titulos = tester.widget<Text>(find.text('Sin conexión a internet')).style!;
      expect(titulos.fontSize, 15.5);
      expect(titulos.fontWeight, FontWeight.w700);
      expect(titulos.color, Colors.white);
      final cuerpo = tester
          .widget<Text>(find.textContaining('Tus ubicaciones se siguen viendo'))
          .style!;
      expect(cuerpo.fontSize, 13.5);
      expect(cuerpo.height, 1.45);

      // La ✕: 48×48 de toque (el canvas dibuja 40: el piso de accesibilidad son 48), pegada al borde.
      final equis = tester.getRect(find.byType(IconButton));
      expect(equis.size, const Size(48, 48));
      expect(equis.right, lessThanOrEqualTo(tarjeta.right - 16 + 1));

      // Los dos botones, a todo el ancho y de 48 como mínimo.
      for (final boton in [_descargar, _activarDatos]) {
        final rect = tester.getRect(boton);
        expect(rect.height, greaterThanOrEqualTo(48), reason: '$boton');
        expect(rect.left, tarjeta.left + 16);
        expect(rect.right, tarjeta.right - 16);
      }
      final descargar = tester.widget<FilledButton>(_descargar);
      expect(descargar.style!.backgroundColor!.resolve({}), Colors.white);
      expect(descargar.style!.foregroundColor!.resolve({}), const Color(0xFFA8312A));
      final activar = tester.widget<OutlinedButton>(_activarDatos);
      expect(activar.style!.side!.resolve({}), const BorderSide(color: Colors.white, width: 1.5));
      expect(activar.style!.foregroundColor!.resolve({}), Colors.white);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets('a 360×640 con el texto al ${escala}x no desborda y se llega a los dos botones', (
        tester,
      ) async {
        await montarAviso(
          tester,
          conexion: TipoConexion.sinConexion,
          tamano: const Size(360, 640),
          escala: escala,
        );

        expect(tester.takeException(), isNull);
        final tarjeta = tester.getRect(_fondoDe(_tarjetaSinConexion));
        expect(tarjeta.left, 14);
        expect(tarjeta.right, 360 - 14);
        // Nunca pasa del 80 % de la pantalla: si el texto es grande, la tarjeta se desplaza.
        final visible = tester.getRect(
          find.descendant(
            of: find.byType(AvisoMapaConectado),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(visible.bottom, lessThanOrEqualTo(8 + 640 * .8 + 1));
        for (final boton in [_descargar, _activarDatos]) {
          await tester.ensureVisible(boton);
          await tester.pump();
          final rect = tester.getRect(boton);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(640));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('«Minimizar aviso» deja solo la píldora; el aviso rojo no vuelve en la sesión', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        catalogo: [paqueteMontevideo],
      );
      expect(_tarjetaSinConexion, findsOneWidget);
      expect(_pildora, findsNothing);

      await tocarAviso(tester, _minimizar);

      expect(_tarjetaSinConexion, findsNothing);
      expect(_pildora, findsOneWidget);

      // Volver atrás y reentrar a la vista: sigue la píldora, el aviso rojo ya salió esta sesión.
      await salirYReentrarAviso(tester, montaje);
      expect(_tarjetaSinConexion, findsNothing);
      expect(_pildora, findsOneWidget);

      // Vuelve la conexión y se va otra vez: la píldora, no el aviso rojo de nuevo.
      montaje.arnes.conectividad.cambiarA(TipoConexion.wifi);
      await asentarAviso(tester);
      _ningunAviso();
      montaje.arnes.conectividad.cambiarA(TipoConexion.sinConexion);
      await asentarAviso(tester);
      expect(_tarjetaSinConexion, findsNothing);
      expect(_pildora, findsOneWidget);
    });

    testWidgets(
      '«Descargar mapa» sin conexión queda en cola y arranca con la primera conexión, aun con datos móviles',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.sinConexion,
          catalogo: [paqueteMontevideo],
        );
        final arnes = montaje.arnes;

        await tocarAviso(tester, _descargar);
        expect(arnes.servidor.pedidos, isEmpty, reason: 'sin conexión no se baja nada');
        expect(arnes.montevideoDescargado, isFalse);
        // El pedido no dice que falló: dice que se descarga sola, y el botón espera.
        expect(find.textContaining('Espacio'), findsNothing);
        expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
        expect(_habilitado(tester, _descargar), isFalse);

        // Vuelve la señal, y es de datos móviles: la descarga que pidió el colportor arranca igual.
        arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await asentarAviso(tester);

        expect(arnes.servidor.pedidos, isNotEmpty);
        expect(arnes.montevideoDescargado, isTrue);
        expect(arnes.archivos.contenido.keys.where((r) => r.endsWith('.pmtiles')), hasLength(1));
        // Con el mapa descargado ya no hay nada que avisar.
        _ningunAviso();
        expect(_fuente(tester), FuenteTiles.pmtilesOffline);
      },
    );

    testWidgets('el pedido sobrevive a salir y volver a entrar, y dos toques no encolan dos', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        catalogo: [paqueteMontevideo],
      );
      final arnes = montaje.arnes;

      await tester.tap(_descargar);
      await tester.tap(_descargar, warnIfMissed: false);
      await asentarAviso(tester);
      await salirYReentrarAviso(tester, montaje);
      // Al volver sigue en cola: lo dice y el botón sigue esperando.
      expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
      expect(_habilitado(tester, _descargar), isFalse);
      await tester.tap(_descargar, warnIfMissed: false);
      await asentarAviso(tester);
      expect(arnes.servidor.pedidos, isEmpty);

      arnes.conectividad.cambiarA(TipoConexion.wifi);
      await asentarAviso(tester);

      // Una sola descarga: un solo pedido al servidor (el paquete cabe en un pedazo).
      expect(arnes.servidor.pedidos, hasLength(1));
      expect(arnes.montevideoDescargado, isTrue);
    });

    testWidgets(
      'si el catálogo ya se conocía, «Descargar mapa» encola el paquete y no lo encola dos veces',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.datosMoviles,
          catalogo: [paqueteMontevideo],
        );
        final arnes = montaje.arnes;
        // Con datos móviles se ve la tarjeta de 06C·07 y el catálogo ya está leído.
        expect(_tarjetaDatos, findsOneWidget);

        arnes.conectividad.cambiarA(TipoConexion.sinConexion);
        await asentarAviso(tester);
        expect(_tarjetaSinConexion, findsOneWidget);

        await tocarAviso(tester, _descargar);
        await tester.tap(_descargar, warnIfMissed: false);
        await asentarAviso(tester);
        final estado = arnes.descargador.estadoDe('ciudad-montevideo');
        expect(estado, isA<DescargaPausada>().having((e) => e.sigueSola, 'sigueSola', true));
        expect(arnes.servidor.pedidos, isEmpty);
        expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
        expect(_habilitado(tester, _descargar), isFalse);

        arnes.conectividad.cambiarA(TipoConexion.wifi);
        await asentarAviso(tester);
        expect(arnes.servidor.pedidos, hasLength(1));
        expect(arnes.montevideoDescargado, isTrue);
      },
    );

    testWidgets(
      'sin saber en qué ciudad está, el pedido dice qué falta y el botón sigue habilitado',
      (tester) async {
        await montarAviso(
          tester,
          conexion: TipoConexion.sinConexion,
          ambito: const AmbitoTrabajo(),
        );
        // «Sin conexión» se sabe sin el ámbito.
        expect(_tarjetaSinConexion, findsOneWidget);

        await tocarAviso(tester, _descargar);

        expect(find.text(const FailureCiudadRequerida().mensaje), findsOneWidget);
        expect(_habilitado(tester, _descargar), isTrue);
        // Y se puede volver a intentar sin que quede nada trabado.
        await tocarAviso(tester, _descargar);
        expect(find.text(const FailureCiudadRequerida().mensaje), findsOneWidget);
        expect(_habilitado(tester, _descargar), isTrue);
      },
    );

    group('«Activar datos»', () {
      testWidgets('abre los ajustes de red del teléfono y no avisa de nada si los abrió', (
        tester,
      ) async {
        final montaje = await montarAviso(tester, conexion: TipoConexion.sinConexion);

        await tocarAviso(tester, _activarDatos);

        expect(montaje.arnes.ajustes.aperturasDeRed, 1);
        expect(find.byType(SnackBar), findsNothing);
        expect(_habilitado(tester, _activarDatos), isTrue);
      });

      testWidgets('un segundo toque mientras abre no abre otra vez, y vuelve a habilitarse', (
        tester,
      ) async {
        final montaje = await montarAviso(tester, conexion: TipoConexion.sinConexion);
        final espera = Completer<void>();
        montaje.arnes.ajustes.espera = espera;

        await tester.tap(_activarDatos);
        await tester.pump();
        await tester.tap(_activarDatos, warnIfMissed: false);
        await tester.pump();
        expect(montaje.arnes.ajustes.aperturasDeRed, 1);
        expect(_habilitado(tester, _activarDatos), isFalse);

        // Mientras tanto, la otra acción del aviso sigue disponible y no se pisan.
        expect(_habilitado(tester, _descargar), isTrue);
        await tester.tap(_descargar);
        await tester.pump();

        espera.complete();
        await asentarAviso(tester);
        expect(_habilitado(tester, _activarDatos), isTrue);
        expect(montaje.arnes.ajustes.aperturasDeRed, 1);
      });

      for (final lanza in [false, true]) {
        testWidgets(
          lanza
              ? 'si la plataforma falla al abrir, explica cómo llegar a mano y no queda trabado'
              : 'si no pudo abrirlos, explica cómo llegar a mano y no queda trabado',
          (tester) async {
            final montaje = await montarAviso(tester, conexion: TipoConexion.sinConexion);
            montaje.arnes.ajustes
              ..resultado = false
              ..lanza = lanza;

            await tocarAviso(tester, _activarDatos);

            expect(
              find.text('No pudimos abrir los ajustes. Abrilos a mano desde el menú del teléfono.'),
              findsOneWidget,
            );
            expect(_habilitado(tester, _activarDatos), isTrue);

            // Un segundo intento, ahora sí.
            montaje.arnes.ajustes
              ..resultado = true
              ..lanza = false;
            await tocarAviso(tester, _activarDatos);
            expect(montaje.arnes.ajustes.aperturasDeRed, 2);
          },
        );
      }
    });
  });

  group('06C·06 · Sin conexión, aviso minimizado (la píldora)', () {
    Future<MontajeAviso> montarMinimizada(
      WidgetTester tester, {
      List<PaqueteTiles>? catalogo,
      AmbitoTrabajo ambito = ambitoMontevideo,
      Size tamano = const Size(390, 844),
      double escala = 1,
    }) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        catalogo: catalogo,
        ambito: ambito,
        tamano: tamano,
        escala: escala,
      );
      await tocarAviso(tester, _minimizar);
      return montaje;
    }

    testWidgets(
      'el texto del canvas y la geometría: a 14 del borde, 44 de alto dibujada, 48 de toque',
      (tester) async {
        await montarMinimizada(tester);

        expect(find.text('Sin conexión · Descargar mapa'), findsOneWidget);
        expect(find.text('!'), findsOneWidget);
        final zonaDeToque = tester.getRect(_pildora);
        expect(zonaDeToque.left, 14);
        expect(zonaDeToque.top, 6);
        expect(zonaDeToque.height, 48);

        final material = find.descendant(of: _pildora, matching: find.byType(Material)).first;
        final dibujada = tester.getRect(material);
        expect(dibujada.height, 44);
        expect(dibujada.top, 8, reason: 'el canvas la dibuja a 8 del borde de arriba');
        expect(tester.widget<Material>(material).color, const Color(0xFFA8312A));
        final texto = tester.widget<Text>(find.text('Sin conexión · Descargar mapa')).style!;
        expect(texto.fontSize, 13.5);
        expect(texto.fontWeight, FontWeight.w600);
        expect(texto.color, Colors.white);
      },
    );

    testWidgets('no tapa los toques del mapa fuera de sí misma', (tester) async {
      final montaje = await montarMinimizada(tester);
      final pildora = tester.getRect(_pildora);
      expect(pildora.right, lessThan(390 - 14), reason: 'la píldora no ocupa todo el ancho');

      // Al lado de la píldora, a su misma altura, hay mapa: el toque le llega.
      await tester.tapAt(Offset(pildora.right + 40, pildora.center.dy));
      await tester.tapAt(const Offset(200, 400));
      expect(montaje.toquesAlMapa, 2);
    });

    testWidgets('«Descargar mapa» desde la píldora encola la descarga y arranca con la conexión', (
      tester,
    ) async {
      final montaje = await montarMinimizada(tester, catalogo: [paqueteMontevideo]);

      await tester.tap(_pildora);
      await tester.tap(_pildora);
      await asentarAviso(tester);
      expect(montaje.arnes.servidor.pedidos, isEmpty);
      expect(_pildora, findsOneWidget, reason: 'sigue visible mientras no haya conexión');

      montaje.arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
      await asentarAviso(tester);

      expect(montaje.arnes.servidor.pedidos, hasLength(1));
      expect(montaje.arnes.montevideoDescargado, isTrue);
      _ningunAviso();
    });

    testWidgets('si el pedido falla, lo dice con un aviso pasajero y la píldora sigue tocable', (
      tester,
    ) async {
      await montarMinimizada(tester, ambito: const AmbitoTrabajo());

      await tester.tap(_pildora);
      await asentarAviso(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(const FailureCiudadRequerida().mensaje), findsWidgets);
      await tester.tap(_pildora);
      await asentarAviso(tester);
      expect(_pildora, findsOneWidget);
    });

    testWidgets(
      'al pedirla, un aviso pasajero dice que se descarga sola; la píldora espera y no lo repite',
      (tester) async {
        final semantica = tester.ensureSemantics();
        try {
          final montaje = await montarMinimizada(tester, catalogo: [paqueteMontevideo]);
          expect(find.byType(SnackBar), findsNothing);
          expect(
            tester.getSemantics(_pildora),
            isSemantics(isButton: true, isEnabled: true, hasTapAction: true),
          );

          await tester.tap(_pildora);
          await asentarAviso(tester);

          expect(find.descendant(of: find.byType(SnackBar), matching: _enCola), findsOneWidget);
          expect(
            tester.getSemantics(_pildora),
            isSemantics(isButton: true, isEnabled: false, hasTapAction: false),
          );

          // Otro toque no pide otra descarga ni repite el aviso.
          await tester.tap(_pildora, warnIfMissed: false);
          await asentarAviso(tester);
          expect(find.byType(SnackBar), findsOneWidget);
          expect(montaje.arnes.servidor.pedidos, isEmpty);
        } finally {
          semantica.dispose();
        }
      },
    );

    testWidgets('con el catálogo ya leído también dice que se descarga sola, una sola vez', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paqueteMontevideo],
      );
      montaje.arnes.conectividad.cambiarA(TipoConexion.sinConexion);
      await asentarAviso(tester);
      await tocarAviso(tester, _minimizar);
      expect(_pildora, findsOneWidget);

      await tester.tap(_pildora);
      await tester.tap(_pildora, warnIfMissed: false);
      await asentarAviso(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.descendant(of: find.byType(SnackBar), matching: _enCola), findsOneWidget);
      expect(
        montaje.arnes.descargador.estadoDe('ciudad-montevideo'),
        isA<DescargaPausada>().having((e) => e.sigueSola, 'sigueSola', true),
      );
    });

    testWidgets(
      'volver atrás y reentrar con el pedido en cola: la píldora sigue esperando y no repite el aviso',
      (tester) async {
        final semantica = tester.ensureSemantics();
        try {
          final montaje = await montarMinimizada(tester, catalogo: [paqueteMontevideo]);
          await tester.tap(_pildora);
          await asentarAviso(tester);
          expect(find.byType(SnackBar), findsOneWidget);

          // El aviso pasajero se va solo.
          await tester.pump(const Duration(seconds: 5));
          await tester.pump(const Duration(seconds: 1));
          expect(find.byType(SnackBar), findsNothing);

          await salirYReentrarAviso(tester, montaje);

          expect(_pildora, findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          expect(
            tester.getSemantics(_pildora),
            isSemantics(isButton: true, isEnabled: false, hasTapAction: false),
          );
          expect(montaje.arnes.servidor.pedidos, isEmpty);
        } finally {
          semantica.dispose();
        }
      },
    );

    testWidgets(
      'a 360×640 y texto al 2x, con el pedido en cola, no desborda con el aviso pasajero',
      (tester) async {
        await montarMinimizada(
          tester,
          catalogo: [paqueteMontevideo],
          tamano: const Size(360, 640),
          escala: 2,
        );

        await tester.tap(_pildora);
        await asentarAviso(tester);

        expect(tester.takeException(), isNull);
        expect(find.descendant(of: find.byType(SnackBar), matching: _enCola), findsOneWidget);
        final aviso = tester.getRect(find.byType(SnackBar));
        expect(aviso.left, greaterThanOrEqualTo(0));
        expect(aviso.right, lessThanOrEqualTo(360));
        expect(aviso.bottom, lessThanOrEqualTo(640));
      },
    );

    testWidgets('a 360×640 y texto al 2x no desborda y se puede tocar', (tester) async {
      await montarMinimizada(tester, tamano: const Size(360, 640), escala: 2);

      expect(tester.takeException(), isNull);
      final rect = tester.getRect(_pildora);
      expect(rect.left, 14);
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.height, greaterThanOrEqualTo(48));
    });

    testWidgets(
      'con conexión otra vez, la píldora desaparece sin dejar un aviso de «sin conexión»',
      (tester) async {
        final montaje = await montarMinimizada(tester, catalogo: [paqueteMontevideo]);

        montaje.arnes.conectividad.cambiarA(TipoConexion.wifi);
        await asentarAviso(tester);

        _ningunAviso();
      },
    );
  });

  group('06C·07 · Con datos móviles', () {
    testWidgets('los textos del canvas, el peso real del paquete y sin ✕', (tester) async {
      await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paquetePesado(44200000)],
      );

      expect(find.text('Estás viendo el mapa con datos móviles'), findsOneWidget);
      expect(
        find.text('Descargalo para usarlo aunque no tengas señal. Conviene hacerlo con Wi-Fi.'),
        findsOneWidget,
      );
      expect(find.text('Descargar mapa · 45 MB'), findsOneWidget);
      expect(find.text('Ahora no'), findsOneWidget);
      expect(find.text('⇩'), findsOneWidget);
      // Sin ✕ ni píldora: el aviso de datos móviles no se minimiza.
      expect(find.byTooltip('Minimizar aviso'), findsNothing);
      expect(_pildora, findsNothing);
      // El mapa se ve en línea con el PMTiles del catálogo.
      expect(_fuente(tester), FuenteTiles.servidorOnline);
    });

    testWidgets(
      'geometría del canvas: tarjeta blanca de borde 1.5, botones de 48 y de ancho completo',
      (tester) async {
        await montarAviso(
          tester,
          conexion: TipoConexion.datosMoviles,
          catalogo: [paquetePesado(44200000)],
        );

        final tarjeta = tester.getRect(_fondoDe(_tarjetaDatos));
        expect(tarjeta.left, 14);
        expect(tarjeta.right, 390 - 14);
        expect(tarjeta.top, 8);
        final decoracion = _decoracion(tester, _tarjetaDatos);
        expect(decoracion.color, Colors.white);
        expect(decoracion.border, Border.all(color: const Color(0xFFCFD6E1), width: 1.5));
        expect(decoracion.borderRadius, BorderRadius.circular(16));

        final titulo = tester
            .widget<Text>(find.text('Estás viendo el mapa con datos móviles'))
            .style!;
        expect(titulo.fontSize, 15);
        expect(titulo.fontWeight, FontWeight.w600);
        expect(titulo.color, const Color(0xFF0E1A2B));
        final cuerpo = tester.widget<Text>(find.textContaining('Descargalo para usarlo')).style!;
        expect(cuerpo.fontSize, 13.5);
        expect(cuerpo.color, const Color(0xFF2A3A52));

        final descargar = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Descargar mapa · 45 MB'),
        );
        expect(descargar.style!.backgroundColor!.resolve({}), const Color(0xFF002856));
        expect(descargar.style!.foregroundColor!.resolve({}), Colors.white);
        final ahora = tester.widget<TextButton>(_ahoraNo);
        expect(ahora.style!.foregroundColor!.resolve({}), const Color(0xFF13407A));
        for (final boton in [
          find.widgetWithText(FilledButton, 'Descargar mapa · 45 MB'),
          _ahoraNo,
        ]) {
          expect(tester.getSize(boton).height, greaterThanOrEqualTo(48));
        }
      },
    );

    testWidgets('«Descargar mapa · N MB» baja el paquete ya, con datos móviles, y el aviso se va', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paqueteMontevideo],
      );
      expect(_descargarConPeso, findsOneWidget);

      await tocarAviso(tester, _descargarConPeso);

      expect(montaje.arnes.servidor.pedidos, hasLength(1));
      expect(montaje.arnes.montevideoDescargado, isTrue);
      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.pmtilesOffline);
    });

    testWidgets('doble toque: una sola descarga', (tester) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paqueteMontevideo],
      );
      final antes = montaje.arnes.conectividad.lecturas;

      await tester.tap(_descargarConPeso);
      await tester.tap(_descargarConPeso, warnIfMissed: false);
      await asentarAviso(tester);

      // Cada `descargar` lee la conexión una vez al prepararse: dos lecturas serían dos pedidos.
      expect(montaje.arnes.conectividad.lecturas - antes, 1);
      expect(montaje.arnes.servidor.pedidos, hasLength(1));
      expect(montaje.arnes.montevideoDescargado, isTrue);
    });

    testWidgets(
      'si no hay espacio, lo dice y el botón vuelve a estar habilitado; al liberar, baja',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.datosMoviles,
          catalogo: [paqueteMontevideo],
        );
        montaje.arnes.espacio.libres = 100;

        await tocarAviso(tester, _descargarConPeso);

        expect(find.textContaining('Espacio insuficiente'), findsOneWidget);
        expect(_habilitado(tester, _descargarConPeso), isTrue);
        expect(montaje.arnes.servidor.pedidos, isEmpty);

        montaje.arnes.espacio.libres = 1 << 40;
        await tocarAviso(tester, _descargarConPeso);

        expect(montaje.arnes.montevideoDescargado, isTrue);
        _ningunAviso();
      },
    );

    testWidgets(
      'si la descarga falla a mitad, lo dice, sigue habilitado y reintentar la completa',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.datosMoviles,
          catalogo: [paqueteMontevideo],
        );
        montaje.arnes.servidor.statusError = 500;

        await tocarAviso(tester, _descargarConPeso);

        expect(montaje.arnes.montevideoDescargado, isFalse);
        expect(_tarjetaDatos, findsOneWidget);
        expect(_habilitado(tester, _descargarConPeso), isTrue);
        expect(_bajando, findsNothing);
        expect(_enCola, findsNothing);
        // El motivo del fallo se ve dentro de la tarjeta (y no una tarjeta vacía).
        expect(
          find.descendant(of: _tarjetaDatos, matching: find.text(const FailureServidor().mensaje)),
          findsOneWidget,
        );

        montaje.arnes.servidor.statusError = null;
        await tocarAviso(tester, _descargarConPeso);

        expect(montaje.arnes.montevideoDescargado, isTrue);
        _ningunAviso();
      },
    );

    testWidgets('«Ahora no» oculta el aviso el resto de la sesión, también al reentrar', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paqueteMontevideo],
      );

      await tocarAviso(tester, _ahoraNo);
      expect(_tarjetaDatos, findsNothing);

      await salirYReentrarAviso(tester, montaje);
      expect(_tarjetaDatos, findsNothing);
      // El mapa sigue siendo el de línea, y no hay descarga sin que el colportor la pida.
      expect(_fuente(tester), FuenteTiles.servidorOnline);
      expect(montaje.arnes.servidor.pedidos, isEmpty);

      // Si después se queda sin conexión, el aviso rojo es otro asunto y sí aparece.
      montaje.arnes.conectividad.cambiarA(TipoConexion.sinConexion);
      await asentarAviso(tester);
      expect(_tarjetaSinConexion, findsOneWidget);
    });

    testWidgets('a 360×640 y texto al 2x no desborda y los dos botones se alcanzan', (
      tester,
    ) async {
      await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paquetePesado(1234500000)],
        tamano: const Size(360, 640),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Descargar mapa · 1235 MB'), findsOneWidget);
      final tarjeta = tester.getRect(_fondoDe(_tarjetaDatos));
      expect(tarjeta.bottom, lessThanOrEqualTo(8 + 640 * .8 + 1));
      for (final boton in [find.text('Descargar mapa · 1235 MB'), _ahoraNo]) {
        await tester.ensureVisible(boton);
        await tester.pump();
        expect(tester.getRect(boton).bottom, lessThanOrEqualTo(640));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('un motivo de falla largo, a 360×640 y texto al 2x, no desborda', (tester) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paqueteMontevideo],
        tamano: const Size(360, 640),
        escala: 2,
      );
      montaje.arnes.espacio.libres = 0;

      await tocarAviso(tester, _descargarConPeso);

      expect(find.textContaining('Espacio insuficiente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // Decisión del 06/10 (pendiente P1 de #190): entre el toque y el mapa, la tarjeta dice en qué está
  // el pedido, con el botón deshabilitado; reducida a la píldora, lo dice un aviso pasajero.
  group('Entre tocar «Descargar mapa» y tener el mapa', () {
    testWidgets('06C·05: sin señal dice que se descarga sola; antes del toque no dice nada', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        catalogo: [paqueteMontevideo],
      );
      expect(_enCola, findsNothing);
      expect(_bajando, findsNothing);
      expect(_habilitado(tester, _descargar), isTrue);

      await tocarAviso(tester, _descargar);

      expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
      expect(_bajando, findsNothing);
      expect(_habilitado(tester, _descargar), isFalse);
      // La otra acción de la tarjeta sigue disponible, y la tarjeta no usa un aviso pasajero.
      expect(_habilitado(tester, _activarDatos), isTrue);
      expect(find.byType(SnackBar), findsNothing);

      // Otro toque (un botón deshabilitado no responde) ni encola otra ni cambia lo que se ve.
      await tester.tap(_descargar, warnIfMissed: false);
      await asentarAviso(tester);
      expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
      expect(montaje.arnes.servidor.pedidos, isEmpty);
    });

    testWidgets(
      '06C·05 a 06C·07: al volver la señal con datos móviles dice «Descargando el mapa…» hasta que '
      'termina, y la tarjeta se va',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.sinConexion,
          catalogo: [paqueteMontevideo],
        );
        final compuerta = _retenerElDisco(montaje.arnes);
        await tocarAviso(tester, _descargar);
        expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);

        montaje.arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await asentarAviso(tester);

        // Con señal, el aviso es el de datos móviles y el pedido sigue siendo el mismo.
        expect(_tarjetaSinConexion, findsNothing);
        expect(_en(_tarjetaDatos, _bajando), findsOneWidget);
        expect(_enCola, findsNothing);
        expect(_habilitado(tester, _descargarConPeso), isFalse);
        expect(_habilitado(tester, _ahoraNo), isTrue);
        expect(montaje.arnes.montevideoDescargado, isFalse);

        compuerta.complete();
        await asentarAviso(tester);

        expect(montaje.arnes.montevideoDescargado, isTrue);
        expect(_bajando, findsNothing);
        _ningunAviso();
        expect(_fuente(tester), FuenteTiles.pmtilesOffline);
      },
    );

    testWidgets(
      '06C·07: «Descargar mapa · N MB» dice «Descargando el mapa…» y espera, también al volver a '
      'entrar; al terminar se va',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.datosMoviles,
          catalogo: [paqueteMontevideo],
        );
        final compuerta = _retenerElDisco(montaje.arnes);
        expect(_bajando, findsNothing);

        await tocarAviso(tester, _descargarConPeso);

        expect(_en(_tarjetaDatos, _bajando), findsOneWidget);
        expect(_enCola, findsNothing);
        expect(_habilitado(tester, _descargarConPeso), isFalse);
        expect(_habilitado(tester, _ahoraNo), isTrue);
        expect(find.byType(SnackBar), findsNothing);

        // Volver atrás y reentrar: el pedido sigue a la vista y no se pide dos veces.
        await salirYReentrarAviso(tester, montaje);
        expect(_en(_tarjetaDatos, _bajando), findsOneWidget);
        expect(_habilitado(tester, _descargarConPeso), isFalse);
        await tester.tap(_descargarConPeso, warnIfMissed: false);
        await asentarAviso(tester);
        expect(montaje.arnes.servidor.pedidos, hasLength(1));

        compuerta.complete();
        await asentarAviso(tester);

        expect(montaje.arnes.montevideoDescargado, isTrue);
        _ningunAviso();
      },
    );

    testWidgets('«Ahora no» mientras baja oculta la tarjeta y la descarga termina igual', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.datosMoviles,
        catalogo: [paqueteMontevideo],
      );
      final compuerta = _retenerElDisco(montaje.arnes);
      await tocarAviso(tester, _descargarConPeso);
      expect(_en(_tarjetaDatos, _bajando), findsOneWidget);

      await tocarAviso(tester, _ahoraNo);
      expect(_tarjetaDatos, findsNothing);
      expect(_bajando, findsNothing);

      compuerta.complete();
      await asentarAviso(tester);

      expect(montaje.arnes.montevideoDescargado, isTrue);
      _ningunAviso();
    });

    testWidgets(
      'se cae la señal a mitad de la descarga: la tarjeta roja dice que sigue sola, y al volver '
      'retoma y termina',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.datosMoviles,
          catalogo: [paqueteMontevideo],
        );
        final compuerta = _retenerElDisco(montaje.arnes);
        await tocarAviso(tester, _descargarConPeso);
        expect(_en(_tarjetaDatos, _bajando), findsOneWidget);

        montaje.arnes.conectividad.cambiarA(TipoConexion.sinConexion);
        await asentarAviso(tester);

        expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
        expect(_bajando, findsNothing);
        expect(_habilitado(tester, _descargar), isFalse);
        expect(montaje.arnes.montevideoDescargado, isFalse);

        compuerta.complete();
        await asentarAviso(tester);
        montaje.arnes.conectividad.cambiarA(TipoConexion.datosMoviles);
        await asentarAviso(tester);

        expect(montaje.arnes.montevideoDescargado, isTrue);
        _ningunAviso();
        expect(_fuente(tester), FuenteTiles.pmtilesOffline);
      },
    );

    testWidgets(
      'falla a mitad de la descarga: se va «Descargando el mapa…», dice el motivo y el botón vuelve; '
      'al reintentar baja',
      (tester) async {
        final montaje = await montarAviso(
          tester,
          conexion: TipoConexion.datosMoviles,
          catalogo: [paqueteMontevideo],
        );
        // El disco se llena en el segundo pedazo (el servidor los manda de a 1000 bytes).
        montaje.arnes.archivos.discoLlenoDespuesDe = 1200;

        await tocarAviso(tester, _descargarConPeso);

        expect(montaje.arnes.montevideoDescargado, isFalse);
        expect(_bajando, findsNothing);
        expect(_enCola, findsNothing);
        expect(_en(_tarjetaDatos, find.textContaining('Espacio insuficiente')), findsOneWidget);
        expect(_habilitado(tester, _descargarConPeso), isTrue);

        montaje.arnes.archivos.discoLlenoDespuesDe = null;
        await tocarAviso(tester, _descargarConPeso);

        expect(montaje.arnes.montevideoDescargado, isTrue);
        _ningunAviso();
      },
    );

    testWidgets('dos acciones seguidas: «Activar datos» y «Descargar mapa» no se pisan', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        catalogo: [paqueteMontevideo],
      );
      final espera = Completer<void>();
      montaje.arnes.ajustes.espera = espera;

      await tester.tap(_activarDatos);
      await tester.pump();
      await tester.tap(_descargar);
      await tester.pump();
      expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
      expect(_habilitado(tester, _activarDatos), isFalse);
      expect(_habilitado(tester, _descargar), isFalse);

      espera.complete();
      await asentarAviso(tester);

      expect(_habilitado(tester, _activarDatos), isTrue);
      expect(_habilitado(tester, _descargar), isFalse);
      expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
      expect(montaje.arnes.ajustes.aperturasDeRed, 1);
    });

    for (final (nombre, conexion, escala) in [
      ('06C·05 en cola', TipoConexion.sinConexion, 1.0),
      ('06C·05 en cola', TipoConexion.sinConexion, 2.0),
      ('06C·07 bajando', TipoConexion.datosMoviles, 1.0),
      ('06C·07 bajando', TipoConexion.datosMoviles, 2.0),
    ]) {
      testWidgets('$nombre a 360×640 con el texto al ${escala}x: no desborda y los botones se '
          'alcanzan', (tester) async {
        final enCola = conexion == TipoConexion.sinConexion;
        final montaje = await montarAviso(
          tester,
          conexion: conexion,
          catalogo: [paqueteMontevideo],
          tamano: const Size(360, 640),
          escala: escala,
        );
        // El disco no escribe: con señal, la descarga queda «bajando» todo el test.
        _retenerElDisco(montaje.arnes);
        final tarjeta = enCola ? _tarjetaSinConexion : _tarjetaDatos;
        final boton = enCola ? _descargar : _descargarConPeso;
        final otro = enCola ? _activarDatos : _ahoraNo;

        await tocarAviso(tester, boton);

        expect(tester.takeException(), isNull);
        expect(_en(tarjeta, enCola ? _enCola : _bajando), findsOneWidget);
        final visible = tester.getRect(
          find.descendant(
            of: find.byType(AvisoMapaConectado),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(visible.bottom, lessThanOrEqualTo(8 + 640 * .8 + 1));
        for (final finder in [boton, otro]) {
          await tester.ensureVisible(finder);
          await tester.pump();
          expect(tester.getRect(finder).bottom, lessThanOrEqualTo(640));
          expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('en la hoja de la vista 03 el renglón también aparece y el botón espera', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        catalogo: [paqueteMontevideo],
        modo: AvisoMapaModo.enHoja,
      );

      await tocarAviso(tester, _descargar);

      expect(_en(_tarjetaSinConexion, _enCola), findsOneWidget);
      expect(_habilitado(tester, _descargar), isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(montaje.arnes.servidor.pedidos, isEmpty);
    });
  });

  group('Con conexión y el mapa no carga', () {
    testWidgets(
      '«No pudimos cargar el mapa de esta ciudad»: el texto pedido, sin «Sin conexión» ni grises',
      (tester) async {
        await montarAviso(tester, catalogo: [paqueteCanelones]);

        expect(find.text('No pudimos cargar el mapa de esta ciudad'), findsOneWidget);
        expect(
          find.text('Tus ubicaciones se siguen viendo. Para ver las calles, probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.textContaining('Sin conexión'), findsNothing);
        expect(find.textContaining('grises'), findsNothing);
        expect(find.byTooltip('Minimizar aviso'), findsNothing);
        // Fondo liso: el mapa sin tiles, el color del diseño.
        expect(_fuente(tester), FuenteTiles.sinTiles);
      },
    );

    testWidgets('con el catálogo caído también, con Wi-Fi o con datos móviles', (tester) async {
      final arnes = ArnesMapa(conexion: TipoConexion.datosMoviles, catalogo: [paqueteMontevideo]);
      arnes.repositorio.falloCatalogo = const FailureSinConexion();
      await montarAviso(tester, arnes: arnes);

      expect(_tarjetaNoCarga, findsOneWidget);
      expect(_tarjetaDatos, findsNothing);
    });

    testWidgets(
      '«Reintentar» vuelve a pedir el catálogo: sin respuesta sigue el aviso y el botón se habilita',
      (tester) async {
        final arnes = ArnesMapa(catalogo: [paqueteMontevideo]);
        arnes.repositorio.falloCatalogo = const FailureSinConexion();
        await montarAviso(tester, arnes: arnes);

        await tocarAviso(tester, _reintentar);

        expect(_tarjetaNoCarga, findsOneWidget);
        expect(_habilitado(tester, _reintentar), isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '«Reintentar» con el catálogo ya disponible: el aviso se va y se ve el mapa en línea',
      (tester) async {
        final arnes = ArnesMapa(catalogo: [paqueteMontevideo]);
        arnes.repositorio.falloCatalogo = const FailureSinConexion();
        await montarAviso(tester, arnes: arnes);
        expect(_tarjetaNoCarga, findsOneWidget);

        arnes.repositorio.falloCatalogo = null;
        await tester.tap(_reintentar);
        await tester.tap(_reintentar, warnIfMissed: false);
        await asentarAviso(tester);

        _ningunAviso();
        expect(_fuente(tester), FuenteTiles.servidorOnline);
      },
    );

    testWidgets(
      'volver atrás y reentrar: el aviso sigue mientras el mapa no cargue, y «Reintentar» también',
      (tester) async {
        final arnes = ArnesMapa(catalogo: [paqueteMontevideo]);
        arnes.repositorio.falloCatalogo = const FailureSinConexion();
        final montaje = await montarAviso(tester, arnes: arnes);
        expect(_tarjetaNoCarga, findsOneWidget);

        await salirYReentrarAviso(tester, montaje);

        expect(_tarjetaNoCarga, findsOneWidget);
        expect(_habilitado(tester, _reintentar), isTrue);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('a 360×640 y texto al 2x no desborda y «Reintentar» se alcanza', (tester) async {
      await montarAviso(
        tester,
        catalogo: [paqueteCanelones],
        tamano: const Size(360, 640),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_reintentar);
      await tester.pump();
      expect(tester.getRect(_reintentar).bottom, lessThanOrEqualTo(640));
      expect(tester.getSize(_reintentar).height, greaterThanOrEqualTo(48));
    });
  });

  group('Sin aviso', () {
    testWidgets('con Wi-Fi y el mapa en línea: nada', (tester) async {
      await montarAviso(tester, catalogo: [paqueteMontevideo]);

      _ningunAviso();
      expect(_fuente(tester), FuenteTiles.servidorOnline);
      expect(find.byType(SizedBox), findsWidgets);
    });

    for (final conexion in TipoConexion.values) {
      testWidgets('con el mapa descargado y ${conexion.name}: nada, y el mapa es el del teléfono', (
        tester,
      ) async {
        final arnes = ArnesMapa(conexion: conexion, catalogo: [paqueteMontevideo]);
        await arnes.repositorio.registrar(descargadoDe(paqueteMontevideo));
        await montarAviso(tester, arnes: arnes);

        _ningunAviso();
        expect(_fuente(tester), FuenteTiles.pmtilesOffline);
      });
    }

    testWidgets('sin conocer la ciudad y con conexión: nada (no se inventa un aviso)', (
      tester,
    ) async {
      await montarAviso(tester, ambito: const AmbitoTrabajo());

      _ningunAviso();
    });

    testWidgets('mientras no se sabe la conexión no se dice «Sin conexión»', (tester) async {
      final arnes = ArnesMapa(conexion: TipoConexion.sinConexion);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: arnes.overrides,
          child: MaterialApp(
            theme: temaClaro(),
            home: const Scaffold(
              body: Stack(
                children: [
                  AvisoMapaConectado(ambito: ambitoMontevideo, modo: AvisoMapaModo.flotante),
                ],
              ),
            ),
          ),
        ),
      );
      // Un solo cuadro, sin dejar que la lectura de la conexión termine.
      expect(find.textContaining('Sin conexión'), findsNothing);
      await asentarAviso(tester);
      expect(_tarjetaSinConexion, findsOneWidget);
    });
  });

  group('En la hoja de la vista 03 (modo enHoja)', () {
    testWidgets('el aviso rojo va sin ✕ ni píldora, y «Descargar mapa» sigue andando', (
      tester,
    ) async {
      final montaje = await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        catalogo: [paqueteMontevideo],
        modo: AvisoMapaModo.enHoja,
      );

      expect(_tarjetaSinConexion, findsOneWidget);
      expect(find.byTooltip('Minimizar aviso'), findsNothing);
      expect(_pildora, findsNothing);

      await tocarAviso(tester, _descargar);
      montaje.arnes.conectividad.cambiarA(TipoConexion.wifi);
      await asentarAviso(tester);
      expect(montaje.arnes.montevideoDescargado, isTrue);
      _ningunAviso();
    });

    testWidgets('a 360×640 y texto al 2x se desplaza con la hoja, sin desbordar', (tester) async {
      await montarAviso(
        tester,
        conexion: TipoConexion.sinConexion,
        modo: AvisoMapaModo.enHoja,
        tamano: const Size(360, 640),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
      final tarjeta = tester.getRect(_fondoDe(_tarjetaSinConexion));
      expect(tarjeta.left, 16);
      expect(tarjeta.right, 360 - 16);
    });
  });
}
