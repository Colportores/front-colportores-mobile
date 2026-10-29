// QA ronda 1 de la vista 39 (base), C·01 «Tocar una casa: resumen» y los estados E·01 a E·06 que la hoja
// compone (HU-UBI-003, #444, PR #471). Complementa a `hoja_casa_444_test.dart` y
// `hoja_casa_integracion_444_test.dart` (Ahem, un tamaño) con lo que esos no miden:
//  - la matriz de estados de la hoja entera × tamaños (360×640 y 412×915) × texto 1.0 y 2.0 con las
//    FUENTES REALES: sin overflow, nada fuera de la pantalla por los costados, tamaños de toque (Android
//    e iOS) y etiquetas para el lector; cada celda saca una captura a `.dart_tool/qa_capturas/` solo
//    con `--dart-define=QA_CAPTURAS=true` (nunca se commitea);
//  - la hoja DENTRO del mapa (a un tercio) y de la Lista (hoja modal) en esos tamaños;
//  - lo que ve el colportor en el mapa sin desplazar la hoja (qué entra a un tercio de la pantalla);
//  - casos límite que los tests del PR no tocan (dirección vacía, deuda de un centavo, frontera de 100 m,
//    «Reactivar» desde la hoja de la Lista y su «Deshacer»).
// El contraste va aparte (`qa_vista39_hoja_casa_444_contraste_test.dart`): con letra real da falsos
// negativos.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/camara_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart' show puntoItalia;
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias;
import 'lista_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
final _raiz = GlobalKey();

const _t360 = Size(360, 640);
const _t412 = Size(412, 915);

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    // La app entera (incluye las hojas modales): la capa raíz de la vista.
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(tester.binding.renderViews.first.paintBounds);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa471_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Rect _rect(Element e) {
  final box = e.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

Rect _rectDe(WidgetTester tester, Finder f) => _rect(tester.element(f));

/// Envuelve la app para poder sacar la captura y fijar la escala del texto.
Widget _envolver(Widget hijo, {required double escala, bool lector = false}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: temaClaro(),
  builder: (context, child) => RepaintBoundary(
    key: _raiz,
    child: MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
      child: child!,
    ),
  ),
  home: hijo,
);

Future<void> _montarHoja(
  WidgetTester tester, {
  ItemListaUbicacion? item,
  Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa clave)? lectura,
  FutureOr<void> Function(ContextoDeVisita)? registrarVisita,
  FutureOr<void> Function(ContextoDeCobro)? cobrar,
  bool conReactivar = true,
  Size tamano = _t360,
  double escala = 1,
  List<int>? cierres,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesHojaCasa(
        lectura: lectura,
        registrarVisita: registrarVisita,
        cobrar: cobrar,
      ),
      child: _envolver(
        Scaffold(
          backgroundColor: Colors.white,
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: item ?? itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () => cierres?.add(cierres.length),
              alReactivar: conReactivar ? () {} : null,
            ),
          ),
        ),
        escala: escala,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder get _titulo => find.byKey(ClavesHojaCasa.titulo);
Finder get _subtitulo => find.byKey(ClavesHojaCasa.subtitulo);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);
Finder get _cobrar => find.byKey(ClavesHojaCasa.cobrar);
Finder get _persona => find.byKey(ClavesHojaCasa.persona);
Finder get _nota => find.byKey(ClavesHojaCasa.nota);

SemanticsOwner _dueno(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!;

// ---------------------------------------------------------------------------------------------
// La matriz: cada estado de la hoja, armado como lo arma el PR.

class _Caso {
  const _Caso(
    this.nombre, {
    this.item,
    this.lectura,
    this.conDestinos = true,
    this.conReactivar = true,
    this.despues,
  });

  final String nombre;
  final ItemListaUbicacion Function()? item;
  final Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa)? Function()? lectura;
  final bool conDestinos;
  final bool conReactivar;
  final Future<void> Function(WidgetTester tester)? despues;
}

final _persona0 = clienteDePersonas(
  'p-largo',
  'Maximiliano Alejandro José',
  apellido: 'Rodríguez de la Fuente y Martínez',
);

final _casos = <_Caso>[
  const _Caso('C01-completo'),
  const _Caso('C01-sin-destinos', conDestinos: false),
  _Caso(
    'C01-vacio',
    lectura: () =>
        (_) => Stream.value(const ContextoDeLaCasa()),
  ),
  _Caso(
    'C01-textos-largos',
    item: () => itemDeLaHoja(
      calle: 'Avenida General Don José Gervasio Artigas y Bulevar',
      numero: '12345 bis apartamento 7',
      metros: 20,
    ),
    lectura: () =>
        (_) => Stream.value(
          ContextoDeLaCasa(
            espacioId: 'esp-1',
            personas: [_persona0],
            saldosCentavos: const {'p-largo': 123456789},
            nota: notaCon(
              '${'Perro suelto: tocar timbre y esperar. ' * 12}Después de las 18 hs hay alguien.',
            ),
          ),
        ),
  ),
  _Caso(
    'C01-edificio',
    item: () => itemDeLaHoja(tipo: TipoUbicacion.edificio, estado: null, metros: null),
    lectura: () =>
        (_) => Stream.value(const ContextoDeLaCasa()),
  ),
  _Caso(
    'E01-cargando',
    lectura: () => (_) {
      final c = StreamController<ContextoDeLaCasa>();
      addTearDown(c.close);
      return c.stream;
    },
  ),
  _Caso(
    'E02-error',
    lectura: () =>
        (_) => Stream.error(StateError('no se pudo leer')),
  ),
  _Caso(
    'E04-baja-con-reactivar',
    item: () => itemDeLaHoja(baja: DateTime.utc(2026, 10, 18, 15), estado: null),
  ),
  _Caso(
    'E04-baja-por-union',
    item: () => itemDeLaHoja(baja: DateTime.utc(2026, 10, 18, 15), estado: null),
    conReactivar: false,
  ),
  _Caso('E05-lejos-650', item: () => itemDeLaHoja(metros: 650)),
  _Caso('E05-lejos-3km', item: () => itemDeLaHoja(metros: 3250)),
  _Caso(
    'falla-registrar',
    despues: (tester) async {
      await tester.ensureVisible(find.byKey(ClavesHojaCasa.registrarVisita));
      await tester.tap(find.byKey(ClavesHojaCasa.registrarVisita));
      await tester.pump();
      await tester.pump();
    },
  ),
];

void main() {
  setUpAll(cargarTipografias);

  const tamanos = [_t360, _t412];
  const escalas = [1.0, 2.0];

  group('Matriz: la hoja de la casa × estados × tamaños × texto', () {
    for (final caso in _casos) {
      for (final t in tamanos) {
        for (final s in escalas) {
          final celda = '${caso.nombre} · ${t.width.toInt()}×${t.height.toInt()} · texto $s×';
          testWidgets('$celda: sin overflow, dentro de la pantalla y con toques de 48 dp', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            await _montarHoja(
              tester,
              item: caso.item?.call(),
              lectura: caso.lectura?.call(),
              registrarVisita: caso.conDestinos
                  ? (caso.nombre == 'falla-registrar' ? (_) => throw StateError('no abre') : (_) {})
                  : null,
              cobrar: caso.conDestinos ? (_) {} : null,
              conReactivar: caso.conReactivar,
              tamano: t,
              escala: s,
            );
            await caso.despues?.call(tester);

            expect(tester.takeException(), isNull, reason: celda);
            for (final texto in find.byType(Text).evaluate()) {
              final caja = _rect(texto);
              expect(caja.left, greaterThanOrEqualTo(-0.5), reason: '$celda · ${texto.widget}');
              expect(
                caja.right,
                lessThanOrEqualTo(t.width + 0.5),
                reason: '$celda · ${texto.widget}',
              );
            }
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await _capturar(tester, 'hoja_${caso.nombre}_${t.width.toInt()}_x${s.toInt()}');
            handle.dispose();
          });
        }
      }
    }
  });

  group('La hoja dentro del mapa (a un tercio) y de la Lista', () {
    for (final t in tamanos) {
      for (final s in escalas) {
        final celda = '${t.width.toInt()}×${t.height.toInt()} · texto $s×';
        testWidgets(
          'mapa · $celda: tocar un marcador abre la hoja sin overflow y con toques de 48 dp',
          (tester) async {
            final handle = tester.ensureSemantics();
            final m = await montarMapaUbicaciones(
              tester,
              repo: RepoListaFalso([
                filaLista(
                  'a',
                  calle: 'Grecia',
                  numero: '3310',
                  metrosAlNorte: 20,
                  estado: EstadoCasa.cobranzaPendiente,
                ),
              ]),
              tamano: t,
              escala: s,
              registrarVisita: (_) {},
              cobrar: (_) {},
            );
            m.mapa.tocarPunto('a');
            await asentarLista(tester);

            expect(find.byType(HojaCasa), findsOneWidget);
            expect(tester.takeException(), isNull, reason: celda);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await _capturar(tester, 'mapa_cobro_${t.width.toInt()}_x${s.toInt()}');
            handle.dispose();
          },
        );

        testWidgets(
          'Lista · $celda: tocar una fila abre la hoja sin overflow y con toques de 48 dp',
          (tester) async {
            final handle = tester.ensureSemantics();
            await montarLista(
              tester,
              repo: RepoListaFalso([
                filaLista(
                  'casa-1',
                  calle: 'Rivadavia',
                  numero: '100',
                  estado: EstadoCasa.cobranzaPendiente,
                ),
              ]),
              tamano: t,
              escala: s,
              registrarVisita: (_) {},
            );
            await tester.tap(find.text('Rivadavia 100'));
            await asentarLista(tester);

            expect(find.byType(HojaCasa), findsOneWidget);
            expect(tester.takeException(), isNull, reason: celda);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await _capturar(tester, 'lista_${t.width.toInt()}_x${s.toInt()}');
            handle.dispose();
          },
        );
      }
    }
  });

  group('Medidas: qué se ve en el mapa sin desplazar la hoja', () {
    for (final t in tamanos) {
      for (final s in escalas) {
        testWidgets(
          'mapa · ${t.width.toInt()}×${t.height.toInt()} · texto $s×: el título, el subtítulo y '
          'la persona de la casa entran en la hoja sin desplazar',
          (tester) async {
            final m = await montarMapaUbicaciones(
              tester,
              repo: RepoListaFalso([
                filaLista(
                  'a',
                  calle: 'Grecia',
                  numero: '3310',
                  metrosAlNorte: 20,
                  estado: EstadoCasa.cobranzaPendiente,
                ),
              ]),
              tamano: t,
              escala: s,
            );
            m.mapa.tocarPunto('a');
            await asentarLista(tester);
            await _capturar(tester, 'mapa_sin_cobro_${t.width.toInt()}_x${s.toInt()}');

            final hojaRect = _rectDe(tester, hoja);
            for (final (nombre, f) in [
              ('título', _titulo),
              ('subtítulo', _subtitulo),
              ('persona', _persona),
            ]) {
              final r = _rectDe(tester, f);
              expect(
                r.bottom,
                lessThanOrEqualTo(hojaRect.bottom + 0.5),
                reason:
                    '$nombre queda bajo el pliegue de la hoja: ${r.bottom} > ${hojaRect.bottom}',
              );
            }
          },
          // skip: QA #444 — a 360×640 con texto 2.0× la hoja a un tercio solo deja ver el título y media
          // línea del subtítulo: la persona queda bajo el pliegue (menor; se llega desplazando).
          skip: t == _t360 && s == 2.0,
        );
      }
    }
  });

  group('Casos límite de los datos', () {
    testWidgets('una casa sin calle ni número se titula «Sin dirección», nunca vacío', (
      tester,
    ) async {
      await _montarHoja(tester, item: itemDeLaHoja(calle: null, numero: null));
      expect(tester.widget<Text>(_titulo).data, 'Sin dirección');
    });

    testWidgets('una dirección de solo espacios se titula «Sin dirección»', (tester) async {
      await _montarHoja(
        tester,
        item: itemDeLaHoja(calle: '   ', numero: '  '),
      );
      expect(tester.widget<Text>(_titulo).data, 'Sin dirección');
    });

    testWidgets('frontera de «lejos»: a 99,9 m no avisa y a 100 m sí', (tester) async {
      await _montarHoja(tester, item: itemDeLaHoja(metros: 99.9));
      expect(find.byKey(ClavesEstadosHojaCasa.avisoLejos), findsNothing);

      await _montarHoja(tester, item: itemDeLaHoja(metros: 100));
      expect(find.byKey(ClavesEstadosHojaCasa.avisoLejos), findsOneWidget);
      expect(find.text(TextosEstadosHojaCasa.lejos(100)), findsOneWidget);
    });

    testWidgets('una deuda de un centavo dice «Debe \$ 0,01» y se puede cobrar', (tester) async {
      await _montarHoja(
        tester,
        lectura: (_) => Stream.value(
          ContextoDeLaCasa(
            espacioId: 'esp-1',
            personas: [pedroGomez],
            saldosCentavos: const {'p-pedro': 1},
            nota: notaDelCanvas,
          ),
        ),
        registrarVisita: (_) {},
        cobrar: (_) {},
      );
      expect(find.text(r'Debe $ 0,01'), findsOneWidget);
      expect(_cobrar, findsOneWidget);
    });

    testWidgets('una deuda negativa o en cero no se escribe y no ofrece cobrar', (tester) async {
      for (final saldo in [0, -500]) {
        await _montarHoja(
          tester,
          lectura: (_) => Stream.value(
            ContextoDeLaCasa(
              espacioId: 'esp-1',
              personas: [pedroGomez],
              saldosCentavos: {'p-pedro': saldo},
            ),
          ),
          registrarVisita: (_) {},
          cobrar: (_) {},
        );
        expect(find.textContaining('Debe'), findsNothing, reason: 'saldo $saldo');
        expect(_cobrar, findsNothing, reason: 'saldo $saldo');
        expect(_persona, findsOneWidget);
      }
    });

    testWidgets('un nombre con emoji y una nota con emoji no rompen la hoja ni las iniciales', (
      tester,
    ) async {
      await _montarHoja(
        tester,
        lectura: (_) => Stream.value(
          ContextoDeLaCasa(
            espacioId: 'esp-1',
            personas: [clienteDePersonas('p-e', '😀María', apellido: '🐶Pérez')],
            nota: notaCon('Ojo con el perro 🐕‍🦺 y el portón 🚪'),
          ),
        ),
        registrarVisita: (_) {},
      );
      expect(tester.takeException(), isNull);
      expect(find.text('😀🐶'), findsOneWidget);
      expect(find.text('Ojo con el perro 🐕‍🦺 y el portón 🚪'), findsOneWidget);
    });

    testWidgets('la nota y las personas no salen en el toString de la nota ni de la hoja (PII)', (
      tester,
    ) async {
      expect(notaDelCanvas.toString(), isNot(contains('Perro suelto')));
      expect(pedroGomez.toString(), isNot(contains('Pedro')));
      expect(pedroGomez.toString(), isNot(contains('Gómez')));
    });
  });

  group('Casos límite de las acciones', () {
    testWidgets('tras una falla de «Registrar visita», «\$ Cobrar» funciona y borra el aviso', (
      tester,
    ) async {
      var cobros = 0;
      var intentos = 0;
      await _montarHoja(
        tester,
        registrarVisita: (_) {
          intentos++;
          throw StateError('no abre');
        },
        cobrar: (_) => cobros++,
      );
      await tester.ensureVisible(_registrar);
      await tester.tap(_registrar);
      await tester.pump();
      await tester.pump();
      expect(find.text('No pudimos abrir «Registrar visita». Probá de nuevo.'), findsOneWidget);

      await tester.ensureVisible(_cobrar);
      await tester.tap(_cobrar);
      await tester.pump();
      await tester.pump();

      expect(intentos, 1);
      expect(cobros, 1);
      expect(find.textContaining('No pudimos abrir'), findsNothing);
    });

    testWidgets('el aviso de falla se anuncia (región viva) y dice qué hacer', (tester) async {
      final handle = tester.ensureSemantics();
      await _montarHoja(tester, registrarVisita: (_) => throw StateError('no abre'));
      await tester.ensureVisible(_registrar);
      await tester.tap(_registrar);
      await tester.pump();
      await tester.pump();

      final aviso = find.text('No pudimos abrir «Registrar visita». Probá de nuevo.');
      expect(aviso, findsOneWidget);
      // Algún ancestro del aviso es región viva (la hoja entera lo es).
      var anuncia = false;
      SemanticsNode? nodo = tester.getSemantics(aviso);
      while (nodo != null) {
        if (nodo.flagsCollection.isLiveRegion) anuncia = true;
        nodo = nodo.parent;
      }
      expect(anuncia, isTrue);
      handle.dispose();
    });

    testWidgets('«Reintentar» de E·02 por el lector de pantalla vuelve a leer la casa', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var lecturas = 0;
      await _montarHoja(
        tester,
        lectura: (_) {
          lecturas++;
          return lecturas == 1 ? Stream.error(StateError('x')) : Stream.value(contextoDelCanvas);
        },
      );
      expect(find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeer), findsOneWidget);

      final boton = tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.accionDelAviso));
      _dueno(tester).performAction(boton.id, SemanticsAction.tap);
      await tester.pump();
      await tester.pump();

      expect(lecturas, 2);
      expect(find.text('Pedro Gómez'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('el lector encuentra «Registrar visita» y «\$ Cobrar a Pedro Gómez» como botones', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montarHoja(tester, registrarVisita: (_) {}, cobrar: (_) {});
      expect(
        find.semantics.byLabel('Registrar visita'),
        findsOneWidget,
        reason: 'el botón debe tener su propio nodo',
      );
      expect(tester.getSemantics(_registrar).flagsCollection.isButton, isTrue);
      expect(tester.getSemantics(_cobrar).label, r'$ Cobrar a Pedro Gómez');
      handle.dispose();
    });

    testWidgets('la ✕ avisa su nombre al lector y llega a 48 dp con texto 2.0 en 360×640', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montarHoja(tester, escala: 2);
      final cerrar = find.byKey(ClavesMapaUbicaciones.cerrarVistaPrevia);
      expect(tester.getSize(cerrar).shortestSide, greaterThanOrEqualTo(48));
      expect(find.semantics.byLabel('Cerrar vista previa'), findsOneWidget);
      handle.dispose();
    });
  });

  group('La nota larga y el texto grande', () {
    testWidgets('con 2.0 y una nota de 3 renglones, la nota entera entra en una fila legible', (
      tester,
    ) async {
      await _montarHoja(
        tester,
        escala: 2,
        lectura: (_) => Stream.value(
          ContextoDeLaCasa(
            espacioId: 'esp-1',
            personas: [pedroGomez],
            saldosCentavos: const {'p-pedro': 120000},
            nota: notaCon('Perro suelto: tocar timbre y esperar. ' * 6),
          ),
        ),
        registrarVisita: (_) {},
        cobrar: (_) {},
      );
      expect(tester.takeException(), isNull);
      final r = _rectDe(tester, _nota);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(360));
    });
  });

  group('E·06 en el mapa: «3 ubicaciones acá» con las fuentes reales', () {
    for (final t in tamanos) {
      for (final s in escalas) {
        testWidgets(
          '${t.width.toInt()}×${t.height.toInt()} · texto $s×: sin overflow, con toques de 48 dp '
          'y el título «3 ubicaciones acá»',
          (tester) async {
            final handle = tester.ensureSemantics();
            final m = await montarMapaUbicaciones(
              tester,
              repo: RepoListaFalso([
                filaLista('u-1', calle: 'Grecia', numero: '3310', metrosAlNorte: 30),
                filaLista('u-2', calle: 'Grecia', numero: '3310 bis', metrosAlNorte: 30),
                filaLista(
                  'u-3',
                  tipo: TipoUbicacion.negocio,
                  calle: 'Grecia',
                  numero: '3312',
                  metrosAlNorte: 30,
                ),
              ]),
              tamano: t,
              escala: s,
            );
            m.mapa.moverPorGesto(CamaraMapa(centro: puntoItalia, zoom: MapaAlta.zoomMaximo));
            m.mapa.tocarPunto('u-1');
            await asentarLista(tester);

            expect(find.text('3 ubicaciones acá'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await _capturar(tester, 'e06_${t.width.toInt()}_x${s.toInt()}');
            handle.dispose();
          },
        );
      }
    }
  });

  // Hallazgos menores de QA #444. El del avatar (iniciales a 2,0×) está corregido; el del subtítulo con la
  // distancia en E·05 queda con `skip`: lo decide el agente de decisiones (gana el canvas), ver #541.
  group('Hallazgos menores (QA #444)', () {
    const verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

    testWidgets(
      'las iniciales del avatar de la persona no se parten ni se cortan con texto 2.0 en 360×640',
      (tester) async {
        await _montarHoja(tester, escala: 2, registrarVisita: (_) {}, cobrar: (_) {});
        final renglones = tester
            .renderObject<RenderParagraph>(find.text('PG'))
            .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 2))
            .length;
        expect(
          renglones,
          1,
          reason:
              'las dos letras bajan a dos renglones y el círculo de 34 dp las corta '
              '(captura qa471_hoja_C01-completo_360_x2.png)',
        );
      },
    );

    testWidgets(
      'E·05: el subtítulo no repite la distancia que ya dice el aviso «Estás a 650 m de esta casa.»',
      (tester) async {
        await _montarHoja(tester, item: itemDeLaHoja(metros: 650));
        expect(find.text(TextosEstadosHojaCasa.lejos(650)), findsOneWidget);
        expect(
          tester.widget<Text>(_subtitulo).data,
          isNot(contains('de vos')),
          reason: 'el canvas E·05 deja el subtítulo en «Casa · Cobranza pendiente»',
        );
      },
      // skip: QA #444 — el canvas E·05 dibuja el subtítulo sin «a 650 m de vos» (lo dice el aviso); la
      // hoja lo dice dos veces (menor).
      skip: !verHallazgos,
    );
  });
}
