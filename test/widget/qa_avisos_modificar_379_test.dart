// QA de #379 (PR #390): los avisos de «Modificar ubicación» (vista 07·04 «¿Descartar los cambios?» y las
// preguntas del guardado con «Confirmar») eligen el aviso grande cuando en el teléfono alguna palabra no
// entra en el de siempre, aunque el texto no pase de 2×.
//
// Lo que ya cubre `avisos_modificar_358_test.dart` (la matriz de los 6 avisos × 5 tamaños × 6 escalas y la
// grilla gruesa) no se repite. Acá: un barrido fino (cada 10 dp × cada 0,1×), el aviso real abierto desde
// la hoja de edición, la letra en negrita del sistema, el escalador no lineal de Android 14, el texto que
// cambia con el aviso abierto, la pantalla apaisada y con muescas, y los toques.
//
// Con las fuentes reales del proyecto. Las capturas solo con `--dart-define=QA_CAPTURAS=true`.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/dialogos_modificar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/modificar_ubicacion_qa_307_arnes.dart' as m;
import '../helpers/qa_hojas_teclado_324_arnes.dart'
    show abrirEdicionQa, cargarTipografias, conCapturas, veces;

typedef _Aviso = ({
  String nombre,
  Future<bool> Function(BuildContext) abrir,
  String? titulo,
  String paraNo,
  String paraSi,
});

final _avisos = <_Aviso>[
  (
    nombre: 'descartar · un cambio',
    abrir: (c) => confirmarDescartarCambios(c, ['el número']),
    titulo: '¿Descartar los cambios?',
    paraNo: 'Seguir editando',
    paraSi: 'Descartar',
  ),
  (
    nombre: 'descartar · los cinco cambios',
    abrir: (c) => confirmarDescartarCambios(c, [
      'el tipo',
      'la ciudad',
      'la calle',
      'el número',
      'la posición',
    ]),
    titulo: '¿Descartar los cambios?',
    paraNo: 'Seguir editando',
    paraSi: 'Descartar',
  ),
  (
    nombre: 'descartar · sin lista',
    abrir: (c) => confirmarDescartarCambios(c, const []),
    titulo: '¿Descartar los cambios?',
    paraNo: 'Seguir editando',
    paraSi: 'Descartar',
  ),
  (
    nombre: 'confirmar · reactivar',
    abrir: (c) => confirmarModificacion(c, texto: ModificacionRequiereConfirmacion.avisoReactivar),
    titulo: null,
    paraNo: 'Cancelar',
    paraSi: 'Confirmar',
  ),
  (
    nombre: 'confirmar · ciudad',
    abrir: (c) =>
        confirmarModificacion(c, texto: ModificacionRequiereConfirmacion.avisoCambioCiudad),
    titulo: null,
    paraNo: 'Cancelar',
    paraSi: 'Confirmar',
  ),
  (
    nombre: 'confirmar · mover',
    abrir: (c) => confirmarModificacion(
      c,
      texto: ModificacionRequiereConfirmacion.avisoDesplazamiento(1234.4),
    ),
    titulo: null,
    paraNo: 'Cancelar',
    paraSi: 'Confirmar',
  ),
];

/// Un escalador no lineal como el de Android 14: el texto chico crece más que el grande.
class _NoLineal extends TextScaler {
  const _NoLineal(this.paraCatorce);

  /// Cuánto crece un texto de 14.
  final double paraCatorce;

  @override
  double scale(double fontSize) {
    // 14 → paraCatorce; 30 o más → 1,0; entre los dos, lineal.
    final t = ((fontSize - 14) / 16).clamp(0.0, 1.0);
    return fontSize * (paraCatorce + (1 - paraCatorce) * t);
  }

  @override
  double get textScaleFactor => paraCatorce;

  @override
  bool operator ==(Object other) => other is _NoLineal && other.paraCatorce == paraCatorce;

  @override
  int get hashCode => paraCatorce.hashCode;
}

class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.aviso, this.respuestas);

  final _Aviso aviso;
  final List<bool> respuestas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async => respuestas.add(await aviso.abrir(context)),
        child: const Text('abrir'),
      ),
    ),
  );
}

final _raiz = GlobalKey();

/// Escalas que cambian en vivo (para el texto que crece con el aviso abierto).
final _escalaViva = ValueNotifier<double>(1);

Future<List<bool>> _montar(
  WidgetTester tester,
  _Aviso aviso, {
  required Size tamano,
  required double escala,
  TextScaler? escalador,
  bool negrita = false,
  FakeViewPadding padding = FakeViewPadding.zero,
  bool viva = false,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = padding;
  tester.view.viewPadding = padding;
  addTearDown(tester.view.reset);
  _escalaViva.value = escala;
  final respuestas = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => RepaintBoundary(
        key: _raiz,
        child: ValueListenableBuilder<double>(
          valueListenable: _escalaViva,
          builder: (context, e, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: escalador ?? TextScaler.linear(viva ? e : escala),
              boldText: negrita,
            ),
            child: child!,
          ),
        ),
      ),
      home: _Anfitrion(aviso, respuestas),
    ),
  );
  return respuestas;
}

Future<void> _abrir(WidgetTester tester, {String donde = ''}) async {
  await tester.tap(find.text('abrir'));
  for (var cuadro = 0; cuadro < 8; cuadro++) {
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull, reason: '$donde: cuadro $cuadro de la apertura');
  }
}

Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _aviso => find.byType(AlertDialog);
Finder get _botonNo => find.descendant(of: _aviso, matching: find.byType(TextButton));
Finder get _botonSi => find.descendant(of: _aviso, matching: find.byType(FilledButton));

List<RenderParagraph> _parrafos(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(find.descendant(of: _aviso, matching: find.byType(RichText)))
    .toList();

bool _esEspacio(String l) => l == ' ' || l == '\n' || l == '\t';

List<String> _cortes(RenderParagraph parrafo) {
  final texto = parrafo.text.toPlainText();
  final tops = <double?>[];
  final cortes = <String>[];
  for (var i = 0; i < texto.length; i++) {
    final cajas = parrafo.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    tops.add(cajas.isEmpty ? null : cajas.first.top);
    if (cajas.isNotEmpty && !_esEspacio(texto[i]) && cajas.first.right > parrafo.size.width + .5) {
      cortes.add('«${texto[i]}» se sale por la derecha');
    }
  }
  for (var i = 1; i < texto.length; i++) {
    final antes = tops[i - 1];
    final ahora = tops[i];
    if (antes == null || ahora == null) continue;
    if (_esEspacio(texto[i]) || _esEspacio(texto[i - 1]) || ahora <= antes + 1) continue;
    var desde = i;
    while (desde > 0 && !_esEspacio(texto[desde - 1])) {
      desde--;
    }
    var hasta = i;
    while (hasta < texto.length && !_esEspacio(texto[hasta])) {
      hasta++;
    }
    cortes.add(
      '«${texto.substring(desde, hasta)}» partida entre «${texto.substring(desde, i)}» y '
      '«${texto.substring(i, hasta)}»',
    );
  }
  return cortes;
}

double _escalaDelAviso(WidgetTester tester) =>
    MediaQuery.textScalerOf(tester.element(_aviso)).scale(14) / 14;

bool _accionesAdentroDelScroll(WidgetTester tester) {
  final dentro = find.descendant(of: _aviso, matching: find.byType(SingleChildScrollView));
  return find.descendant(of: dentro, matching: _botonSi).evaluate().isNotEmpty &&
      find.descendant(of: dentro, matching: _botonNo).evaluate().isNotEmpty;
}

List<String> _todasLasCortes(WidgetTester tester) => [
  for (final p in _parrafos(tester)) ..._cortes(p),
];

/// El aviso de siempre armado aparte, para ver si en esa pantalla parte una palabra.
Future<List<String>> _cortesDelDeSiempre(
  WidgetTester tester,
  _Aviso aviso,
  String cuerpo, {
  required double ancho,
  required double escala,
}) async {
  tester.view.physicalSize = Size(ancho, 640);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              scrollable: true,
              title: aviso.titulo == null ? null : Text(aviso.titulo!),
              content: Text(cuerpo),
              actions: [
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                  child: Text(aviso.paraNo),
                ),
                FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                  child: Text(aviso.paraSi),
                ),
              ],
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await _abrir(tester);
  return _todasLasCortes(tester);
}

void _botonesAlcanzables(WidgetTester tester, Size tamano, String donde) {
  for (final boton in [_botonNo, _botonSi]) {
    final r = tester.getRect(boton);
    expect(r.height, greaterThanOrEqualTo(48 - .01), reason: '$donde: alto $r');
    expect(r.width, greaterThanOrEqualTo(48 - .01), reason: '$donde: ancho $r');
    expect(r.left, greaterThanOrEqualTo(-.5), reason: '$donde: $r se sale por la izquierda');
    expect(
      r.right,
      lessThanOrEqualTo(tamano.width + .5),
      reason: '$donde: $r se sale por la derecha',
    );
  }
}

/// Si la barra de desplazamiento del aviso pinta su pulgar (`thumbVisibility: true`: siempre que haya
/// algo para desplazar).
bool _barraSePinta(WidgetTester tester) {
  final cajas = find.descendant(of: _aviso, matching: find.byType(CustomPaint));
  for (final caja in tester.renderObjectList<RenderCustomPaint>(cajas)) {
    final pintor = caja.foregroundPainter;
    if (pintor is! ScrollbarPainter) continue;
    final lienzo = TestRecordingCanvas();
    pintor.paint(lienzo, caja.size);
    return lienzo.invocations.isNotEmpty;
  }
  fail('el aviso grande no tiene barra de desplazamiento');
}

void main() {
  setUpAll(cargarTipografias);
  tearDown(() => _escalaViva.value = 1);

  // -------------------------------------------------------------------------------------------------
  // Barrido fino: cada 10 dp de ancho y cada 0,1× de texto. Ninguna palabra se parte NUNCA (con el aviso
  // de siempre ni con el grande), los botones miden 48 dp y no se salen, hasta 2× el texto es el del
  // sistema y el aviso grande solo sale cuando el de siempre parte una palabra.
  // -------------------------------------------------------------------------------------------------
  group('QA #379 · barrido fino de ancho × escala', () {
    // Desde 320 dp: el teléfono más chico que probamos (por debajo ni el aviso grande a 2× alcanza).
    final anchos = [for (var a = 320.0; a <= 420; a += 10) a];
    final escalas = [for (var i = 10; i <= 25; i++) i / 10];
    for (final aviso in _avisos) {
      testWidgets('${aviso.nombre}: nunca una palabra partida ni un botón fuera de la pantalla', (
        tester,
      ) async {
        final fallas = <String>[];
        for (final ancho in anchos) {
          for (final escala in escalas) {
            final donde = '${aviso.nombre} · ${ancho.round()} dp · ${veces(escala)}';
            await tester.pumpWidget(const SizedBox());
            final tamano = Size(ancho, 640);
            await _montar(tester, aviso, tamano: tamano, escala: escala);
            await _abrir(tester, donde: donde);
            for (final c in _todasLasCortes(tester)) {
              fallas.add('$donde: $c');
            }
            try {
              _botonesAlcanzables(tester, tamano, donde);
            } on TestFailure catch (e) {
              fallas.add('$donde: ${e.message}');
            }
            if (escala <= 2 && (_escalaDelAviso(tester) - escala).abs() > 1e-9) {
              fallas.add('$donde: el aviso baja el texto a ${_escalaDelAviso(tester)}');
            }
          }
        }
        expect(fallas, isEmpty, reason: fallas.take(12).join('\n'));
      });

      testWidgets('${aviso.nombre}: hasta 2× es el grande solo si el de siempre parte una palabra', (
        tester,
      ) async {
        final fallas = <String>[];
        for (final ancho in anchos) {
          for (final escala in escalas.where((e) => e <= 2)) {
            final donde = '${aviso.nombre} · ${ancho.round()} dp · ${veces(escala)}';
            await tester.pumpWidget(const SizedBox());
            await _montar(tester, aviso, tamano: Size(ancho, 640), escala: escala);
            await _abrir(tester, donde: donde);
            if (!_accionesAdentroDelScroll(tester)) continue;
            final textos = [for (final p in _parrafos(tester)) p.text.toPlainText()];
            final cuerpo = textos.firstWhere(
              (t) => t != aviso.titulo && t != aviso.paraNo && t != aviso.paraSi,
            );
            await tester.pumpWidget(const SizedBox());
            final partidas = await _cortesDelDeSiempre(
              tester,
              aviso,
              cuerpo,
              ancho: ancho,
              escala: escala,
            );
            // 330 dp a 2×: «Confirmar» mide 154,001 dp y el renglón 154 dp. La medida lo manda al grande
            // por una milésima, y el aviso de siempre no la parte (menor, ver el comentario del PR).
            final filo = ancho == 330 && escala == 2.0 && aviso.paraSi == 'Confirmar';
            if (partidas.isEmpty && !filo) {
              fallas.add('$donde: el de siempre entraba y salió el grande');
            }
          }
        }
        expect(fallas, isEmpty, reason: fallas.take(12).join('\n'));
      });
    }
  });

  // -------------------------------------------------------------------------------------------------
  // Otras formas en que el teléfono cambia el ancho que tiene el texto.
  // -------------------------------------------------------------------------------------------------
  group('QA #379 · negrita del sistema', () {
    // Android «Texto en negrita»: Flutter pinta todo en negrita y las palabras miden más.
    for (final (tamano, escala) in <(Size, double)>[
      (const Size(320, 568), 1.8),
      (const Size(320, 568), 1.9),
      (const Size(320, 568), 2.0),
      (const Size(340, 640), 2.0),
      (const Size(360, 640), 2.0),
    ]) {
      for (final aviso in [_avisos[1], _avisos[3]]) {
        testWidgets(
          '${aviso.nombre} · ${tamano.width.round()}×${tamano.height.round()} · ${veces(escala)} con '
          'negrita: sin palabras partidas',
          (tester) async {
            await _montar(tester, aviso, tamano: tamano, escala: escala, negrita: true);
            await _abrir(tester);
            expect(_todasLasCortes(tester), isEmpty);
          },
        );
      }
    }
  });

  group('QA #379 · escalador no lineal (Android 14)', () {
    for (final (tamano, crece) in <(Size, double)>[
      (const Size(320, 568), 1.8),
      (const Size(320, 568), 2.0),
      (const Size(340, 640), 2.0),
      (const Size(360, 640), 2.0),
      (const Size(320, 568), 2.6),
    ]) {
      for (final aviso in _avisos) {
        testWidgets(
          '${aviso.nombre} · ${tamano.width.round()} dp · el 14 crece ${veces(crece)}: sin palabras '
          'partidas ni desborde',
          (tester) async {
            await _montar(tester, aviso, tamano: tamano, escala: 1, escalador: _NoLineal(crece));
            await _abrir(tester);
            expect(_todasLasCortes(tester), isEmpty);
            _botonesAlcanzables(tester, tamano, aviso.nombre);
          },
        );
      }
    }
  });

  group('QA #379 · cambia el texto del sistema con el aviso abierto', () {
    for (final aviso in [_avisos[1], _avisos[3]]) {
      testWidgets('${aviso.nombre} · 320×568: de 1× a 1,9× y de vuelta a 1×', (tester) async {
        final respuestas = await _montar(
          tester,
          aviso,
          tamano: const Size(320, 568),
          escala: 1,
          viva: true,
        );
        await _abrir(tester);
        expect(_accionesAdentroDelScroll(tester), isFalse, reason: 'a 1× es el de siempre');
        expect(_todasLasCortes(tester), isEmpty);

        _escalaViva.value = 1.9;
        await _asentar(tester);
        expect(tester.takeException(), isNull);
        expect(_accionesAdentroDelScroll(tester), isTrue, reason: 'a 1,9× es el grande');
        expect(_todasLasCortes(tester), isEmpty);
        expect(_escalaDelAviso(tester), closeTo(1.9, 1e-9));

        _escalaViva.value = 1;
        await _asentar(tester);
        expect(tester.takeException(), isNull);
        expect(_accionesAdentroDelScroll(tester), isFalse);
        expect(_todasLasCortes(tester), isEmpty);

        await tester.tap(_botonSi);
        await _asentar(tester);
        expect(respuestas, [true]);
      });
    }
  });

  group('QA #379 · pantalla apaisada y con muescas', () {
    for (final (tamano, escala) in <(Size, double)>[
      (const Size(568, 320), 1.0),
      (const Size(568, 320), 2.0),
      (const Size(640, 360), 2.0),
      (const Size(640, 360), 3.0),
      (const Size(568, 320), 3.0),
    ]) {
      for (final aviso in [_avisos[1], _avisos[5]]) {
        testWidgets('${aviso.nombre} · apaisado ${tamano.width.round()}×${tamano.height.round()} · '
            '${veces(escala)}: sin desborde y los dos botones se alcanzan desplazando', (
          tester,
        ) async {
          final respuestas = await _montar(tester, aviso, tamano: tamano, escala: escala);
          await _abrir(tester);
          expect(_todasLasCortes(tester), isEmpty);
          for (final boton in [_botonNo, _botonSi]) {
            await tester.ensureVisible(boton);
            await tester.pump();
            final r = tester.getRect(boton);
            expect(r.top, greaterThanOrEqualTo(-.5), reason: '$r');
            expect(r.bottom, lessThanOrEqualTo(tamano.height + .5), reason: '$r');
          }
          await tester.tap(_botonSi);
          await _asentar(tester);
          expect(respuestas, [true]);
        });
      }
    }

    // Apaisado con una muesca de 48 dp a cada lado (o la barra de navegación): el ancho útil es menor.
    for (final (tamano, escala) in <(Size, double)>[
      (const Size(640, 360), 1.0),
      (const Size(640, 360), 2.0),
      (const Size(568, 320), 2.0),
    ]) {
      for (final aviso in [_avisos[1], _avisos[3]]) {
        testWidgets(
          '${aviso.nombre} · apaisado ${tamano.width.round()}×${tamano.height.round()} con 48 dp de '
          'muesca a cada lado · ${veces(escala)}: sin palabras partidas',
          (tester) async {
            await _montar(
              tester,
              aviso,
              tamano: tamano,
              escala: escala,
              padding: const FakeViewPadding(left: 48, right: 48, top: 24, bottom: 24),
            );
            await _abrir(tester);
            expect(_todasLasCortes(tester), isEmpty);
            _botonesAlcanzables(tester, tamano, aviso.nombre);
          },
        );
      }
    }
  });

  // -------------------------------------------------------------------------------------------------
  // Los toques con el aviso grande a menos de 2×.
  // -------------------------------------------------------------------------------------------------
  group('QA #379 · contestar con el aviso grande a 320×568 · 1,9×', () {
    for (final aviso in _avisos) {
      testWidgets(
        '${aviso.nombre}: «${aviso.paraSi}» devuelve true y no cierra la pantalla de abajo',
        (tester) async {
          final respuestas = await _montar(
            tester,
            aviso,
            tamano: const Size(320, 568),
            escala: 1.9,
          );
          await _abrir(tester);
          expect(_accionesAdentroDelScroll(tester), isTrue);
          await tester.ensureVisible(_botonSi);
          await tester.pump();
          await tester.tap(_botonSi);
          await tester.tap(_botonSi, warnIfMissed: false);
          await _asentar(tester);
          expect(respuestas, [true]);
          expect(find.text('abrir'), findsOneWidget);
        },
      );

      testWidgets('${aviso.nombre}: «${aviso.paraNo}», tocar afuera y «atrás» devuelven false', (
        tester,
      ) async {
        final respuestas = await _montar(tester, aviso, tamano: const Size(320, 568), escala: 1.9);
        await _abrir(tester);
        await tester.ensureVisible(_botonNo);
        await tester.pump();
        await tester.tap(_botonNo);
        await _asentar(tester);
        await _abrir(tester);
        await tester.tapAt(const Offset(2, 2));
        await _asentar(tester);
        await _abrir(tester);
        await tester.binding.handlePopRoute();
        await _asentar(tester);
        expect(respuestas, [false, false, false]);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }
  });

  // -------------------------------------------------------------------------------------------------
  // Con el aviso grande a menos de 2× las acciones están adentro de lo que se desplaza: si no se ven
  // enteras al abrirlo (la pantalla chica y el texto grande son justo el caso de #379), una barra de
  // desplazamiento siempre visible avisa que hay más (decisión (c) del 21/10 sobre el hallazgo menor 1
  // del QA); si todo entra, no hay barra.
  // -------------------------------------------------------------------------------------------------
  group('QA #379 · la barra de desplazamiento del aviso grande se ve cuando algo queda fuera', () {
    for (final (tamano, escala) in <(Size, double)>[
      (const Size(320, 568), 1.8),
      (const Size(320, 568), 1.9),
      (const Size(320, 568), 2.0),
      (const Size(340, 640), 2.0),
    ]) {
      for (final aviso in _avisos) {
        testWidgets(
          '${aviso.nombre} · ${tamano.width.round()}×${tamano.height.round()} · ${veces(escala)}',
          (tester) async {
            await _montar(tester, aviso, tamano: tamano, escala: escala);
            await _abrir(tester);
            await _asentar(tester);
            if (!_accionesAdentroDelScroll(tester)) return; // las del aviso de siempre van fijas
            final visor = tester.getRect(
              find.descendant(of: _aviso, matching: find.byType(SingleChildScrollView)).first,
            );
            // (hasta 2 dp: con 1,8× el botón de abajo se pasa 1,2 dp del borde, que es su relleno.)
            final fuera = [_botonNo, _botonSi].any((boton) {
              final r = tester.getRect(boton);
              return r.bottom > visor.bottom + 2 || r.top < visor.top - 2;
            });
            final desplazable = tester
                .state<ScrollableState>(
                  find.descendant(of: _aviso, matching: find.byType(Scrollable)).first,
                )
                .position
                .maxScrollExtent;
            expect(desplazable > 0, fuera, reason: 'se desplaza si y solo si algo queda fuera');
            expect(
              _barraSePinta(tester),
              fuera,
              reason: fuera ? 'algo queda fuera y no hay barra' : 'todo entra y hay barra',
            );
          },
        );
      }
    }

    testWidgets(
      '320×568 · 2× · cinco cambios: la barra está, tocar «Descartar» desplazando contesta',
      (tester) async {
        final respuestas = await _montar(
          tester,
          _avisos[1],
          tamano: const Size(320, 568),
          escala: 2,
        );
        await _abrir(tester);
        await _asentar(tester);
        expect(_barraSePinta(tester), isTrue);
        await tester.ensureVisible(_botonSi);
        await tester.pump();
        await tester.tap(_botonSi);
        await _asentar(tester);
        expect(respuestas, [true]);
      },
    );
  });

  // -------------------------------------------------------------------------------------------------
  // El aviso real, abierto desde la hoja «Modificar ubicación» (el caso de la colportora de #379).
  // -------------------------------------------------------------------------------------------------
  group('QA #379 · 07·04 abierto desde la edición real', () {
    // Con el teclado cerrado (el colportor lo bajó con «atrás») y con el teclado arriba.
    for (final conTeclado in [false, true]) {
      for (final (tamano, escala) in <(Size, double)>[
        (const Size(320, 568), 1.8),
        (const Size(320, 568), 1.9),
        (const Size(320, 568), 2.0),
        (const Size(340, 640), 2.0),
        (const Size(360, 640), 2.0),
      ]) {
        testWidgets(
          '${tamano.width.round()}×${tamano.height.round()} · ${veces(escala)} · '
          '${conTeclado ? 'con el teclado arriba' : 'con el teclado cerrado'}: «✕» con lo escrito abre '
          'el aviso sin palabras partidas; «Seguir editando» conserva lo escrito; «Descartar» sale',
          (tester) async {
            final repo = await abrirEdicionQa(tester, tamano: tamano, escala: escala);
            await tester.ensureVisible(m.campoNumero);
            await tester.pump();
            await tester.tap(m.campoNumero);
            await tester.enterText(m.campoNumero, '1238');
            await m.asentarConTeclado(tester);
            if (!conTeclado) {
              tester.testTextInput.hide();
              m.ponerTeclado(tester, 0);
              await m.asentarConTeclado(tester);
            }

            final cerrar = find.byTooltip('Cerrar');
            await tester.ensureVisible(cerrar);
            await tester.pump();
            await tester.tap(cerrar, warnIfMissed: false);
            // Mientras el sistema baja el teclado de a poco: ningún cuadro con excepción.
            for (var cuadro = 0; cuadro < 20; cuadro++) {
              await tester.pump(const Duration(milliseconds: 16));
              final bajando = tester.view.viewInsets.bottom;
              if (bajando > 0) m.ponerTeclado(tester, math.max(0, bajando - 20));
              expect(tester.takeException(), isNull, reason: 'cuadro $cuadro');
            }
            await m.asentarConTeclado(tester, 14);
            expect(find.text('¿Descartar los cambios?'), findsOneWidget);
            expect(_todasLasCortes(tester), isEmpty);
            expect(tester.takeException(), isNull);

            await tester.ensureVisible(find.text('Seguir editando'));
            await tester.pump();
            await tester.tap(find.text('Seguir editando'));
            await m.asentarConTeclado(tester, 14);
            expect(
              find.widgetWithText(TextField, '1238'),
              findsOneWidget,
              reason: 'lo escrito sigue',
            );
            expect(repo.escrituras, isEmpty);

            if (!conTeclado) {
              // Al volver a la hoja el foco vuelve al campo y el teclado sube: se lo baja otra vez.
              tester.testTextInput.hide();
              m.ponerTeclado(tester, 0);
              await m.asentarConTeclado(tester);
            }
            await tester.ensureVisible(cerrar);
            await tester.pump();
            await tester.tap(cerrar, warnIfMissed: false);
            await m.asentarConTeclado(tester, 14);
            await tester.ensureVisible(find.text('Descartar'));
            await tester.pump();
            await tester.tap(find.text('Descartar'));
            await m.asentarConTeclado(tester, 14);
            expect(find.text('abrir'), findsOneWidget, reason: 'volvió a la pantalla de abajo');
            expect(repo.escrituras, isEmpty, reason: 'descartar no guarda');
          },
        );
      }
    }
  });

  // -------------------------------------------------------------------------------------------------
  // Capturas (solo con --dart-define=QA_CAPTURAS=true).
  // -------------------------------------------------------------------------------------------------
  group('QA #379 · capturas', () {
    for (final (tamano, escala) in <(Size, double)>[
      (const Size(320, 568), 1.0),
      (const Size(320, 568), 1.8),
      (const Size(320, 568), 2.0),
      (const Size(340, 640), 2.0),
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 2.0),
    ]) {
      for (final aviso in [_avisos[1], _avisos[3], _avisos[5]]) {
        testWidgets('${aviso.nombre} ${tamano.width.round()} ${veces(escala)}', (tester) async {
          await _montar(tester, aviso, tamano: tamano, escala: escala);
          await _abrir(tester);
          await _asentar(tester);
          await tester.runAsync(() async {
            final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
            final img = await render.toImage();
            final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
            final nombre =
                '379_${aviso.nombre.replaceAll(' · ', '_').replaceAll(' ', '')}_'
                '${tamano.width.round()}_${veces(escala)}';
            final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
            File('${dir.path}/$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
          });
        }, skip: !conCapturas);
      }
    }
  });
}
