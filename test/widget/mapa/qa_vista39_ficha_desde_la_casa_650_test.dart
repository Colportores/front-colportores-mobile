// QA #650 (PR #663): vista 39 C·02 «Hoja arriba · Personas» → vista 32 B «Ficha de la persona».
// Lo que prueba (además de lo del implementador, que monta la hoja suelta): la hoja de la Lista (modal),
// los estados 32B alcanzables desde la hoja en 4 tamaños, las guías de accesibilidad de la fila y de
// 32B·06/07 con el nombre, y los casos límite (falla y reintento, toques superpuestos, el contexto que
// cambia con la ficha abierta, nombres hostiles).
//
// `--dart-define=QA_CAPTURAS=true` deja PNG en `.dart_tool/qa_capturas/650_*.png` (fuentes reales).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_ficha_desde_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/ficha_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ficha_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/qa_ficha_persona_563_arnes.dart'
    show EstadoFicha, mundoDe563, telefonoChico563, telefonoGrande563;
import 'ficha_persona_arnes.dart';
import 'lista_ubicaciones_arnes.dart';

const _capturas = bool.fromEnvironment('QA_CAPTURAS');

var _fuentes = false;

Future<void> _cargarFuentes(WidgetTester tester) async {
  if (!_capturas || _fuentes) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
        await cargador.load();
        break;
      }
    }
  });
  _fuentes = true;
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_capturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/650_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

final class _Observador extends NavigatorObserver {
  var empujadas = 0;
  var sacadas = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) empujadas++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) sacadas++;
  }
}

Finder get _filas => find.byKey(ClavesHojaCasa.abrirPersona);
Finder get _ficha => find.byType(FichaPersonaPage);
Finder get _hoja => find.byType(HojaCasa);
const _noPudimos = 'No pudimos abrir la ficha. Probá de nuevo.';

PersonaDelEspacio _persona(String id, String nombre, {String apellido = 'Pérez'}) =>
    clienteDePersonas(id, nombre, apellido: apellido);

List<Override> _overridesFicha(MundoFicha m) {
  var contador = 0;
  return [
    fichaPersonaRepositoryProvider.overrideWithValue(m.fichas),
    notaPersonaRepositoryProvider.overrideWithValue(m.notas),
    espacioRepositoryProvider.overrideWithValue(m.espacios),
    cuentasDePersonasProvider.overrideWithValue(m.cuentas),
    movimientosDeCuentaProvider.overrideWithValue(m.movimientos),
    marcadorDeTelefonoProvider.overrideWithValue(m.marcador),
    personaRepositoryProvider.overrideWithValue(m.personas),
    relojPersonaProvider.overrideWithValue(() => ahoraFicha),
    generadorIdPersonaProvider.overrideWithValue(() => 'nota-nueva-${++contador}'),
  ];
}

/// Lo que cambia entre un test y otro de la hoja suelta.
final class _Hoja {
  _Hoja(this.mundo);

  final MundoFicha mundo;
  final observador = _Observador();

  /// La sesión: `null` = sin sesión (el flujo lanza).
  String? colportorId = 'col-1';

  /// Si no es `null`, se espera antes de abrir (una apertura lenta).
  Completer<void>? compuerta;
  final navegador = GlobalKey<NavigatorState>();
  final destinos = <ContextoDeFicha>[];
}

Future<_Hoja> _montarHoja(
  WidgetTester tester, {
  MundoFicha? mundo,
  Stream<ContextoDeLaCasa>? lectura,
  List<PersonaDelEspacio>? personas,
  String espacioId = 'esp-1',
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  await _cargarFuentes(tester);
  final h = _Hoja(mundo ?? MundoFicha());
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesHojaCasa(
          lectura: (_) =>
              lectura ??
              Stream.value(
                ContextoDeLaCasa(
                  espacioId: espacioId,
                  personas: personas ?? [_persona('per-1', 'María')],
                ),
              ),
        ),
        fichaDePersonaDesdeLaCasaProvider.overrideWithValue((datos) async {
          h.destinos.add(datos);
          await h.compuerta?.future;
          await FlujoFichaDesdeLaCasa.abrir(
            h.navegador.currentContext!,
            datos,
            colportorId: h.colportorId,
          );
          return null;
        }),
        ..._overridesFicha(h.mundo),
      ],
      child: MaterialApp(
        navigatorKey: h.navegador,
        navigatorObservers: [h.observador],
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () {},
              arriba: true,
              colportorId: 'col-1',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return h;
}

Future<void> _tocarFila(WidgetTester tester, [Finder? fila]) async {
  final f = fila ?? _filas.first;
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f, warnIfMissed: false);
  await asentar(tester);
}

/// La marca de cada estado 32B (copiada de la QA de #563).
final _marcas = <EstadoFicha, Finder Function()>{
  EstadoFicha.completa: () => find.byKey(ClavesFicha.cuenta),
  EstadoFicha.personaDeBaja: () => find.byKey(ClavesFicha.botonReactivar),
  EstadoFicha.sinHistorial: () => find.byKey(ClavesFicha.hero),
  EstadoFicha.cargando: () => find.byKey(ClavesFicha.cargando),
  EstadoFicha.error: () => find.byKey(ClavesFicha.error),
  EstadoFicha.deptoDeBaja: () => find.byKey(ClavesFicha.botonReactivarDepto),
};

void main() {
  setUpAll(() => WidgetsApp.debugAllowBannerOverride = false);

  final tamanos = [telefonoChico563, telefonoGrande563];
  final escalas = [1.0, 2.0];

  group('C·02 · la hoja con filas tocables: guías de accesibilidad y tamaños', () {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        final donde =
            '${tamano.width.toInt()}×${tamano.height.toInt()} al ${(escala * 100).toInt()} %';
        testWidgets('C·02 con «›» a $donde: toque, etiqueta, contraste y sin overflow', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await _montarHoja(
            tester,
            tamano: tamano,
            escala: escala,
            personas: [
              _persona('per-1', 'María'),
              _persona('per-2', 'Pedro', apellido: 'Gómez'),
              _persona('per-3', 'Ana', apellido: 'Gómez'),
            ],
          );
          expect(_filas, findsNWidgets(3));
          expect(find.text('›'), findsNWidgets(3));
          await _capturar(tester, 'C02_${tamano.width.toInt()}_${(escala * 10).toInt()}');

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (!_capturas) await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
          semantica.dispose();
        });
      }
    }

    testWidgets('el lector lee cada fila como botón con el nombre y la acción de toque', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montarHoja(tester);

      final nodo = tester.getSemantics(find.byKey(ClavesHojaCasa.persona).first);
      expect(nodo.label, contains('María Pérez'));
      expect(nodo.flagsCollection.isButton, isTrue);
      expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      semantica.dispose();
    });
  });

  group('32B alcanzable desde la hoja: cada estado, 4 tamaños', () {
    final estados = _marcas.keys.toList();
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        for (final estado in estados) {
          final donde =
              '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} al ${(escala * 100).toInt()} %';
          testWidgets(donde, (tester) async {
            final semantica = tester.ensureSemantics();
            final h = await _montarHoja(
              tester,
              mundo: mundoDe563(estado),
              tamano: tamano,
              escala: escala,
            );

            await _tocarFila(tester);

            expect(_ficha, findsOneWidget);
            expect(h.destinos.single.personaId, 'per-1');
            expect(h.destinos.single.espacioId, 'esp-1');
            final marca = _marcas[estado]!();
            if (marca.evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                marca,
                300,
                scrollable: find.byType(Scrollable).first,
              );
            }
            expect(marca, findsWidgets, reason: '${estado.rotulo}: falta lo propio del estado');
            await _capturar(
              tester,
              '${estado.name}_${tamano.width.toInt()}_${(escala * 10).toInt()}',
            );
            expect(tester.takeException(), isNull);

            // Las pantallas nuevas del delta (06 y 07, ahora con el nombre) pasan las guías completas.
            if (estado == EstadoFicha.cargando || estado == EstadoFicha.error) {
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              if (!_capturas) await expectLater(tester, meetsGuideline(textContrastGuideline));
            }

            // Volver desde cada estado deja la hoja como estaba.
            await volverAtras(tester);
            expect(_ficha, findsNothing);
            expect(_hoja, findsOneWidget);
            expect(_filas, findsOneWidget);
            semantica.dispose();
          });
        }
      }
    }
  });

  group('32B·06 y 32B·07 con el nombre de la fila', () {
    testWidgets('32B·06: el lector oye «Cargando la ficha de María», no un spinner mudo', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montarHoja(tester, mundo: MundoFicha(cargando: true));
      await _tocarFila(tester);

      expect(find.bySemanticsLabel(TextosFicha.cargando('María')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('32B·07: es región viva, dice qué pasa («de María») y «Reintentar» está a mano', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final mundo = MundoFicha()..fichas.errorAlObservar = StateError('x');
      await _montarHoja(tester, mundo: mundo);
      await _tocarFila(tester);

      final nodo = tester.getSemantics(find.text(TextosFicha.noPudimosLeer('María')));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      expect(find.text(TextosFicha.reintentar), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('32B·07 → «Reintentar» trae la ficha y «Volver» deja la hoja abierta', (
      tester,
    ) async {
      final mundo = MundoFicha()..fichas.errorAlObservar = StateError('x');
      await _montarHoja(tester, mundo: mundo);
      await _tocarFila(tester);
      expect(find.byKey(ClavesFicha.error), findsOneWidget);

      mundo.fichas.errorAlObservar = null;
      await tester.tap(find.text(TextosFicha.reintentar));
      await asentar(tester);
      expect(find.byKey(ClavesFicha.error), findsNothing);
      expect(find.text('María Pérez'), findsWidgets);

      await volverAtras(tester);
      expect(_ficha, findsNothing);
      expect(_filas, findsOneWidget);
    });

    testWidgets('nombres hostiles (emoji, 120 letras, comillas) no desbordan a 360×640 al 200 %', (
      tester,
    ) async {
      final largo = 'Maríaaaaaaaaaaaaaaaa' * 6;
      for (final nombre in ['María 🙂👍', largo, 'D\'Ángelo "Beto" <b>x</b>']) {
        final mundo = MundoFicha()..fichas.errorAlObservar = StateError('x');
        await _montarHoja(
          tester,
          mundo: mundo,
          tamano: telefonoChico563,
          escala: 2,
          personas: [_persona('per-1', nombre)],
        );
        await _tocarFila(tester);
        expect(_ficha, findsOneWidget);
        expect(find.byKey(ClavesFicha.error), findsOneWidget);
        expect(tester.takeException(), isNull, reason: nombre);
        await volverAtras(tester);
      }
    });
  });

  group('32B·06 y 32B·07: el nombre completo de la fila es el título (decisión del 05/11)', () {
    // Es un `Text` con exactamente el nombre que la fila mostraba.
    Finder titulo(String nombre) => find.byWidgetPredicate((w) => w is Text && w.data == nombre);

    for (final estado in [EstadoFicha.cargando, EstadoFicha.error]) {
      testWidgets('${estado.rotulo}: el título es «María Pérez», como la ficha leída', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await _montarHoja(tester, mundo: mundoDe563(estado));
        await _tocarFila(tester);

        expect(titulo('María Pérez'), findsOneWidget);
        expect(
          tester.getSemantics(titulo('María Pérez')).flagsCollection.isHeader,
          isTrue,
          reason: 'el título es un encabezado',
        );
        // El texto del lector de 06 y el aviso de 07 siguen diciendo el nombre de pila.
        if (estado == EstadoFicha.cargando) {
          expect(find.bySemanticsLabel(TextosFicha.cargando('María')), findsOneWidget);
        } else {
          expect(find.text(TextosFicha.noPudimosLeer('María')), findsOneWidget);
        }
        semantica.dispose();
      });

      testWidgets('${estado.rotulo}: persona sin apellido muestra solo el nombre', (tester) async {
        await _montarHoja(
          tester,
          mundo: mundoDe563(estado),
          personas: [_persona('per-1', 'María', apellido: '')],
        );
        await _tocarFila(tester);

        expect(titulo('María'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      for (final tamano in tamanos) {
        for (final escala in escalas) {
          testWidgets(
            '${estado.rotulo}: título largo a ${tamano.width.toInt()}×${tamano.height.toInt()} al ${(escala * 100).toInt()} %: entero y sin overflow',
            (tester) async {
              final semantica = tester.ensureSemantics();
              const completo = 'María de los Ángeles Fernández Ortiz de la Cruz';
              await _montarHoja(
                tester,
                mundo: mundoDe563(estado),
                tamano: tamano,
                escala: escala,
                personas: [
                  _persona('per-1', 'María de los Ángeles', apellido: 'Fernández Ortiz de la Cruz'),
                ],
              );
              await _tocarFila(tester);

              expect(titulo(completo), findsOneWidget, reason: 'el título se dibuja entero');
              await _capturar(
                tester,
                'titulo_${estado.name}_${tamano.width.toInt()}_${(escala * 10).toInt()}',
              );
              expect(tester.takeException(), isNull);
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              if (!_capturas) await expectLater(tester, meetsGuideline(textContrastGuideline));
              semantica.dispose();
            },
          );
        }
      }
    }

    testWidgets(
      'el título ya no desaparece al reintentar: 07 → Reintentar → la ficha con el mismo nombre',
      (tester) async {
        final mundo = MundoFicha()..fichas.errorAlObservar = StateError('x');
        await _montarHoja(tester, mundo: mundo);
        await _tocarFila(tester);
        expect(titulo('María Pérez'), findsOneWidget);

        mundo.fichas.errorAlObservar = null;
        await tester.tap(find.text(TextosFicha.reintentar));
        await asentar(tester);

        expect(find.byKey(ClavesFicha.error), findsNothing);
        expect(
          titulo('María Pérez'),
          findsOneWidget,
          reason: 'un solo título, el de la ficha leída',
        );
      },
    );
  });

  group('casos límite del flujo', () {
    testWidgets('falla a mitad: sin sesión avisa, la fila se habilita y con sesión después abre', (
      tester,
    ) async {
      final h = await _montarHoja(tester);
      h.colportorId = null;

      await _tocarFila(tester);
      expect(_ficha, findsNothing);
      expect(find.text(_noPudimos), findsOneWidget);

      h.colportorId = 'col-1';
      await _tocarFila(tester);
      expect(_ficha, findsOneWidget);
      await volverAtras(tester);
      expect(_ficha, findsNothing);
      expect(h.destinos.length, 2);
    });

    testWidgets('el aviso de «No pudimos abrir la ficha» se anuncia (región viva)', (tester) async {
      final semantica = tester.ensureSemantics();
      final h = await _montarHoja(tester);
      h.colportorId = null;
      await _tocarFila(tester);

      final nodo = tester.getSemantics(find.text(_noPudimos));
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      semantica.dispose();
    });

    testWidgets('sesión con solo espacios cuenta como sin sesión', (tester) async {
      final h = await _montarHoja(tester);
      h.colportorId = '   ';
      await _tocarFila(tester);
      expect(_ficha, findsNothing);
      expect(find.text(_noPudimos), findsOneWidget);
    });

    testWidgets('toques superpuestos: dos toques reales antes de pintar abren una sola ficha', (
      tester,
    ) async {
      final h = await _montarHoja(tester);
      final antes = h.observador.empujadas;

      await tester.tap(_filas.first);
      await tester.tap(_filas.first, warnIfMissed: false);
      await asentar(tester);

      expect(_ficha, findsOneWidget);
      expect(h.observador.empujadas - antes, 1);
      expect(h.destinos.length, 1);
    });

    testWidgets('apertura lenta: mientras espera, otra fila no abre una segunda ficha', (
      tester,
    ) async {
      final h = await _montarHoja(
        tester,
        personas: [
          _persona('per-1', 'María'),
          _persona('per-2', 'Pedro', apellido: 'Gómez'),
        ],
      );
      h.compuerta = Completer<void>();

      await tester.tap(_filas.first);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(_filas.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 60));
      expect(h.destinos.length, 1, reason: 'la guarda corta el segundo toque');

      h.compuerta!.complete();
      await asentar(tester);
      expect(_ficha, findsOneWidget);
      expect(tester.widget<FichaPersonaPage>(_ficha).personaId, 'per-1');
    });

    testWidgets(
      'el contexto cambia con la ficha abierta (persona dada de baja): al volver no queda la fila ni se rompe',
      (tester) async {
        final contexto = StreamController<ContextoDeLaCasa>();
        addTearDown(contexto.close);
        await _montarHoja(tester, lectura: contexto.stream);
        contexto.add(ContextoDeLaCasa(espacioId: 'esp-1', personas: [_persona('per-1', 'María')]));
        await tester.pump();
        await tester.pump();

        await _tocarFila(tester);
        expect(_ficha, findsOneWidget);

        contexto.add(const ContextoDeLaCasa(espacioId: 'esp-1'));
        await asentar(tester);
        await volverAtras(tester);

        expect(_ficha, findsNothing);
        expect(_filas, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('la hoja se desmonta con la ficha abierta: al cerrar la ficha no hay excepción', (
      tester,
    ) async {
      final h = await _montarHoja(tester);
      await _tocarFila(tester);
      expect(_ficha, findsOneWidget);

      // Se reemplaza el árbol de la hoja por otra cosa mientras la ficha sigue encima.
      unawaited(
        h.navegador.currentState!.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('otra pantalla'))),
        ),
      );
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('otra pantalla'), findsOneWidget);
    });

    testWidgets('edificio: la ficha lleva el depto de la fila, no el edificio', (tester) async {
      final h = await _montarHoja(tester, espacioId: 'dep-3B');
      await _tocarFila(tester);
      expect(h.destinos.single.espacioId, 'dep-3B');
      expect(tester.widget<FichaPersonaPage>(_ficha).espacioId, 'dep-3B');
    });

    testWidgets('20 personas: abrir la 1.ª y la 20.ª, ida y vuelta, deja el desplazamiento', (
      tester,
    ) async {
      final personas = [for (var i = 1; i <= 20; i++) _persona('p-$i', 'Persona $i')];
      await _montarHoja(tester, personas: personas, tamano: const Size(390, 700));
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('fila_persona_p-20')),
        200,
        scrollable: scroll,
      );
      final antes = tester.state<ScrollableState>(scroll).position.pixels;

      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('fila_persona_p-20')), matching: _filas),
      );
      await asentar(tester);
      expect(tester.widget<FichaPersonaPage>(_ficha).personaId, 'p-20');
      await volverAtras(tester);
      expect(tester.state<ScrollableState>(scroll).position.pixels, antes);

      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('fila_persona_p-20')), matching: _filas),
      );
      await asentar(tester);
      expect(tester.widget<FichaPersonaPage>(_ficha).personaId, 'p-20');
    });
  });

  group(
    'la hoja de la Lista (modal): la ficha se apila encima y al volver la hoja sigue arriba',
    () {
      Future<MundoFicha> abrirDesdeLaLista(
        WidgetTester tester, {
        MundoFicha? mundo,
        String? sesion = 'col-1',
        double escala = 1,
        Size tamano = const Size(390, 844),
      }) async {
        final m = mundo ?? MundoFicha();
        await _cargarFuentes(tester);
        late BuildContext Function() ctx;
        ctx = () => tester.element(find.byType(ListaUbicacionesPage));
        await montarLista(
          tester,
          repo: RepoListaFalso([
            filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40),
          ]),
          escala: escala,
          tamano: tamano,
          lecturaContexto: (_) => Stream.value(
            ContextoDeLaCasa(
              espacioId: 'esp-1',
              personas: [
                _persona('per-1', 'María'),
                _persona('per-2', 'Pedro', apellido: 'Gómez'),
              ],
            ),
          ),
          masOverrides: [
            ..._overridesFicha(m),
            fichaDePersonaDesdeLaCasaProvider.overrideWithValue(
              (datos) => FlujoFichaDesdeLaCasa.abrir(ctx(), datos, colportorId: sesion),
            ),
          ],
        );
        await tester.tap(find.text('Av. Italia 1234'));
        await asentarLista(tester);
        await tester.tap(find.byKey(ClavesHojaCasa.asaDeLaLista));
        await asentarLista(tester);
        return m;
      }

      double alto(WidgetTester tester) => tester
          .getSize(
            find
                .ancestor(
                  of: find.byKey(ClavesHojaCasa.asaDeLaLista),
                  matching: find.byType(AnimatedContainer),
                )
                .first,
          )
          .height;

      testWidgets(
        'tocar a María abre su ficha y «Volver» deja la hoja arriba, en Personas, a la misma altura',
        (tester) async {
          await abrirDesdeLaLista(tester);
          expect(find.byKey(ClavesHojaCasa.pestanas), findsOneWidget);
          final altoAntes = alto(tester);

          await _tocarFila(tester);
          expect(_ficha, findsOneWidget);
          expect(tester.widget<FichaPersonaPage>(_ficha).nombre, 'María');
          await _capturar(tester, 'lista_ficha');

          await volverAtras(tester);
          expect(_ficha, findsNothing);
          expect(_hoja, findsOneWidget);
          expect(find.byKey(ClavesHojaCasa.pestanas), findsOneWidget);
          expect(find.byKey(ClavesHojaCasa.listaDePersonas), findsOneWidget);
          expect(alto(tester), closeTo(altoAntes, 1));
          await _capturar(tester, 'lista_vuelta');
        },
      );

      testWidgets(
        '«atrás» del sistema cierra solo la ficha: la hoja de la Lista sigue; otro atrás la cierra',
        (tester) async {
          await abrirDesdeLaLista(tester);
          await _tocarFila(tester);

          await tester.binding.handlePopRoute();
          await asentar(tester);
          expect(_ficha, findsNothing);
          expect(_hoja, findsOneWidget);

          await tester.binding.handlePopRoute();
          await asentarLista(tester);
          expect(_hoja, findsNothing);
        },
      );

      testWidgets('sin sesión: avisa dentro de la hoja de la Lista y la fila sigue tocable', (
        tester,
      ) async {
        await abrirDesdeLaLista(tester, sesion: null);
        await _tocarFila(tester);

        expect(_ficha, findsNothing);
        expect(find.text(_noPudimos), findsOneWidget);
        expect(_hoja, findsOneWidget);
        await _tocarFila(tester);
        expect(find.text(_noPudimos), findsOneWidget);
      });

      testWidgets('tres vueltas ficha/hoja, una por persona, a 360×640 al 200 %', (tester) async {
        await abrirDesdeLaLista(tester, tamano: telefonoChico563, escala: 2);
        for (final i in [0, 1, 0]) {
          await _tocarFila(tester, _filas.at(i));
          expect(_ficha, findsOneWidget, reason: 'fila $i');
          await volverAtras(tester);
          expect(_ficha, findsNothing);
          expect(find.byKey(ClavesHojaCasa.pestanas), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    },
  );

  group('privacidad', () {
    testWidgets('el aviso de falla no lleva el nombre ni los ids de la persona', (tester) async {
      final h = await _montarHoja(
        tester,
        personas: [_persona('per-1', 'Jorge', apellido: 'Secreto')],
      );
      h.colportorId = null;
      await _tocarFila(tester);

      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.contains('No pudimos'))
          .join('|');
      expect(textos, isNot(contains('Jorge')));
      expect(textos, isNot(contains('per-1')));
    });
  });
}
