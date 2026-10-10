// Vista 03 «Alta de ubicación» (HU-UBI-001), seguimiento #324 de #320 y #307: con el teclado abierto,
// el campo que se escribe y «Registrar» siguen a la vista.
//
// Lo que se prueba, con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado):
// - Si el campo con foco no entra entero sobre «Registrar», la hoja crece lo justo para que entre, hasta
//   el 80 % del cuerpo, con «Registrar» fijo; si ni así entra, «Registrar» pasa al final de lo que se
//   desplaza. En los seis estados del alta.
// - Tocar «Registrar» apagado lleva el motivo a la vista, lo anuncia una vez por toque y no registra,
//   no cierra el teclado ni mueve el foco; el motivo es la pista del botón para el lector de pantalla.
// - El alto de «Registrar» se mide (con el texto grande mide 56 a 72 dp, no 52).
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_317_arnes.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show asentar, cargarFuentesReales;

const _telefono320x568 = Size(320, 568);

String _x(double escala) => escala == escala.roundToDouble()
    ? '${escala.round()}×'
    : '${escala.toString().replaceAll('.', ',')}×';

/// El borde de la hoja (su `Material`).
Finder get _hoja => find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first;

bool _enLoQueSeDesplaza(Finder f) =>
    find.descendant(of: desplazable, matching: f).evaluate().isNotEmpty;

/// Cuánto del alto de [r] queda fuera de [area] o detrás del botón fijo.
double _corte(Rect r, Rect area, Rect registrar) {
  final limite = area.bottom < registrar.top ? area.bottom : registrar.top;
  return (area.top - r.top).clamp(0, double.infinity) +
      (r.bottom - limite).clamp(0, double.infinity);
}

/// Lleva «Registrar» a la vista si está al final de lo que se desplaza y comprueba que queda entero
/// sobre el teclado y que se toca.
Future<void> _registrarEntero(WidgetTester tester, double libre, String donde) async {
  if (_enLoQueSeDesplaza(botonRegistrarFijo)) {
    await tester.ensureVisible(botonRegistrarFijo);
    await tester.pump();
  }
  final r = tester.getRect(botonRegistrarFijo);
  expect(r.top, greaterThanOrEqualTo(0), reason: '$donde: «Registrar» se corta arriba ($r)');
  expect(r.bottom, lessThanOrEqualTo(libre + .5), reason: '$donde: «Registrar» queda tapado ($r)');
  expect(botonRegistrarFijo.hitTestable(), findsOneWidget, reason: '$donde: «Registrar» se toca');
}

/// Los anuncios que la app le manda al lector de pantalla.
List<String> _escucharAnuncios(WidgetTester tester) {
  final anuncios = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (dynamic mensaje) async {
      if (mensaje is Map && mensaje['type'] == 'announce') {
        anuncios.add((mensaje['data'] as Map)['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return anuncios;
}

void main() {
  setUpAll(cargarFuentesReales);

  final telefonos = <(String, Size, double)>[
    ('360×640', telefonoChico, tecladoAbierto),
    ('412×915', telefonoGrande, 340),
    ('320×568', _telefono320x568, tecladoAbierto),
  ];

  // Los seis estados del alta, que son los artboards 03A·01 a 03A·04 y las dos variantes sin conexión
  // y sin ciudades. Los de la HU que no son un artboard (cargando, error al guardar, éxito) los cubre
  // `alta_ubicacion_registrar_fijo_test.dart`.
  group(
    '#324 · 03 · con el teclado abierto, el campo que se escribe y «Registrar» siguen a la vista',
    () {
      for (final (nombreTel, tamano, teclado) in telefonos) {
        for (final escala in [1.0, 1.3, 2.0, 3.0]) {
          for (final estado in EstadoAlta.values) {
            // El estado más ancho del canvas (GPS impreciso) y el más corto bastan en 3×.
            if (escala == 3.0 &&
                estado != EstadoAlta.gpsPreciso &&
                estado != EstadoAlta.gpsImpreciso) {
              continue;
            }
            testWidgets(
              '${estado.rotulo} · $nombreTel · texto ${_x(escala)} · teclado de ${teclado.round()} dp: '
              'escribir el número y la calle los deja enteros, «Registrar» entero y la hoja no pasa del 80 %',
              (tester) async {
                await abrirEn(tester, estado, tamano: tamano, escala: escala, teclado: teclado);
                final cuerpo = tamano.height - teclado;
                expect(tester.takeException(), isNull, reason: 'sin overflow al abrir el teclado');

                for (final (campo, nombre, valor) in <(Finder, String, String)>[
                  (campoNumero, 'número', '1240'),
                  (campoCalle, 'calle', 'Avenida Italia'),
                ]) {
                  await tester.enterText(campo, valor);
                  await asentar(tester);
                  final hoja = tester.getRect(_hoja);
                  expect(
                    hoja.height,
                    lessThanOrEqualTo(cuerpo * .8 + .5),
                    reason: 'escribiendo la $nombre: la hoja pasa del 80 % del cuerpo ($hoja)',
                  );
                  expect(hoja.height, greaterThanOrEqualTo(cuerpo * .62 - .5));
                  expect(hoja.bottom, closeTo(cuerpo, .5), reason: 'la hoja apoya en el teclado');
                  final corte = _corte(
                    tester.getRect(campo),
                    zonaQueSeDesplaza(tester),
                    tester.getRect(botonRegistrarFijo),
                  );
                  expect(
                    corte,
                    lessThanOrEqualTo(1),
                    reason: 'escribiendo la $nombre se corta $corte dp',
                  );
                  expect(find.widgetWithText(TextField, valor), findsOneWidget);
                  expect(
                    tester.takeException(),
                    isNull,
                    reason: 'escribiendo la $nombre: overflow',
                  );
                }
                await _registrarEntero(tester, cuerpo, 'con el teclado abierto');
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    },
  );

  group('#324 · 03 · cuánto crece la hoja y dónde queda «Registrar»', () {
    for (final (nombreTel, tamano, _) in telefonos) {
      testWidgets('$nombreTel · sin teclado la hoja ocupa el 62 % del cuerpo', (tester) async {
        await abrirEn(tester, EstadoAlta.gpsPreciso, tamano: tamano);
        expect(tester.getRect(_hoja).height, lessThanOrEqualTo(tamano.height * .62 + .5));
      });
    }

    testWidgets(
      '320×568 · 1×: con el teclado la hoja crece lo justo para que el campo entre entero '
      'sobre «Registrar», que sigue fijo',
      (tester) async {
        await abrirEn(tester, EstadoAlta.gpsPreciso, tamano: _telefono320x568);
        final cerrada = tester.getRect(_hoja).height;
        await abrirTeclado(tester);
        const cuerpo = 568 - tecladoAbierto;
        final abierta = tester.getRect(_hoja).height;

        expect(abierta, greaterThan(cuerpo * .62 + 1), reason: 'crece más allá del 62 %');
        expect(abierta, lessThanOrEqualTo(cuerpo * .8 + .5));
        expect(abierta, lessThan(cerrada + 200), reason: 'y es una hoja, no la pantalla');
        expect(
          _enLoQueSeDesplaza(find.text(TextosAlta.elegiElTipo)),
          isTrue,
          reason: 'el motivo no entra debajo del botón: queda al final de lo que se desplaza',
        );
        expect(_enLoQueSeDesplaza(botonRegistrarFijo), isFalse);
        await tester.enterText(campoNumero, '1240');
        await asentar(tester);
        expect(
          _corte(
            tester.getRect(campoNumero),
            zonaQueSeDesplaza(tester),
            tester.getRect(botonRegistrarFijo),
          ),
          lessThanOrEqualTo(1),
        );
      },
    );

    testWidgets(
      '360×640 · 1×: con el teclado, «Registrar» sigue fijo con el motivo debajo (como en el canvas) '
      'y la hoja crece apenas, lo que ese motivo pide',
      (tester) async {
        await abrirEn(tester, EstadoAlta.gpsPreciso, teclado: tecladoAbierto);
        const cuerpo = 640 - tecladoAbierto;
        final hoja = tester.getRect(_hoja);
        expect(hoja.height, lessThanOrEqualTo(cuerpo * .8 + .5));
        expect(hoja.height, lessThan(cuerpo * .62 + 20), reason: 'crece apenas');
        expect(_enLoQueSeDesplaza(botonRegistrarFijo), isFalse);
        expect(_enLoQueSeDesplaza(find.text(TextosAlta.elegiElTipo)), isFalse);
        expect(
          tester.getRect(find.text(TextosAlta.elegiElTipo)).top,
          greaterThanOrEqualTo(tester.getRect(botonRegistrarFijo).bottom),
        );
      },
    );

    testWidgets('texto al 300 %: con el teclado «Registrar» pasa al final de lo que se desplaza, '
        'debajo del motivo, y la hoja no desborda ni pasa del 80 %', (tester) async {
      await abrirEn(
        tester,
        EstadoAlta.gpsPreciso,
        tamano: _telefono320x568,
        escala: 3,
        teclado: tecladoAbierto,
      );
      const cuerpo = 568 - tecladoAbierto;

      expect(tester.getRect(_hoja).height, closeTo(cuerpo * .8, .5), reason: 'pide todo el 80 %');
      expect(_enLoQueSeDesplaza(botonRegistrarFijo), isTrue, reason: 'el botón va al final');
      expect(_enLoQueSeDesplaza(find.text(TextosAlta.elegiElTipo)), isTrue);
      await tester.enterText(campoNumero, '1240');
      await asentar(tester);
      expect(tester.takeException(), isNull);
      expect(
        _corte(
          tester.getRect(campoNumero),
          zonaQueSeDesplaza(tester),
          // Sin botón fijo: el borde de abajo de la zona es el único límite.
          Rect.fromLTWH(0, zonaQueSeDesplaza(tester).bottom, 1, 1),
        ),
        lessThanOrEqualTo(1),
        reason: 'el campo se ve entero',
      );
      // Y «Registrar» se alcanza desplazando, entero sobre el teclado.
      await _registrarEntero(tester, cuerpo, 'texto 3×');
      await tester.tap(botonRegistrarFijo);
      await asentar(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('al cerrar el teclado «Registrar» vuelve a quedar fijo al pie, donde estaba', (
      tester,
    ) async {
      await abrirEn(tester, EstadoAlta.gpsPreciso, tamano: _telefono320x568, escala: 3);
      final antes = tester.getRect(botonRegistrarFijo);
      await abrirTeclado(tester);
      expect(_enLoQueSeDesplaza(botonRegistrarFijo), isTrue);
      await cerrarTeclado(tester);

      expect(_enLoQueSeDesplaza(botonRegistrarFijo), isFalse);
      expect(tester.getRect(botonRegistrarFijo), antes);
      expect(tester.takeException(), isNull);
    });
  });

  group('#324 · 03 · el alto de «Registrar» se mide', () {
    for (final escala in [1.0, 1.15, 1.3, 1.5, 2.0]) {
      testWidgets('360×640 · texto ${_x(escala)}: con el teclado el campo y el motivo no se cortan '
          'aunque el botón mida más de 52 dp', (tester) async {
        await abrirEn(tester, EstadoAlta.gpsPreciso, escala: escala, teclado: tecladoAbierto);
        final boton = tester.getSize(botonRegistrarFijo).height;
        expect(boton, greaterThanOrEqualTo(52));
        if (escala >= 1.3) {
          expect(boton, greaterThan(52), reason: 'con el texto grande el botón crece');
        }
        const cuerpo = 640 - tecladoAbierto;
        await tester.enterText(campoNumero, '1240');
        await asentar(tester);

        expect(tester.takeException(), isNull);
        expect(tester.getRect(_hoja).height, lessThanOrEqualTo(cuerpo * .8 + .5));
        expect(
          _corte(
            tester.getRect(campoNumero),
            zonaQueSeDesplaza(tester),
            tester.getRect(botonRegistrarFijo),
          ),
          lessThanOrEqualTo(1),
          reason: 'con un botón de ${boton.toStringAsFixed(1)} dp el campo se corta',
        );
        final motivo = find.text(TextosAlta.elegiElTipo);
        if (_enLoQueSeDesplaza(motivo)) {
          await tester.ensureVisible(motivo);
          await tester.pump();
          final zona = zonaQueSeDesplaza(tester);
          expect(tester.getRect(motivo).top, greaterThanOrEqualTo(zona.top - .5));
        } else {
          expect(tester.getRect(motivo).bottom, lessThanOrEqualTo(cuerpo + .5));
        }
      });
    }

    for (final escala in [1.15, 1.3, 2.0]) {
      testWidgets(
        '360×640 · texto ${_x(escala)} sin teclado: «Registrar» y su motivo entran enteros '
        'en la hoja',
        (tester) async {
          await abrirEn(tester, EstadoAlta.gpsPreciso, escala: escala);
          final hoja = tester.getRect(_hoja);
          final boton = tester.getRect(botonRegistrarFijo);

          expect(tester.takeException(), isNull);
          expect(boton.bottom, lessThanOrEqualTo(hoja.bottom));
          final motivo = find.text(TextosAlta.elegiElTipo);
          if (!_enLoQueSeDesplaza(motivo)) {
            expect(tester.getRect(motivo).bottom, lessThanOrEqualTo(hoja.bottom - 20 + .5));
          }
        },
      );
    }
  });

  group('#324 · 03 · tocar «Registrar» apagado dice por qué', () {
    for (final (nombre, tamano, escala, estado, motivo)
        in <(String, Size, double, EstadoAlta, String)>[
          ('320×568', _telefono320x568, 1.0, EstadoAlta.gpsPreciso, TextosAlta.elegiElTipo),
          ('320×568', _telefono320x568, 1.0, EstadoAlta.gpsImpreciso, TextosAlta.elegiPrecision),
          ('360×640', telefonoChico, 2.0, EstadoAlta.gpsPreciso, TextosAlta.elegiElTipo),
          ('360×640', telefonoChico, 1.0, EstadoAlta.gpsImpreciso, TextosAlta.elegiPrecision),
        ]) {
      testWidgets(
        '$nombre · texto ${_x(escala)} · ${estado.rotulo}: lleva el motivo a la vista, lo '
        'anuncia una vez por toque y no registra, no cierra el teclado ni mueve el foco',
        (tester) async {
          final anuncios = _escucharAnuncios(tester);
          final m = await abrirEn(
            tester,
            estado,
            tamano: tamano,
            escala: escala,
            teclado: tecladoAbierto,
          );
          final libre = tamano.height - tecladoAbierto;
          await tester.enterText(campoNumero, '1240');
          await asentar(tester);
          final foco = FocusManager.instance.primaryFocus;
          expect(foco, isNotNull, reason: 'se escribe en el número');
          expect(registrarHabilitado(tester), isFalse);

          // El colportor subió la hoja hasta el principio: el motivo, si está en lo que se desplaza,
          // queda fuera de la vista.
          await irAlPrincipioDeLaHoja(tester);
          final enLaZona = _enLoQueSeDesplaza(find.text(motivo));
          if (enLaZona) {
            expect(
              tester.getRect(find.text(motivo)).top,
              greaterThanOrEqualTo(zonaQueSeDesplaza(tester).bottom - .5),
              reason: 'antes del toque el motivo está fuera de la vista',
            );
          }

          await tester.tap(botonRegistrarFijo);
          await asentar(tester);

          // El motivo está a la vista: dentro de la zona que se desplaza o debajo del botón fijo.
          final r = tester.getRect(find.text(motivo));
          if (enLaZona) {
            final zona = zonaQueSeDesplaza(tester);
            expect(r.top, greaterThanOrEqualTo(zona.top - .5));
            expect(r.bottom, lessThanOrEqualTo(zona.bottom + .5));
          } else {
            expect(r.bottom, lessThanOrEqualTo(libre + .5));
          }
          expect(anuncios, [motivo], reason: 'se anuncia una vez');
          expect(m.repo.llamadas, isEmpty, reason: 'no registra');
          expect(tester.testTextInput.isVisible, isTrue, reason: 'el teclado sigue arriba');
          expect(tester.view.viewInsets.bottom, tecladoAbierto);
          expect(
            identical(FocusManager.instance.primaryFocus, foco),
            isTrue,
            reason: 'el foco no se movió',
          );
          expect(
            find.widgetWithText(TextField, '1240'),
            findsOneWidget,
            reason: 'lo escrito sigue',
          );

          // Un segundo toque anuncia una vez más (uno por toque), sin acumular nada.
          await tester.tap(botonRegistrarFijo);
          await asentar(tester);
          expect(anuncios, [motivo, motivo]);
          expect(m.repo.llamadas, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('sin teclado también: anuncia el motivo y no registra', (tester) async {
      final anuncios = _escucharAnuncios(tester);
      final m = await abrirEn(tester, EstadoAlta.gpsPreciso);

      await tester.tap(botonRegistrarFijo);
      await asentar(tester);

      expect(anuncios, [TextosAlta.elegiElTipo]);
      expect(m.repo.llamadas, isEmpty);
    });

    testWidgets('con «Registrar» habilitado no anuncia nada y registra una sola vez', (
      tester,
    ) async {
      final anuncios = _escucharAnuncios(tester);
      final m = await abrirEn(tester, EstadoAlta.gpsPreciso, teclado: tecladoAbierto);
      await tester.ensureVisible(find.text('Casa'));
      await tester.pump();
      await tester.tap(find.text('Casa'));
      await asentar(tester);
      expect(registrarHabilitado(tester), isTrue);

      await tester.tap(botonRegistrarFijo);
      await tester.tap(botonRegistrarFijo, warnIfMissed: false);
      await asentar(tester);

      expect(anuncios, isEmpty);
      expect(m.repo.llamadas, hasLength(1));
    });

    testWidgets('mientras guarda, el botón apagado no anuncia ningún motivo', (tester) async {
      final anuncios = _escucharAnuncios(tester);
      final m = await abrirEn(tester, EstadoAlta.gpsPreciso);
      m.repo.bloqueo = Completer<void>();
      await tester.tap(find.text('Casa'));
      await asentar(tester);
      await tester.tap(botonRegistrarFijo);
      await tester.pump();
      expect(find.text(TextosAlta.registrando), findsOneWidget);

      await tester.tap(botonRegistrarFijo);
      await tester.pump();

      expect(anuncios, isEmpty);
    });

    testWidgets('el motivo es la pista del botón apagado para el lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await abrirEn(tester, EstadoAlta.gpsPreciso, teclado: tecladoAbierto);

      // El nodo del botón junta lo suyo con lo del texto: `getSemanticsData` da lo juntado.
      SemanticsData datos() => tester.getSemantics(botonRegistrarFijo).getSemanticsData();
      final apagado = datos();
      expect(apagado.label, contains(TextosAlta.registrar));
      expect(apagado.hint, TextosAlta.elegiElTipo);

      await tester.ensureVisible(find.text('Casa'));
      await tester.pump();
      await tester.tap(find.text('Casa'));
      await asentar(tester);
      expect(datos().hint, isEmpty, reason: 'habilitado no hay pista');
      semantica.dispose();
    });
  });
}
