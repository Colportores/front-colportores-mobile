// QA de la casilla «Unión rechazada» (vista 10 «Posibles duplicados», HU-UBI-006, #679): el aviso que
// vuelve arriba de la tarjeta del par cuando el servidor rechazó la unión. Matriz de tamaños
// (360×640 y 412×915) × texto 1,0 y 2,0 con las guías de accesibilidad de Flutter, el contraste medido
// par de colores por par de colores (con las fuentes reales la guía de contraste da falsos negativos),
// lo que lee el lector de pantalla y capturas PNG en `.dart_tool/qa_capturas/` (gitignored).
//
// Los tests con `skip` documentan un hallazgo de QA (`QA #679: …`): el implementador saca el `skip`
// cuando lo arregla.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show ColoresAlta;
import 'package:colportores_mobile/features/mapa/presentation/widgets/textos_posibles_duplicados.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/duplicados_falsos.dart';
import '../../helpers/qa_vista10_arnes.dart';

const _parItalia = 'ub-a|ub-b';
const _parArtigas = 'ub-c|ub-d';

const _textoUb003 =
    'La ubicación que ibas a conservar ya está dada de baja. Revisá el par de nuevo.';
const _textoGenerico =
    'No pudimos unir estas dos ubicaciones. Quedaron separadas, como estaban. Revisá el par de nuevo.';

final _raiz = GlobalKey();

DuplicadosEnMemoria _datos() {
  final datos = DuplicadosEnMemoria();
  datos
    ..agregar(ubicacionDuplicable('ub-a'))
    ..agregar(ubicacionDuplicable('ub-b', metrosAlNorte: 12))
    ..agregar(
      ubicacionDuplicable('ub-c', metrosAlNorte: 1000, calle: 'Bulevar Artigas', numero: '880'),
    )
    ..agregar(
      ubicacionDuplicable('ub-d', metrosAlNorte: 1010, calle: 'Bulevar Artigas', numero: '880'),
    );
  return datos;
}

typedef _Estado = ({String nombre, void Function(DuplicadosEnMemoria) preparar});

final _estados = <_Estado>[
  (nombre: 'ub003', preparar: (d) => d.rechazarUnion(_parItalia, 'UB003')),
  (nombre: 'generico', preparar: (d) => d.rechazarUnion(_parItalia, '42501')),
  (
    nombre: 'dos-avisos',
    preparar: (d) {
      d.rechazarUnion(_parItalia, 'UB003');
      d.rechazarUnion(_parArtigas, 'CG001');
    },
  ),
];

const _tamanos = <(String, Size)>[('360x640', Size(360, 640)), ('412x915', Size(412, 915))];

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos, {
  required Size tamano,
  required double escala,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  await cargarFuentes208(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true),
      child: RepaintBoundary(
        key: _raiz,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('abrir'),
                  onPressed: () =>
                      unawaited(PosiblesDuplicadosPage.abrir(context, colportorId: 'col-1')),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await _asentar(tester);
  await tester.pump(const Duration(seconds: 1));
  await _asentar(tester);
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/679_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}

Finder _aviso(String clave) => find.byKey(Key('union_rechazada_$clave'));

/// Sube la lista hasta que [f] está a la vista (la lista es perezosa).
Future<void> _verAviso(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    300,
    maxScrolls: 100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  for (final (nombreTam, tamano) in _tamanos) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in _estados) {
        final etiqueta = '${estado.nombre} · $nombreTam · texto $escala×';

        _prueba(
          'dado $etiqueta, el aviso se lee entero, sin overflow ni texto fuera de la pantalla',
          (tester) async {
            final datos = _datos();
            estado.preparar(datos);
            await _montar(tester, datos, tamano: tamano, escala: escala);
            await _verAviso(tester, _aviso(_parItalia));

            expect(tester.takeException(), isNull);
            final esperado = estado.nombre == 'ub003' || estado.nombre == 'dos-avisos'
                ? _textoUb003
                : _textoGenerico;
            expect(
              find.descendant(of: _aviso(_parItalia), matching: find.text(esperado)),
              findsOneWidget,
            );
            expectSinTextoFueraDeLosCostados208(tester, tamano);
            // El texto no se corta: el párrafo no tiene más líneas de las que muestra.
            final texto = tester.widget<Text>(
              find.descendant(of: _aviso(_parItalia), matching: find.text(esperado)),
            );
            expect(texto.maxLines, isNull);
            expect(texto.overflow, isNull);
            await _capturar(tester, '${estado.nombre}_${nombreTam}_$escala');
          },
        );

        _prueba('dado $etiqueta, cumple las guías de toque y de etiquetas', (tester) async {
          final datos = _datos();
          estado.preparar(datos);
          await _montar(tester, datos, tamano: tamano, escala: escala);
          await _verAviso(tester, _aviso(_parItalia));
          // El botón «Revisar» a la vista: las guías miden lo que se ve en pantalla.
          await tester.ensureVisible(find.byKey(const Key('revisar_$_parItalia')));
          await tester.pump();

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        });
      }
    }
  }

  group('contraste (WCAG 1.4.3 y 1.4.11), par de colores por par de colores', () {
    const fondoAviso = Color(0xFFFDF1F1);
    test('el texto del aviso (tinta sobre el rosa) llega a 4,5:1', () {
      expect(contraste208(ColoresAlta.tinta, fondoAviso), greaterThanOrEqualTo(4.5));
    });
    test('el «!» blanco sobre el círculo rojo llega a 4,5:1', () {
      expect(contraste208(Colors.white, ColoresAlta.rojo), greaterThanOrEqualTo(4.5));
    });
    test('el borde rojo sobre el blanco de la tarjeta llega a 3:1 (componente gráfico)', () {
      expect(contraste208(ColoresAlta.rojo, Colors.white), greaterThanOrEqualTo(3));
    });
  });

  group('lector de pantalla', () {
    _prueba(
      'dado el aviso, el lector lo lee como un solo texto con el contenido de la HU y sin el «!»',
      (tester) async {
        final manejador = tester.ensureSemantics();
        final datos = _datos()..rechazarUnion(_parItalia, 'UB003');
        await _montar(tester, datos, tamano: const Size(412, 915), escala: 1);

        expect(
          tester.getSemantics(_aviso(_parItalia)),
          matchesSemantics(label: _textoUb003, isLiveRegion: true),
        );
        manejador.dispose();
      },
    );

    _prueba(
      'dado el aviso, el texto de la HU para UB003 es literal y el genérico no nombra el código',
      (tester) async {
        expect(TextosPosiblesDuplicados.avisoUnionRechazada('UB003'), _textoUb003);
        for (final codigo in ['UB004', '42501', 'CG001', '', 'XX999']) {
          final t = TextosPosiblesDuplicados.avisoUnionRechazada(codigo);
          expect(t, _textoGenerico, reason: codigo);
          expect(
            t.contains(codigo) && codigo.isNotEmpty,
            isFalse,
            reason: 'no se muestra el código',
          );
        }
      },
    );

    testWidgets(
      'dado que el rechazo llega con la vista abierta y el lector encendido, el aviso se anuncia '
      '(región viva), como el aviso rojo «quedaron unidas» de la misma pantalla',
      (tester) async {
        final manejador = tester.ensureSemantics();
        final datos = _datos();
        await _montar(tester, datos, tamano: const Size(412, 915), escala: 1);
        expect(_aviso(_parItalia), findsNothing);

        datos.rechazarUnion(_parItalia, 'UB003');
        await _asentar(tester);

        final nodo = tester.getSemantics(_aviso(_parItalia));
        expect(nodo.flagsCollection.isLiveRegion, isTrue);
        manejador.dispose();
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 10));
      },
    );
  });

  group('datos límite', () {
    _prueba(
      'dado muchos pares con aviso a la vez, todos salen con su texto y la lista sigue andando',
      (tester) async {
        final datos = DuplicadosEnMemoria();
        for (var i = 0; i < 12; i++) {
          datos
            ..agregar(ubicacionDuplicable('ub-a$i', metrosAlNorte: i * 1000.0, calle: 'Calle $i'))
            ..agregar(
              ubicacionDuplicable('ub-b$i', metrosAlNorte: i * 1000.0 + 8, calle: 'Calle $i'),
            )
            ..rechazarUnion('ub-a$i|ub-b$i', i.isEven ? 'UB003' : 'CG001');
        }
        await _montar(tester, datos, tamano: const Size(360, 640), escala: 2);

        expect(find.text('12 para revisar'), findsOneWidget);
        for (var i = 0; i < 12; i++) {
          // La lista es perezosa y solo baja: se sube al principio antes de buscar cada aviso.
          await tester.drag(find.byType(Scrollable).first, const Offset(0, 8000));
          await tester.pump();
          await _verAviso(tester, _aviso('ub-a$i|ub-b$i'));
          expect(_aviso('ub-a$i|ub-b$i'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    _prueba('dado el aviso, cuando sale del estado «para revisar» por una decisión, desaparece sin '
        'dejar un hueco ni el texto', (tester) async {
      final datos = _datos()..rechazarUnion(_parItalia, 'UB003');
      await _montar(tester, datos, tamano: const Size(412, 915), escala: 1);
      expect(_aviso(_parItalia), findsOneWidget);

      datos.unionesRechazadas.remove(_parItalia);
      datos.rechazarUnion(_parArtigas, 'CG001');
      await _asentar(tester);

      expect(_aviso(_parItalia), findsNothing);
      expect(find.text(_textoUb003), findsNothing);
      expect(_aviso(_parArtigas), findsOneWidget);
    });
  });
}
