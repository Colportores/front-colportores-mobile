// #358 (seguimiento de #355): los dos avisos de «Modificar ubicación» (vista 07·04 «¿Descartar los
// cambios?» y las preguntas del guardado: reactivar, cambiar la ciudad, mover más de 100 m) con el texto
// del sistema al máximo y el teclado subiendo o bajando.
//
// Con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado y las palabras no se
// parten como en el teléfono). Hasta el 200 % el aviso es el de siempre; con más, ocupa casi todo el
// ancho, lleva las dos acciones adentro de lo que se desplaza y limita su texto al mayor tamaño en el
// que ninguna palabra se parte, sin bajar de 2×.
//
// #379 (seguimiento): en un teléfono de 320–340 dp el aviso de siempre ya parte «¿Descartar» o
// «Confirmar» con el texto entre 1,8× y 2×. El aviso grande entra también ahí, cuando alguna palabra no
// entra en el de siempre; donde todo entra, el aviso es el de siempre.
import 'dart:math' as math;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/dialogos_modificar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/modificar_ubicacion_qa_307_arnes.dart' show ponerTeclado;
import '../helpers/qa_hojas_teclado_324_arnes.dart'
    show capturarEn, cargarTipografias, conCapturas, telefonoMinimo, telefonos, veces;

/// Un aviso a probar: cómo se abre y qué dicen sus dos botones.
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
    nombre: 'descartar · sin lista de cambios',
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
    nombre: 'confirmar · cambiar la ciudad',
    abrir: (c) =>
        confirmarModificacion(c, texto: ModificacionRequiereConfirmacion.avisoCambioCiudad),
    titulo: null,
    paraNo: 'Cancelar',
    paraSi: 'Confirmar',
  ),
  (
    nombre: 'confirmar · mover el punto',
    abrir: (c) => confirmarModificacion(
      c,
      texto: ModificacionRequiereConfirmacion.avisoDesplazamiento(1234.4),
    ),
    titulo: null,
    paraNo: 'Cancelar',
    paraSi: 'Confirmar',
  ),
];

final _descartarCinco = _avisos[1];

/// Un teléfono de 340 dp: el aviso de siempre parte «¿Descartar» a 2× (#379).
const _telefono340 = (nombre: '340×640', tamano: Size(340, 640), teclado: 300.0);

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

/// La raíz de las capturas (solo con `--dart-define=QA_CAPTURAS=true`).
final _raiz = GlobalKey();

/// Monta la pantalla de partida a [tamano] con el texto del sistema a [escala] y, sin abrir el aviso,
/// lo deja listo para tocar «abrir».
Future<List<bool>> _montar(
  WidgetTester tester,
  _Aviso aviso, {
  required Size tamano,
  required double escala,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final respuestas = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => RepaintBoundary(
        key: _raiz,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
      ),
      home: _Anfitrion(aviso, respuestas),
    ),
  );
  return respuestas;
}

/// El aviso de siempre (`AlertDialog` con las acciones fijas, como el de 1× de #358) armado aparte con
/// los textos de [aviso], abierto, para ver si en esa pantalla parte alguna palabra.
Future<void> _montarDeSiempre(
  WidgetTester tester,
  _Aviso aviso,
  String cuerpo, {
  required double ancho,
  required double escala,
}) async {
  tester.view.physicalSize = Size(ancho, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
}

/// Deja que terminen las animaciones: la del aviso al abrirse o cerrarse y la del `Dialog` al seguir al
/// teclado (`AnimatedPadding` arranca en el cuadro siguiente al cambio, no en el mismo).
Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Toca «abrir» y deja correr la transición del aviso, mirando que ningún cuadro tire una excepción.
Future<void> _abrir(WidgetTester tester, {String donde = ''}) async {
  await tester.tap(find.text('abrir'));
  for (var cuadro = 0; cuadro < 14; cuadro++) {
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull, reason: '$donde: cuadro $cuadro de la apertura');
  }
}

/// Lo que hace el sistema al abrir el aviso con el teclado arriba: lo baja de a [paso] dp por cuadro.
/// Ningún cuadro, con el aviso armado con el alto de ese momento, puede tirar una excepción.
Future<void> _bajarTeclado(WidgetTester tester, {double paso = 20, String donde = ''}) async {
  for (var cuadro = 0; cuadro < 40; cuadro++) {
    final actual = tester.view.viewInsets.bottom;
    if (actual <= 0) break;
    ponerTeclado(tester, math.max(0, actual - paso));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      tester.takeException(),
      isNull,
      reason: '$donde: cuadro $cuadro, teclado ${tester.view.viewInsets.bottom.round()} dp',
    );
  }
  await _asentar(tester);
  expect(tester.takeException(), isNull, reason: '$donde: asentado');
}

Finder get _aviso => find.byType(AlertDialog);

Finder get _botonNo => find.descendant(of: _aviso, matching: find.byType(TextButton));

Finder get _botonSi => find.descendant(of: _aviso, matching: find.byType(FilledButton));

/// Todos los textos del aviso, tal como los pinta Flutter.
List<RenderParagraph> _parrafos(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(find.descendant(of: _aviso, matching: find.byType(RichText)))
    .toList();

bool _esEspacio(String letra) => letra == ' ' || letra == '\n' || letra == '\t';

/// Las palabras que [parrafo] parte por dentro (una letra cae en otro renglón que la de antes sin un
/// espacio entre las dos) y las letras que quedan fuera de su caja por la derecha.
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

/// Cuánto agranda el texto el propio aviso (con el tope ya puesto).
double _escalaDelAviso(WidgetTester tester) =>
    MediaQuery.textScalerOf(tester.element(_aviso)).scale(14) / 14;

/// Si las dos acciones están adentro de lo que se desplaza.
bool _accionesAdentroDelScroll(WidgetTester tester) {
  final dentro = find.descendant(of: _aviso, matching: find.byType(SingleChildScrollView));
  return find.descendant(of: dentro, matching: _botonSi).evaluate().isNotEmpty &&
      find.descendant(of: dentro, matching: _botonNo).evaluate().isNotEmpty;
}

void main() {
  setUpAll(cargarTipografias);

  final cuerpos = [...telefonos, _telefono340, telefonoMinimo];

  group('Avisos de «Modificar ubicación» (#358)', () {
    for (final aviso in _avisos) {
      for (final t in cuerpos) {
        for (final escala in [1.0, 1.8, 1.9, 2.0, 2.5, 3.0]) {
          final donde = '${aviso.nombre} · ${t.nombre} · ${veces(escala)}';

          testWidgets(
            '$donde: sin desborde con el teclado bajando, sin palabras partidas, acciones al '
            'alcance',
            (tester) async {
              final respuestas = await _montar(tester, aviso, tamano: t.tamano, escala: escala);
              // El teclado está arriba cuando se toca «abrir» y el sistema lo baja de a poco.
              ponerTeclado(tester, t.teclado);
              await _abrir(tester, donde: donde);
              await _bajarTeclado(tester, donde: donde);
              expect(find.text(aviso.paraNo), findsOneWidget, reason: donde);

              // Sin palabras cortadas ni partidas por dentro, en el título, el cuerpo y los botones.
              for (final parrafo in _parrafos(tester)) {
                expect(
                  _cortes(parrafo),
                  isEmpty,
                  reason: '$donde: «${parrafo.text.toPlainText()}»',
                );
              }

              // Los dos botones miden 48 dp como mínimo.
              for (final boton in [_botonNo, _botonSi]) {
                final r = tester.getRect(boton);
                // (con un margen de 0,01 dp: la altura de un botón a 1,8× sale 47,99999999999994.)
                expect(r.height, greaterThanOrEqualTo(48 - .01), reason: '$donde: $r');
                expect(r.width, greaterThanOrEqualTo(48 - .01), reason: '$donde: $r');
              }

              // Con el teclado otra vez arriba (300 dp) los dos botones se alcanzan.
              ponerTeclado(tester, t.teclado);
              await _asentar(tester);
              expect(tester.takeException(), isNull, reason: '$donde: con el teclado arriba');
              final libre = t.tamano.height - t.teclado;
              for (final boton in [_botonNo, _botonSi]) {
                await tester.ensureVisible(boton);
                await tester.pump();
                final r = tester.getRect(boton);
                expect(r.top, greaterThanOrEqualTo(0), reason: '$donde: $r');
                expect(r.bottom, lessThanOrEqualTo(libre + .5), reason: '$donde: $r');
              }

              // Y contestan: «no» devuelve false, «sí» devuelve true.
              await tester.tap(_botonNo);
              await _asentar(tester);
              expect(respuestas, [false], reason: donde);
              expect(find.byType(AlertDialog), findsNothing, reason: donde);
            },
          );
        }
      }
    }

    // El aviso de siempre hasta el 200 %: acciones fijas al pie y el texto como lo manda el sistema; con
    // más, las acciones van adentro de lo que se desplaza y el texto no crece por encima del sistema.
    for (final aviso in _avisos) {
      for (final t in telefonos) {
        for (final escala in [1.0, 1.5, 2.0, 2.5, 3.0]) {
          final grande = escala > 2;
          testWidgets(
            '${aviso.nombre} · ${t.nombre} · ${veces(escala)}: ${grande ? 'acciones adentro de lo que '
                      'se desplaza' : 'acciones fijas al pie, igual que antes'}',
            (tester) async {
              await _montar(tester, aviso, tamano: t.tamano, escala: escala);
              await _abrir(tester);
              expect(_accionesAdentroDelScroll(tester), grande);
              final del = _escalaDelAviso(tester);
              if (grande) {
                expect(del, inInclusiveRange(2, escala + 1e-9));
              } else {
                expect(del, closeTo(escala, 1e-9), reason: 'hasta 2× el texto es el del sistema');
                // El ancho del aviso de siempre: los 40 dp de margen del `Dialog`.
                final ancho = tester
                    .getSize(
                      find.descendant(of: _aviso, matching: find.byType(IntrinsicWidth)).first,
                    )
                    .width;
                expect(ancho, lessThanOrEqualTo(t.tamano.width - 80 + .5));
              }
            },
          );
        }
      }
    }

    group('el aviso grande entra desde que una palabra no entra en el de siempre (#379)', () {
      // A 360 dp o más, con 1× y con 2×, el aviso es el de siempre, como hoy.
      for (final aviso in _avisos) {
        for (final ancho in [360.0, 380.0, 412.0, 480.0]) {
          for (final escala in [1.0, 2.0]) {
            testWidgets(
              '${aviso.nombre} · ${ancho.round()} dp · ${veces(escala)}: el aviso de siempre',
              (tester) async {
                await _montar(tester, aviso, tamano: Size(ancho, 640), escala: escala);
                await _abrir(tester);
                expect(_accionesAdentroDelScroll(tester), isFalse);
                expect(_escalaDelAviso(tester), closeTo(escala, 1e-9));
                for (final parrafo in _parrafos(tester)) {
                  expect(_cortes(parrafo), isEmpty);
                }
              },
            );
          }
        }
      }

      // El caso de la colportora: 1,8× en 320×568 (y 1,9× y 2×) y 2× en 340×640.
      for (final (t, escala) in [
        (telefonoMinimo, 1.8),
        (telefonoMinimo, 1.9),
        (telefonoMinimo, 2.0),
        (_telefono340, 2.0),
      ]) {
        testWidgets(
          '${t.nombre} · ${veces(escala)}: «¿Descartar» y «Descartar» no se parten; es el grande, al '
          'tamaño del sistema',
          (tester) async {
            await _montar(tester, _descartarCinco, tamano: t.tamano, escala: escala);
            await _abrir(tester);
            expect(_accionesAdentroDelScroll(tester), isTrue);
            expect(_escalaDelAviso(tester), closeTo(escala, 1e-9), reason: 'sin bajar el texto');
            for (final parrafo in _parrafos(tester)) {
              expect(_cortes(parrafo), isEmpty, reason: parrafo.text.toPlainText());
            }
          },
        );
      }

      testWidgets(
        '320×568 · 1,9×: «Confirmar» y «Cancelar» no se parten; es el grande, al tamaño del sistema',
        (tester) async {
          await _montar(tester, _avisos[3], tamano: telefonoMinimo.tamano, escala: 1.9);
          await _abrir(tester);
          expect(_accionesAdentroDelScroll(tester), isTrue);
          expect(_escalaDelAviso(tester), closeTo(1.9, 1e-9));
          for (final parrafo in _parrafos(tester)) {
            expect(_cortes(parrafo), isEmpty, reason: parrafo.text.toPlainText());
          }
        },
      );

      // La medida coincide con la realidad en toda la grilla: es el aviso grande cuando, y solo cuando, el
      // `AlertDialog` de siempre (armado aparte, con las mismas piezas) parte alguna palabra.
      for (final aviso in _avisos) {
        testWidgets('${aviso.nombre}: grande si y solo si el de siempre parte una palabra', (
          tester,
        ) async {
          for (final ancho in [280.0, 300.0, 320.0, 340.0, 360.0, 380.0, 412.0]) {
            for (final escala in [1.0, 1.5, 1.8, 1.9, 2.0]) {
              final donde = '${aviso.nombre} · ${ancho.round()} dp · ${veces(escala)}';
              await tester.pumpWidget(const SizedBox());
              await _montar(tester, aviso, tamano: Size(ancho, 640), escala: escala);
              await _abrir(tester, donde: donde);
              final grande = _accionesAdentroDelScroll(tester);
              final textos = [for (final p in _parrafos(tester)) p.text.toPlainText()];
              final cuerpo = textos.firstWhere(
                (t) => t != aviso.titulo && t != aviso.paraNo && t != aviso.paraSi,
              );
              if (!grande) {
                for (final parrafo in _parrafos(tester)) {
                  expect(_cortes(parrafo), isEmpty, reason: donde);
                }
                continue;
              }

              await tester.pumpWidget(const SizedBox());
              await _montarDeSiempre(tester, aviso, cuerpo, ancho: ancho, escala: escala);
              final partidas = [for (final p in _parrafos(tester)) ..._cortes(p)];
              expect(
                partidas,
                isNotEmpty,
                reason: '$donde: el de siempre entraba y se usó el grande',
              );
            }
          }
        });
      }
    });

    group('el tamaño del texto se limita al mayor en el que entra', () {
      for (final t in [...telefonos, telefonoMinimo]) {
        for (final escala in [2.2, 2.5, 3.0]) {
          testWidgets(
            '${t.nombre} · ${veces(escala)}: nunca por debajo de 2× ni por encima del sistema '
            'y no hay un tamaño mayor en el que entre',
            (tester) async {
              await _montar(tester, _descartarCinco, tamano: t.tamano, escala: escala);
              await _abrir(tester);
              final del = _escalaDelAviso(tester);
              expect(del, inInclusiveRange(2, escala + 1e-9));
              if (del >= escala - .01) return; // entra al tamaño del sistema: nada que limitar

              // Un poco más grande, alguna palabra del título o del cuerpo ya no entra en su renglón.
              final dialogo = tester.getRect(
                find.descendant(of: _aviso, matching: find.byType(Material)).first,
              );
              var algunaNoEntra = false;
              for (final parrafo in _parrafos(tester)) {
                final texto = parrafo.text.toPlainText();
                if (texto == _descartarCinco.paraNo || texto == _descartarCinco.paraSi) continue;
                final izquierda = parrafo.localToGlobal(Offset.zero).dx - dialogo.left;
                final ancho = dialogo.width - 2 * izquierda;
                for (final palabra in texto.split(RegExp(r'[ \n\t]+'))) {
                  final pintor = TextPainter(
                    text: TextSpan(text: palabra, style: parrafo.text.style),
                    textDirection: TextDirection.ltr,
                    textScaler: TextScaler.linear(del + .05),
                  )..layout();
                  if (pintor.width > ancho) algunaNoEntra = true;
                  pintor.dispose();
                }
              }
              expect(
                algunaNoEntra,
                isTrue,
                reason: 'a ${del + .05} también entraría: el tope es muy bajo',
              );
            },
          );
        }
      }

      testWidgets('en una pantalla tan angosta que ni a 2× entra, queda en 2×', (tester) async {
        await _montar(tester, _descartarCinco, tamano: const Size(220, 700), escala: 3);
        await _abrir(tester);
        expect(_escalaDelAviso(tester), closeTo(2, 1e-9));
        expect(tester.takeException(), isNull);
      });
    });

    group('capturas', () {
      for (final aviso in [_avisos[1], _avisos[5]]) {
        for (final t in telefonos) {
          for (final escala in [1.0, 2.0, 3.0]) {
            testWidgets('${aviso.nombre} ${t.nombre} ${veces(escala)}', (tester) async {
              await _montar(tester, aviso, tamano: t.tamano, escala: escala);
              await _abrir(tester);
              await capturarEn(
                tester,
                _raiz,
                '358_${aviso.nombre.split(' ').first}_${aviso.nombre.split(' ').last}_'
                '${t.nombre}_${veces(escala)}',
              );
              ponerTeclado(tester, t.teclado);
              await _asentar(tester);
              await capturarEn(
                tester,
                _raiz,
                '358_${aviso.nombre.split(' ').first}_${aviso.nombre.split(' ').last}_'
                '${t.nombre}_${veces(escala)}_teclado',
              );
            }, skip: !conCapturas);
          }
        }
      }
    });

    group('contestar', () {
      for (final aviso in _avisos) {
        testWidgets(
          '${aviso.nombre} · 3×: «${aviso.paraSi}» devuelve true; tocarlo dos veces seguidas no '
          'saca también la pantalla de abajo',
          (tester) async {
            final respuestas = await _montar(
              tester,
              aviso,
              tamano: const Size(360, 640),
              escala: 3,
            );
            await _abrir(tester);
            await tester.ensureVisible(_botonSi);
            await tester.pump();
            await tester.tap(_botonSi);
            await tester.tap(_botonSi, warnIfMissed: false);
            await _asentar(tester);
            expect(respuestas, [true]);
            expect(find.text('abrir'), findsOneWidget, reason: 'la pantalla de abajo sigue');
          },
        );

        testWidgets('${aviso.nombre} · 3×: «atrás» y volver a abrirlo; los dos botones llegan por '
            'segunda vez', (tester) async {
          final respuestas = await _montar(tester, aviso, tamano: const Size(360, 640), escala: 3);
          await _abrir(tester);
          await tester.binding.handlePopRoute();
          await _asentar(tester);
          expect(respuestas, [false], reason: 'cerrarlo de otro modo es "no"');
          await _abrir(tester);
          await tester.ensureVisible(_botonNo);
          await tester.pump();
          await tester.tap(_botonNo);
          await _asentar(tester);
          expect(respuestas, [false, false]);
          expect(find.byType(AlertDialog), findsNothing);
        });
      }
    });
  });
}
