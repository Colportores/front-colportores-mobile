// QA de #320 / PR #322 (vista 03 «Alta de ubicación», HU-UBI-001): el motivo de «Registrar» apagado
// («Elegí el tipo de ubicación para registrar.», «Marcá el punto…», «Elegí «Ajustar manualmente»…»)
// también se ve con el teclado abierto (decisión §2 b de #305).
//
// Complementa al grupo `#320` de `alta_ubicacion_registrar_fijo_test.dart` (360×640, texto 1× y 2×,
// tres motivos) con lo que ese grupo no recorre: los seis estados del alta que muestran un motivo, los
// tres teléfonos (360×640, 320×568 y 412×915), el texto 1×, 1,3×, 2× y 3×, el campo que se escribe
// (calle y número), el cambio de lugar del motivo con el foco puesto y que sin teclado nada cambió.
//
// Geometría con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado). Las
// guías de accesibilidad van en `alta_ubicacion_qa_320_guias_test.dart`.
//
// Los tests que documentan un hallazgo van con `skip: true` y, arriba, el comentario
// `// skip: QA #322 — <hallazgo>` (en `testWidgets` el `skip` es un bool).
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_317_arnes.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;

const _telefono320x568 = Size(320, 568);

String _x(double escala) => escala == escala.roundToDouble()
    ? '${escala.round()}×'
    : '${escala.toString().replaceAll('.', ',')}×';

/// Los estados del alta que muestran un motivo bajo «Registrar» y el texto de cada uno.
const _conMotivo = <(EstadoAlta, String)>[
  (EstadoAlta.gpsPreciso, TextosAlta.elegiElTipo),
  (EstadoAlta.gpsImpreciso, TextosAlta.elegiPrecision),
  (EstadoAlta.sinGps, TextosAlta.marcaElPunto),
  (EstadoAlta.sinGpsSinConexion, TextosAlta.marcaElPunto),
  (EstadoAlta.sinCiudades, TextosAlta.marcaElPunto),
  (EstadoAlta.numeroEditado, TextosAlta.elegiElTipo),
];

bool _enLoQueSeDesplaza(Finder f) =>
    find.descendant(of: desplazable, matching: f).evaluate().isNotEmpty;

/// Cuánto del alto de [r] queda fuera de [area] o detrás del botón fijo.
double _corte(Rect r, Rect area, Rect registrar) {
  final limite = area.bottom < registrar.top ? area.bottom : registrar.top;
  return (area.top - r.top).clamp(0, double.infinity) +
      (r.bottom - limite).clamp(0, double.infinity);
}

/// «Registrar» entero, por encima de lo que tapa el teclado (o la barra de abajo). Si está al final de
/// lo que se desplaza (#324: el teléfono más chico con el texto muy grande) se lo lleva a la vista.
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

/// El motivo a la vista: debajo del botón y sobre el teclado, o al final de lo que se desplaza
/// (arriba del botón) y alcanzable con el dedo.
Future<void> _motivoALaVista(WidgetTester tester, String texto, double libre, String donde) async {
  final motivo = find.text(texto);
  expect(motivo, findsOneWidget, reason: '$donde: el motivo está, una sola vez');
  if (_enLoQueSeDesplaza(motivo)) {
    await tester.ensureVisible(motivo);
    await tester.pump();
    final r = tester.getRect(motivo);
    final area = zonaQueSeDesplaza(tester);
    expect(r.top, greaterThanOrEqualTo(area.top - .5), reason: '$donde: empieza a la vista');
    if (r.height <= area.height) {
      expect(r.bottom, lessThanOrEqualTo(area.bottom + .5), reason: '$donde: se ve entero');
      expect(motivo.hitTestable(), findsOneWidget, reason: '$donde: el motivo se alcanza');
    } else {
      expect(r.top, lessThan(area.bottom - 8), reason: '$donde: su primer renglón se ve');
    }
  } else {
    final r = tester.getRect(motivo);
    expect(
      r.top,
      greaterThanOrEqualTo(tester.getRect(botonRegistrarFijo).bottom - .5),
      reason: '$donde: va debajo del botón',
    );
    expect(r.bottom, lessThanOrEqualTo(libre + .5), reason: '$donde: se corta ($r)');
    expect(motivo.hitTestable(), findsOneWidget, reason: '$donde: el motivo se ve');
  }
}

void main() {
  setUpAll(cargarFuentesReales);

  final telefonos = <(String, Size, double)>[
    ('360×640', telefonoChico, tecladoAbierto),
    ('412×915', telefonoGrande, 340),
    ('320×568', _telefono320x568, tecladoAbierto),
  ];

  group('QA #322 · el motivo de «Registrar» con el teclado abierto, en los seis estados', () {
    for (final (nombreTel, tamano, teclado) in telefonos) {
      for (final escala in [1.0, 1.3, 2.0, 3.0]) {
        for (final (estado, texto) in _conMotivo) {
          // El estado más ancho del canvas (GPS impreciso) y el más corto bastan en 3×: el resto
          // repite la misma geometría.
          if (escala == 3.0 &&
              estado != EstadoAlta.gpsPreciso &&
              estado != EstadoAlta.gpsImpreciso) {
            continue;
          }
          testWidgets(
            '${estado.rotulo} · $nombreTel · texto ${_x(escala)} · teclado de ${teclado.round()} dp: '
            'el motivo está y se alcanza, «Registrar» entero y apagado, sin overflow',
            (tester) async {
              await abrirEn(tester, estado, tamano: tamano, escala: escala, teclado: teclado);
              final libre = tamano.height - teclado;

              expect(tester.takeException(), isNull, reason: 'sin overflow');
              expect(registrarHabilitado(tester), isFalse, reason: 'apagado: por eso el motivo');
              await _registrarEntero(tester, libre, 'teclado abierto');
              await _motivoALaVista(tester, texto, libre, 'teclado abierto');
              // Un solo motivo a la vez.
              for (final otro in {
                TextosAlta.marcaElPunto,
                TextosAlta.elegiElTipo,
                TextosAlta.elegiPrecision,
                TextosAlta.elegiLaCiudad,
              }.difference({texto})) {
                expect(find.text(otro), findsNothing, reason: 'solo el motivo «$texto»');
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('QA #322 · el campo que se escribe sigue entero con el motivo a la vista', () {
    for (final (nombreTel, tamano, teclado) in telefonos) {
      for (final escala in [1.0, 1.3, 2.0]) {
        testWidgets(
          '$nombreTel · texto ${_x(escala)} · teclado de ${teclado.round()} dp: escribir el número y la '
          'calle los deja enteros, sobre «Registrar» y sin que el motivo se pierda',
          (tester) async {
            await abrirEn(
              tester,
              EstadoAlta.gpsPreciso,
              tamano: tamano,
              escala: escala,
              teclado: teclado,
            );
            final libre = tamano.height - teclado;

            for (final (campo, nombre, valor) in <(Finder, String, String)>[
              (campoNumero, 'número', '1240'),
              (campoCalle, 'calle', 'Avenida Italia'),
            ]) {
              await tester.enterText(campo, valor);
              await asentar(tester);
              final corte = _corte(
                tester.getRect(campo),
                zonaQueSeDesplaza(tester),
                tester.getRect(botonRegistrarFijo),
              );
              // 1 dp de tolerancia: a 2× la base ya dejaba 1 dp fuera (el borde del campo).
              expect(
                corte,
                lessThanOrEqualTo(1),
                reason: 'escribiendo la $nombre se corta $corte dp',
              );
              expect(find.widgetWithText(TextField, valor), findsOneWidget);
              await _registrarEntero(tester, libre, 'escribiendo la $nombre');
              expect(
                find.text(TextosAlta.elegiElTipo),
                findsOneWidget,
                reason: 'el motivo no se va',
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('QA #322 · el motivo cambia de lugar con el foco puesto y lo escrito sigue ahí', () {
    testWidgets(
      '360×640 · texto 1,3×: un teclado cada vez más alto pasa el motivo debajo → en lo que '
      'se desplaza sin perder el foco ni lo escrito',
      (tester) async {
        await abrirEn(tester, EstadoAlta.gpsPreciso, escala: 1.3);
        await tester.enterText(campoNumero, '1240');
        await asentar(tester);
        final foco = tester.widget<TextField>(campoNumero).focusNode;

        var debajo = 0;
        var arriba = 0;
        for (var teclado = 240.0; teclado <= 400; teclado += 8) {
          tester.view.viewInsets = FakeViewPadding(bottom: teclado);
          await tester.pumpAndSettle();
          final donde = 'teclado de ${teclado.round()} dp';

          expect(tester.takeException(), isNull, reason: '$donde: sin overflow');
          expect(find.text(TextosAlta.elegiElTipo), findsOneWidget, reason: '$donde: motivo');
          expect(
            find.widgetWithText(TextField, '1240'),
            findsOneWidget,
            reason: '$donde: lo escrito',
          );
          if (foco != null) expect(foco.hasFocus, isTrue, reason: '$donde: el foco sigue');
          await _registrarEntero(tester, 640 - teclado, donde);
          if (_enLoQueSeDesplaza(find.text(TextosAlta.elegiElTipo))) {
            arriba++;
          } else {
            debajo++;
          }
        }
        expect(debajo, greaterThan(0), reason: 'con los teclados bajos va debajo del botón');
        expect(arriba, greaterThan(0), reason: 'con los altos pasa a lo que se desplaza');
      },
    );

    testWidgets(
      '360×640 · texto 2×: abrir y cerrar el teclado tres veces con el número escrito: nada '
      'se duplica ni se pierde',
      (tester) async {
        await abrirEn(tester, EstadoAlta.gpsImpreciso, escala: 2);
        await tester.enterText(campoNumero, '1240');
        await asentar(tester);
        final sinTeclado = tester.getRect(botonRegistrarFijo);

        for (var vez = 0; vez < 3; vez++) {
          await abrirTeclado(tester);
          expect(
            find.text(TextosAlta.elegiPrecision),
            findsOneWidget,
            reason: 'abierto, vuelta $vez',
          );
          await _registrarEntero(tester, 640 - tecladoAbierto, 'abierto, vuelta $vez');
          await cerrarTeclado(tester);
          expect(
            find.text(TextosAlta.elegiPrecision),
            findsOneWidget,
            reason: 'cerrado, vuelta $vez',
          );
          expect(tester.getRect(botonRegistrarFijo), sinTeclado, reason: 'cerrado, vuelta $vez');
          expect(find.widgetWithText(TextField, '1240'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('QA #322 · la acción con el motivo a la vista', () {
    testWidgets('360×640 · texto 2× · teclado: elegir «Casa» apaga el motivo y «Registrar» registra '
        'una sola vez aun con dos toques seguidos', (tester) async {
      final m = await abrirEn(tester, EstadoAlta.gpsPreciso, escala: 2, teclado: tecladoAbierto);
      expect(registrarHabilitado(tester), isFalse);
      expect(find.text(TextosAlta.elegiElTipo), findsOneWidget);

      // El tipo de ubicación está arriba, en lo que se desplaza: se lo lleva a la vista y se lo toca.
      await tester.ensureVisible(find.text('Casa'));
      await tester.pump();
      await tester.tap(find.text('Casa'));
      await asentar(tester);

      expect(find.text(TextosAlta.elegiElTipo), findsNothing);
      expect(registrarHabilitado(tester), isTrue);
      await _registrarEntero(tester, 640 - tecladoAbierto, 'con «Casa»');

      await tester.tap(botonRegistrarFijo);
      await tester.tap(botonRegistrarFijo, warnIfMissed: false);
      await asentar(tester);
      expect(m.repo.llamadas, hasLength(1), reason: 'doble toque: una sola ubicación');
    });
  });

  group('QA #322 · sin teclado nada cambió', () {
    // El lugar del motivo con «GPS preciso» y sin teclado, tal como estaba antes de #322 (la sonda del
    // QA corrió la misma matriz en la base y en el PR: 72 combinaciones idénticas). La barra de 3
    // botones de 48 dp acorta la hoja y a 320×568 con texto 2× lo manda a lo que se desplaza.
    const abajo = true;
    const lugar = <(String, Size, double, double, bool)>[
      ('360×640', telefonoChico, 1.0, 0, abajo),
      ('360×640', telefonoChico, 1.3, 0, abajo),
      ('360×640', telefonoChico, 2.0, 0, abajo),
      ('360×640', telefonoChico, 3.0, 0, !abajo),
      ('360×640', telefonoChico, 2.0, 48, abajo),
      ('412×915', telefonoGrande, 1.0, 0, abajo),
      ('412×915', telefonoGrande, 2.0, 0, abajo),
      ('412×915', telefonoGrande, 3.0, 48, abajo),
      ('320×568', _telefono320x568, 1.0, 0, abajo),
      ('320×568', _telefono320x568, 2.0, 0, abajo),
      ('320×568', _telefono320x568, 2.0, 48, !abajo),
      ('320×568', _telefono320x568, 3.0, 0, !abajo),
    ];
    for (final (nombreTel, tamano, escala, barra, debajoDelBoton) in lugar) {
      testWidgets('$nombreTel · texto ${_x(escala)} · barra de ${barra.round()} dp: el motivo va '
          '${debajoDelBoton ? 'debajo del botón' : 'al final de lo que se desplaza'}', (
        tester,
      ) async {
        await abrirEn(
          tester,
          EstadoAlta.gpsPreciso,
          tamano: tamano,
          escala: escala,
          barraInferior: barra,
        );
        final motivo = find.text(TextosAlta.elegiElTipo);

        expect(motivo, findsOneWidget);
        expect(_enLoQueSeDesplaza(motivo), !debajoDelBoton);
        await _registrarEntero(tester, tamano.height - barra, 'sin teclado');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
