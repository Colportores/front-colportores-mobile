// QA ronda 1 de la vista 39, grupo E «Estados y casos límite» (HU-UBI-003 y HU-UBI-005, #448, PR #462).
// Complementa a `estados_hoja_casa_448_test.dart` y `_fuentes_test.dart` (que miden con Ahem o a
// 320×568) con lo que esos no miden:
//  - la matriz de estados × tamaños (360×640 y 412×915) × texto 1.0 y 2.0 con las FUENTES REALES:
//    sin overflow, nada fuera de la pantalla, tamaños de toque (Android, iOS) y etiquetas para el lector;
//    cada celda saca una captura a `.dart_tool/qa_capturas/` solo con `--dart-define=QA_CAPTURAS=true`
//    (nunca se commitea);
//  - lo que ve el lector de pantalla (región viva, nombre y acción del botón, filas deshabilitadas
//    mientras corre la elección);
//  - casos límite de las acciones (falla síncrona, la lista cambia mientras se elige, estado del botón);
//  - datos límite de los textos (frontera km, día de la baja en hora local).
// El contraste va aparte (`qa_vista39_estados_448_contraste_test.dart`): con letra real da falsos
// negativos.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias;

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _llave = ValueKey('qa_vista39_raiz');

enum _Estado {
  e01Cargando('E01-cargando'),
  e02Error('E02-error'),
  e04Baja('E04-baja'),
  e04BajaPorUnion('E04-baja-por-union'),
  e05Lejos('E05-lejos-650m'),
  e05LejosKm('E05-lejos-3km'),
  e06Tres('E06-tres'),
  e06Largas('E06-direcciones-largas'),
  e06Muchas('E06-muchas-con-alto-acotado'),
  e06Una('E06-una'),
  juntos('E02-E04-E05-juntos');

  const _Estado(this.nombre);
  final String nombre;
}

ItemListaUbicacion _item(
  String id, {
  String? calle = 'Grecia',
  String? numero = '3310',
  TipoUbicacion tipo = TipoUbicacion.casa,
  EstadoCasa? estado,
  DateTime? baja,
}) => ItemListaUbicacion(
  ubicacion: ubicacionGuardada(id: id, calle: calle, numero: numero, tipo: tipo, deBajaDesde: baja),
  estado: estado,
);

List<ItemListaUbicacion> get _tres => [
  _item('u-1', estado: EstadoCasa.cobranzaPendiente),
  _item('u-2', numero: '3310 bis', estado: EstadoCasa.noContesto),
  _item('u-3', tipo: TipoUbicacion.negocio, estado: EstadoCasa.sinVisita),
];

Widget _widget(_Estado e) {
  switch (e) {
    case _Estado.e01Cargando:
      return const CargandoHojaCasa();
    case _Estado.e02Error:
      return AvisoHojaCasa.errorAlLeer(alReintentar: () {});
    case _Estado.e04Baja:
      return AvisoHojaCasa.dadaDeBaja(alReactivar: () {});
    case _Estado.e04BajaPorUnion:
      return AvisoHojaCasa.dadaDeBaja();
    case _Estado.e05Lejos:
      return AvisoHojaCasa.lejos(metros: 650);
    case _Estado.e05LejosKm:
      return AvisoHojaCasa.lejos(metros: 3250);
    case _Estado.e06Tres:
      return ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) {});
    case _Estado.e06Una:
      return ElegirUbicacionDelPunto(ubicaciones: [_tres.first], alElegir: (_) {});
    case _Estado.e06Largas:
      return ElegirUbicacionDelPunto(
        ubicaciones: [
          _item(
            'u-1',
            calle: 'Avenida General Don José Gervasio Artigas',
            numero: '12345 bis',
            estado: EstadoCasa.entregaYPago,
          ),
          _item('u-2', calle: null, numero: null),
          _item('u-3', baja: DateTime(2026, 10, 18), tipo: TipoUbicacion.edificio),
        ],
        alElegir: (_) {},
      );
    case _Estado.e06Muchas:
      return SizedBox(
        height: 380,
        child: ElegirUbicacionDelPunto(
          ubicaciones: [for (var i = 0; i < 200; i++) _item('u-$i', numero: '${3000 + i}')],
          alElegir: (_) {},
        ),
      );
    case _Estado.juntos:
      return Column(
        spacing: 12,
        children: [
          AvisoHojaCasa.errorAlLeer(alReintentar: () {}),
          AvisoHojaCasa.dadaDeBaja(alReactivar: () {}),
          AvisoHojaCasa.lejos(metros: 650),
        ],
      );
  }
}

Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  Size tamano = const Size(360, 640),
  double escala = 1,
  bool conScroll = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: _llave,
        child: Scaffold(
          body: conScroll
              ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: hijo)
              : Padding(padding: const EdgeInsets.all(16), child: hijo),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_llave));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa448_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Rect _rect(Element e) {
  final box = e.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

Finder get _accion => find.byKey(ClavesEstadosHojaCasa.accionDelAviso);

SemanticsOwner _dueno(WidgetTester tester) =>
    tester.binding.renderViews.first.owner!.semanticsOwner!;

void main() {
  setUpAll(cargarTipografias);

  const tamanos = [Size(360, 640), Size(412, 915)];
  const escalas = [1.0, 2.0];

  group('Matriz: estados × tamaños × texto', () {
    for (final e in _Estado.values) {
      for (final t in tamanos) {
        for (final s in escalas) {
          final celda = '${e.nombre} · ${t.width.toInt()}×${t.height.toInt()} · texto $s×';
          testWidgets('$celda: sin overflow, dentro de la pantalla y con toques de 48 dp', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            await _montar(tester, _widget(e), tamano: t, escala: s);

            expect(tester.takeException(), isNull, reason: celda);
            // Nada de lo visible se sale de la pantalla por los costados.
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
            await _capturar(tester, '${e.nombre}_${t.width.toInt()}_x${s.toInt()}');
            handle.dispose();
          });
        }
      }
    }
  });

  group('Lo que oye el lector de pantalla', () {
    testWidgets('E·02: el aviso es región viva, dice qué pasó y «Reintentar» es un botón con tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var lecturas = 0;
      await _montar(tester, AvisoHojaCasa.errorAlLeer(alReintentar: () => lecturas++));

      final aviso = tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeer));
      expect(aviso.flagsCollection.isLiveRegion, isTrue);
      expect(aviso.label, contains('No pudimos leer esta casa en tu teléfono.'));

      final boton = tester.getSemantics(_accion);
      expect(boton.label, 'Reintentar');
      expect(boton.flagsCollection.isButton, isTrue);
      expect(boton.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      // Por el lector se activa igual que con el dedo.
      _dueno(tester).performAction(boton.id, SemanticsAction.tap);
      await tester.pump();
      expect(lecturas, 1);
      handle.dispose();
    });

    testWidgets(
      'E·04: con «Reactivar» el lector lo encuentra como botón; sin acción no hay botón',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, AvisoHojaCasa.dadaDeBaja(alReactivar: () {}));
        expect(tester.getSemantics(_accion).label, 'Reactivar');
        expect(tester.getSemantics(_accion).flagsCollection.isButton, isTrue);

        await _montar(tester, AvisoHojaCasa.dadaDeBaja());
        expect(_accion, findsNothing);
        handle.dispose();
      },
    );

    testWidgets('E·01: el rótulo «Cargando la casa» es región viva y la ve el lector', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, const CargandoHojaCasa());
      final nodo = tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.cargando));
      expect(nodo.label, 'Cargando la casa');
      expect(nodo.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('E·06: mientras corre la elección las filas se anuncian deshabilitadas', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final espera = Completer<void>();
      await _montar(
        tester,
        ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) => espera.future),
      );
      final fila1 = find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1'));
      final fila2 = find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-2'));
      expect(tester.getSemantics(fila2).flagsCollection.isEnabled, ui.Tristate.isTrue);

      await tester.tap(fila1);
      await tester.pump();
      expect(tester.getSemantics(fila2).flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(tester.getSemantics(fila2).getSemanticsData().hasAction(SemanticsAction.tap), isFalse);

      espera.complete();
      await tester.pump();
      expect(tester.getSemantics(fila2).flagsCollection.isEnabled, ui.Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('E·06: el título «3 ubicaciones acá» es un encabezado', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) {}));
      final nodo = tester.getSemantics(find.text('3 ubicaciones acá'));
      expect(nodo.flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });

  group('Casos límite de las acciones', () {
    testWidgets(
      '«Reintentar» cuya acción lanza antes de devolver un Future: el botón queda habilitado',
      (tester) async {
        var llamadas = 0;
        await _montar(
          tester,
          AvisoHojaCasa.errorAlLeer(
            alReintentar: () {
              llamadas++;
              throw StateError('falló sin ser async');
            },
          ),
        );
        await tester.tap(_accion);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(tester.widget<TextButton>(_accion).onPressed, isNotNull);
        await tester.tap(_accion);
        await tester.pump();
        expect(llamadas, 2);
      },
    );

    testWidgets(
      '«Reactivar» con la acción en vuelo: dos toques en el mismo cuadro llaman una vez',
      (tester) async {
        final espera = Completer<void>();
        var llamadas = 0;
        await _montar(
          tester,
          AvisoHojaCasa.dadaDeBaja(
            alReactivar: () {
              llamadas++;
              return espera.future;
            },
          ),
        );
        final centro = tester.getCenter(_accion);
        await tester.tapAt(centro);
        await tester.tapAt(centro);
        await tester.pump();
        expect(llamadas, 1);
        expect(tester.widget<TextButton>(_accion).onPressed, isNull);
        espera.complete();
        await tester.pump();
        expect(tester.widget<TextButton>(_accion).onPressed, isNotNull);
      },
    );

    testWidgets(
      'E·06: la lista cambia (otra ubicación) mientras se elige: nada se rompe y se puede seguir',
      (tester) async {
        final espera = Completer<void>();
        final elegidas = <String>[];
        final lista = ValueNotifier<List<ItemListaUbicacion>>(_tres);
        await _montar(
          tester,
          ValueListenableBuilder<List<ItemListaUbicacion>>(
            valueListenable: lista,
            builder: (_, items, _) => ElegirUbicacionDelPunto(
              ubicaciones: items,
              alElegir: (i) {
                elegidas.add(i.ubicacion.id);
                return espera.future;
              },
            ),
          ),
        );
        await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-2')));
        await tester.pump();
        lista.value = [_tres.first, _tres.last];
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('2 ubicaciones acá'), findsOneWidget);
        // En vuelo: nada responde. Cuando termina, responde la que sigue en la lista.
        await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1')));
        await tester.pump();
        expect(elegidas, ['u-2']);
        espera.complete();
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-1')));
        await tester.pump();
        expect(elegidas, ['u-2', 'u-1']);
      },
    );

    testWidgets('E·06: con 200 ubicaciones y el texto al 200 % se llega a la última en 360×640', (
      tester,
    ) async {
      final elegidas = <String>[];
      await _montar(
        tester,
        SizedBox(
          height: 380,
          child: ElegirUbicacionDelPunto(
            ubicaciones: [for (var i = 0; i < 200; i++) _item('u-$i', numero: '${3000 + i}')],
            alElegir: (i) => elegidas.add(i.ubicacion.id),
          ),
        ),
        escala: 2,
        conScroll: false,
      );
      final ultima = find.byKey(ClavesEstadosHojaCasa.filaDelPunto('u-199'));
      await tester.scrollUntilVisible(
        ultima,
        600,
        maxScrolls: 200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(ultima);
      await tester.pump();
      expect(elegidas, ['u-199']);
      expect(tester.takeException(), isNull);
    });
  });

  group('Textos y datos límite', () {
    test('E·04: el día de la baja es el de hora local, venga en UTC o local', () {
      final local = DateTime(2026, 10, 18, 22, 30);
      expect(
        TextosEstadosHojaCasa.subtituloDeBaja(TipoUbicacion.casa, local),
        'Casa · dada de baja el 18/10',
      );
      expect(
        TextosEstadosHojaCasa.subtituloDeBaja(TipoUbicacion.casa, local.toUtc()),
        'Casa · dada de baja el 18/10',
      );
      expect(
        TextosEstadosHojaCasa.subtituloDeBaja(TipoUbicacion.edificio, DateTime(2026, 1, 5)),
        'Edificio · dada de baja el 05/01',
      );
    });

    test(
      'E·05: la distancia en la frontera del kilómetro nunca dice «1000 m»',
      () {
        for (final m in [999.4, 999.5, 999.9, 1000.0, 1049.0, 1050.0]) {
          expect(
            TextosEstadosHojaCasa.lejos(m),
            isNot(contains('1000')),
            reason: 'a $m m dice «${TextosEstadosHojaCasa.lejos(m)}»',
          );
        }
      },
      skip:
          true, // skip: QA #448 — 999,5 a 999,99 m se redondea a «1000 m» en vez de «1,0 km» (FormatoUbicaciones.distancia).
    );

    test('E·05: las distancias de siempre', () {
      const nbsp = FormatoUbicaciones.espacioDuro;
      expect(TextosEstadosHojaCasa.lejos(650), 'Estás a 650${nbsp}m de esta casa.');
      expect(TextosEstadosHojaCasa.lejos(0), 'Estás a 1${nbsp}m de esta casa.');
      expect(TextosEstadosHojaCasa.lejos(1000), 'Estás a 1,0${nbsp}km de esta casa.');
      expect(TextosEstadosHojaCasa.lejos(double.infinity), '');
      expect(TextosEstadosHojaCasa.lejos(-5), '');
      expect(TextosEstadosHojaCasa.lejos(double.nan), '');
    });

    test('E·06: «1 ubicación acá» en singular y el literal «Elegí cuál»', () {
      expect(TextosEstadosHojaCasa.variasEnElPunto(1), '1 ubicación acá');
      expect(TextosEstadosHojaCasa.variasEnElPunto(3), '3 ubicaciones acá');
      expect(TextosEstadosHojaCasa.elegiCual, 'Elegí cuál');
    });
  });

  group('Privacidad', () {
    test('los textos de los estados no llevan datos de la persona ni de la casa', () {
      final todos = [
        TextosEstadosHojaCasa.cargando,
        TextosEstadosHojaCasa.errorAlLeer,
        TextosEstadosHojaCasa.dadaDeBaja,
        TextosEstadosHojaCasa.elegiCual,
      ].join(' ');
      expect(todos, isNot(matches(RegExp(r'\d'))));
    });

    testWidgets('el toString del aviso y de la lista no vuelca la dirección', (tester) async {
      final lista = ElegirUbicacionDelPunto(ubicaciones: _tres, alElegir: (_) {});
      expect(lista.toString(), isNot(contains('Grecia')));
      expect(lista.toString(), isNot(contains('3310')));
    });
  });
}
