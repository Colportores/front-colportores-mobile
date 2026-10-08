// «Registrar» fijo al pie de la hoja del alta (vista 03, HU-UBI-001, #305): lo de arriba se desplaza
// y el botón queda entero a la vista en cada artboard (03A · 01 a 04), en 360×640, con el texto al
// 200 % y con el teclado abierto. Más los rótulos de la 03 sobre el mapa (chip del GPS y pista), que
// escalan con el texto sin tapar el pin, como en la 07. Y, desde #320, el motivo de «Registrar»
// apagado también con el teclado abierto.
//
// Medidas con las fuentes reales del proyecto (con Ahem el texto se infla).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mapa_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart';

/// La barra de estado de un Android común.
const _barraDeEstado = 24.0;

/// El teclado abierto, en dp de alto.
const _teclado = 300.0;

const _telefonoChico = Size(360, 640);

/// Los estados del canvas (vista 03) a los que se llega desde el alta.
enum _Artboard {
  gpsPreciso('03A · 01 GPS preciso'),
  sinGps('03A · 02 Sin GPS'),
  gpsImpreciso('03A · 03 GPS impreciso'),
  numeroEditado('03A · 04 Número editado'),
  sinGpsYSinConexion('03A · 02 Sin GPS con el aviso «Sin conexión…» de arriba');

  const _Artboard(this.rotulo);
  final String rotulo;
}

Future<RepoAltaFalso> _montar(
  WidgetTester tester,
  _Artboard artboard, {
  double escala = 1,
  Size tamano = _telefonoChico,
  bool teclado = false,
  RepoAltaFalso? repo,
}) async {
  tester.view.padding = const FakeViewPadding(top: _barraDeEstado);
  tester.view.viewPadding = const FakeViewPadding(top: _barraDeEstado);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
  final repoAlta = repo ?? RepoAltaFalso();
  await montarAlta(
    tester,
    tamano: tamano,
    escala: escala,
    repo: repoAlta,
    gps: switch (artboard) {
      _Artboard.sinGps || _Artboard.sinGpsYSinConexion => gpsSinPermiso,
      _Artboard.gpsImpreciso => GpsFalso(Right(lecturaGps(85))),
      _ => null,
    },
    situacion: artboard == _Artboard.sinGpsYSinConexion ? situacionSinConexion : null,
  );
  await tester.pumpAndSettle();
  if (artboard == _Artboard.numeroEditado) {
    await tester.enterText(_campoNumero, '1238');
    await asentar(tester);
  }
  if (teclado) await _abrirTeclado(tester);
  return repoAlta;
}

Future<void> _abrirTeclado(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: _teclado);
  await tester.pumpAndSettle();
}

Future<void> _cerrarTeclado(WidgetTester tester) async {
  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
}

Finder get _campoNumero => find.byType(TextField).at(1);

Finder get _campoCalle => find.byType(TextField).first;

/// El botón «Registrar» (o «Registrando…»).
Finder get _registrar => find.byWidgetPredicate(
  (w) =>
      w is FilledButton &&
      w.child is Text &&
      ((w.child! as Text).data == TextosAlta.registrar ||
          (w.child! as Text).data == TextosAlta.registrando),
);

/// La parte de la hoja que se desplaza.
Finder get _desplazable =>
    find.descendant(of: find.byType(HojaAlta), matching: find.byType(SingleChildScrollView)).first;

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_registrar).onPressed != null;

/// «Registrar» entero dentro de lo que se ve (la pantalla menos el teclado), con su texto sin cortar.
void _registrarEntero(WidgetTester tester, {required double alto, required String donde}) {
  expect(tester.takeException(), isNull, reason: '$donde: sin desborde');
  expect(_registrar, findsOneWidget, reason: donde);
  final r = tester.getRect(_registrar);
  expect(r.top, greaterThanOrEqualTo(0), reason: '$donde: «Registrar» se sale por arriba ($r)');
  expect(
    r.bottom,
    lessThanOrEqualTo(alto),
    reason: '$donde: «Registrar» queda cortado al pie ($r)',
  );
  expect(r.height, greaterThanOrEqualTo(48), reason: '$donde: «Registrar» queda aplastado ($r)');
  expect(_registrar.hitTestable(), findsOneWidget, reason: '$donde: «Registrar» no se puede tocar');
  final texto = tester.getRect(find.descendant(of: _registrar, matching: find.byType(Text)));
  expect(
    r.inflate(.5).contains(texto.topLeft) && r.inflate(.5).contains(texto.bottomRight),
    isTrue,
    reason: '$donde: el texto de «Registrar» se sale del botón ($texto en $r)',
  );
}

void main() {
  setUpAll(cargarFuentesReales);

  group(
    '#305 · «Registrar» queda fijo al pie, entero a la vista, en cada artboard de la vista 03',
    () {
      for (final artboard in _Artboard.values) {
        for (final (tamano, escala, teclado) in [
          (_telefonoChico, 1.0, false),
          (_telefonoChico, 1.0, true),
          (_telefonoChico, 2.0, false),
          (_telefonoChico, 2.0, true),
          (const Size(412, 915), 2.0, false),
          (const Size(412, 915), 1.0, false),
        ]) {
          final alto = tamano.height - (teclado ? _teclado : 0);
          testWidgets(
            '${artboard.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}, texto ${escala}x'
            '${teclado ? ' y el teclado abierto' : ''}',
            (tester) async {
              await _montar(tester, artboard, escala: escala, tamano: tamano, teclado: teclado);

              _registrarEntero(tester, alto: alto, donde: 'sin elegir el tipo');

              // Con el tipo elegido (el botón se habilita si ya hay punto): sigue entero y a la vista.
              await tocar(tester, find.text('Casa'));
              _registrarEntero(tester, alto: alto, donde: 'con «Casa» elegida');
            },
          );
        }
      }
    },
  );

  group('#305 · la sonda del QA: un campo editado en 360×640', () {
    testWidgets('con el número escrito a mano, «Registrar» no se corre al desplazar la hoja', (
      tester,
    ) async {
      await _montar(tester, _Artboard.numeroEditado, escala: 2);
      final antes = tester.getRect(_registrar);

      await tester.drag(_desplazable, const Offset(0, -400));
      await tester.pump();
      expect(tester.getRect(_registrar), antes, reason: 'el botón es fijo: no se desplaza');

      await tester.drag(_desplazable, const Offset(0, 400));
      await tester.pump();
      expect(tester.getRect(_registrar), antes);
    });

    testWidgets('a texto 2x la parte de arriba se desplaza y deja llegar a calle y número', (
      tester,
    ) async {
      await _montar(tester, _Artboard.gpsPreciso, escala: 2);
      final maximo = tester
          .state<ScrollableState>(
            find.descendant(of: _desplazable, matching: find.byType(Scrollable)).first,
          )
          .position
          .maxScrollExtent;
      expect(maximo, greaterThan(0), reason: 'a 2x no entra todo: se desplaza');

      await tester.drag(_desplazable, Offset(0, -maximo));
      await tester.pump();

      expect(_campoNumero.hitTestable(), findsOneWidget, reason: 'el número se alcanza');
      expect(_campoCalle.hitTestable(), findsOneWidget);
      expect(_registrar.hitTestable(), findsOneWidget);
      final numero = tester.getRect(_campoNumero);
      final boton = tester.getRect(_registrar);
      expect(numero.overlaps(boton), isFalse, reason: 'el campo no queda bajo el botón fijo');
    });

    testWidgets('con el teclado abierto a texto 2x se puede escribir el número y registrar', (
      tester,
    ) async {
      final repo = await _montar(tester, _Artboard.gpsPreciso, escala: 2, teclado: true);
      await tocar(tester, find.text('Casa'));

      await tester.enterText(_campoNumero, '1240');
      await asentar(tester);
      _registrarEntero(tester, alto: 640 - _teclado, donde: 'escribiendo el número');

      await tester.tap(_registrar);
      await asentar(tester);
      expect(repo.llamadas, hasLength(1));
      expect(repo.llamadas.single.ubicacion.numero, '1240');
    });
  });

  group('#305 · el motivo de abajo de «Registrar»', () {
    testWidgets(
      'se ve debajo del botón, como en el canvas, y con el teclado abierto no se pierde',
      (tester) async {
        await _montar(tester, _Artboard.gpsPreciso, escala: 2);
        expect(find.text(TextosAlta.elegiElTipo), findsOneWidget);
        expect(
          tester.getRect(find.text(TextosAlta.elegiElTipo)).top,
          greaterThanOrEqualTo(tester.getRect(_registrar).bottom),
          reason: 'el motivo va debajo del botón, como en el canvas',
        );

        await _abrirTeclado(tester);
        expect(find.text(TextosAlta.elegiElTipo), findsOneWidget, reason: 'también con el teclado');
        _registrarEntero(tester, alto: 640 - _teclado, donde: 'con el teclado');

        await _cerrarTeclado(tester);
        expect(
          tester.getRect(find.text(TextosAlta.elegiElTipo)).top,
          greaterThanOrEqualTo(tester.getRect(_registrar).bottom),
          reason: 'al cerrar el teclado el motivo vuelve a su lugar, debajo del botón',
        );
        _registrarEntero(tester, alto: 640, donde: 'sin el teclado');
      },
    );

    testWidgets('el motivo más largo del canvas (GPS impreciso) sigue debajo del botón a texto 2x', (
      tester,
    ) async {
      await _montar(tester, _Artboard.gpsImpreciso, escala: 2);

      final motivo = find.text(TextosAlta.elegiPrecision);
      expect(motivo, findsOneWidget);
      expect(
        find.descendant(of: _desplazable, matching: motivo),
        findsNothing,
        reason:
            'con las fuentes reales entra a 200 %: queda fijo debajo del botón, como en el canvas',
      );
      expect(tester.getRect(motivo).top, greaterThanOrEqualTo(tester.getRect(_registrar).bottom));
      _registrarEntero(tester, alto: 640, donde: 'GPS impreciso a 2x');
    });

    testWidgets(
      'a texto 3x el motivo dejaría poco para los campos: pasa a lo que se desplaza, arriba del '
      'botón, y se alcanza',
      (tester) async {
        await _montar(tester, _Artboard.gpsImpreciso, escala: 3);

        final motivo = find.text(TextosAlta.elegiPrecision);
        expect(motivo, findsOneWidget);
        expect(find.descendant(of: _desplazable, matching: motivo), findsOneWidget);
        _registrarEntero(tester, alto: 640, donde: 'GPS impreciso a 3x');

        await tester.ensureVisible(motivo);
        await tester.pump();
        expect(motivo.hitTestable(), findsOneWidget, reason: 'el motivo se alcanza desplazando');
        expect(
          tester.getRect(motivo).bottom,
          lessThanOrEqualTo(tester.getRect(_registrar).top),
          reason: 'queda justo arriba del botón',
        );
        // Aunque se desplace, el botón sigue en su lugar.
        _registrarEntero(tester, alto: 640, donde: 'después de llevar el motivo a la vista');
      },
    );

    testWidgets('sin ubicación, el motivo «Marcá el punto…» está a la vista a texto 2x', (
      tester,
    ) async {
      await _montar(tester, _Artboard.sinGps, escala: 2);

      expect(find.text(TextosAlta.marcaElPunto), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      final motivo = tester.getRect(find.text(TextosAlta.marcaElPunto));
      expect(motivo.bottom, lessThanOrEqualTo(640), reason: 'el motivo no se corta');
      expect(find.text(TextosAlta.marcaElPunto).hitTestable(), findsOneWidget);
    });
  });

  group('#320 · el motivo de «Registrar» apagado también se ve con el teclado abierto', () {
    // Los tres motivos que el canvas dibuja bajo el botón apagado, con el estado que los provoca.
    final motivos = <(_Artboard, String)>[
      (_Artboard.gpsPreciso, TextosAlta.elegiElTipo),
      (_Artboard.gpsImpreciso, TextosAlta.elegiPrecision),
      (_Artboard.sinGps, TextosAlta.marcaElPunto),
    ];

    /// El área de la hoja que se desplaza, la que queda entre el asa de la hoja y el botón fijo.
    Rect areaQueSeDesplaza(WidgetTester tester) => tester.getRect(_desplazable);

    /// El campo entero dentro del área que se desplaza y sobre el botón fijo.
    void campoEntero(WidgetTester tester, Finder campo, {required String donde}) {
      final c = tester.getRect(campo);
      final area = areaQueSeDesplaza(tester);
      expect(c.top, greaterThanOrEqualTo(area.top - .5), reason: '$donde: el campo se corta ($c)');
      expect(
        c.bottom,
        lessThanOrEqualTo(area.bottom + .5),
        reason: '$donde: el campo se corta abajo ($c en $area)',
      );
      expect(c.bottom, lessThanOrEqualTo(tester.getRect(_registrar).top + .5), reason: donde);
    }

    /// El motivo a la vista: debajo del botón y por encima del teclado, o en lo que se desplaza
    /// (arriba del botón) si se lleva con el dedo.
    Future<void> motivoALaVista(
      WidgetTester tester,
      String texto, {
      required double alto,
      required String donde,
    }) async {
      final motivo = find.text(texto);
      expect(motivo, findsOneWidget, reason: '$donde: el motivo está');
      final enLoQueSeDesplaza = find
          .descendant(of: _desplazable, matching: motivo)
          .evaluate()
          .isNotEmpty;
      if (enLoQueSeDesplaza) {
        await tester.ensureVisible(motivo);
        await tester.pump();
        final r = tester.getRect(motivo);
        final area = areaQueSeDesplaza(tester);
        expect(r.top, greaterThanOrEqualTo(area.top - .5), reason: '$donde: empieza a la vista');
        if (r.height <= area.height) {
          expect(motivo.hitTestable(), findsOneWidget, reason: '$donde: el motivo se alcanza');
          expect(
            r.bottom,
            lessThanOrEqualTo(tester.getRect(_registrar).top + .5),
            reason: '$donde: el motivo queda justo arriba del botón',
          );
        } else {
          // Más alto que el área (a 3x con el teclado): se ve desde su primer renglón y el resto se
          // lee desplazando.
          expect(r.top, lessThan(area.bottom - 8), reason: '$donde: su primer renglón se ve');
        }
      } else {
        final r = tester.getRect(motivo);
        expect(
          r.top,
          greaterThanOrEqualTo(tester.getRect(_registrar).bottom - .5),
          reason: '$donde: el motivo va debajo del botón',
        );
        expect(r.bottom, lessThanOrEqualTo(alto + .5), reason: '$donde: el motivo se corta ($r)');
        expect(motivo.hitTestable(), findsOneWidget, reason: '$donde: el motivo se ve');
      }
    }

    for (final (artboard, texto) in motivos) {
      for (final escala in [1.0, 2.0]) {
        testWidgets(
          '${artboard.rotulo} a 360×640 y texto ${escala}x con el teclado abierto: el motivo está, '
          '«Registrar» entero sobre el teclado y el número que se escribe se ve entero',
          (tester) async {
            await _montar(tester, artboard, escala: escala, teclado: true);
            const alto = 640 - _teclado;

            _registrarEntero(tester, alto: alto, donde: 'teclado abierto');
            expect(_habilitado(tester), isFalse, reason: 'sin tipo elegido no se registra');
            expect(find.text(texto), findsOneWidget, reason: 'el motivo está');

            // Se escribe el número (como lo haría el colportor): la hoja lleva el campo a la vista,
            // entero, y el motivo sigue ahí.
            await tester.enterText(_campoNumero, '1240');
            await asentar(tester);
            campoEntero(tester, _campoNumero, donde: 'escribiendo el número');
            _registrarEntero(tester, alto: alto, donde: 'escribiendo el número');
            expect(find.text(texto), findsOneWidget, reason: 'el motivo no se va al escribir');
            expect(find.widgetWithText(TextField, '1240'), findsOneWidget);

            // Y el motivo se alcanza: debajo del botón, por encima del teclado, o desplazando.
            await motivoALaVista(tester, texto, alto: alto, donde: 'teclado abierto');
          },
        );
      }
    }

    testWidgets('a 360×640 y texto 1x el motivo queda debajo del botón también con el teclado', (
      tester,
    ) async {
      await _montar(tester, _Artboard.gpsPreciso, teclado: true);

      final motivo = find.text(TextosAlta.elegiElTipo);
      expect(find.descendant(of: _desplazable, matching: motivo), findsNothing);
      expect(
        tester.getRect(motivo).top,
        greaterThanOrEqualTo(tester.getRect(_registrar).bottom),
        reason: 'como en el canvas: debajo de «Registrar»',
      );
      expect(tester.getRect(motivo).bottom, lessThanOrEqualTo(640 - _teclado));
    });

    testWidgets(
      'si debajo del botón el motivo le dejara al campo menos que su alto, pasa a lo que se '
      'desplaza (gana ver lo que se escribe)',
      (tester) async {
        // Un teclado cada vez más alto achica la hoja: el motivo está siempre y, mientras va debajo
        // del botón, lo que se desplaza todavía deja ver un campo entero.
        await _montar(tester, _Artboard.gpsPreciso);
        final campo = tester.getRect(_campoNumero).height;
        var debajo = 0;
        var enLoQueSeDesplaza = 0;
        for (var teclado = 280.0; teclado <= 400; teclado += 4) {
          tester.view.viewInsets = FakeViewPadding(bottom: teclado);
          await tester.pumpAndSettle();
          final donde = 'teclado de ${teclado.toInt()} dp';

          final motivo = find.text(TextosAlta.elegiElTipo);
          expect(motivo, findsOneWidget, reason: '$donde: el motivo está');
          final seDesplaza = find
              .descendant(of: _desplazable, matching: motivo)
              .evaluate()
              .isNotEmpty;
          if (seDesplaza) {
            enLoQueSeDesplaza++;
          } else {
            debajo++;
            expect(
              areaQueSeDesplaza(tester).height,
              greaterThanOrEqualTo(campo),
              reason: '$donde: con el motivo debajo del botón, el campo ya no entra entero',
            );
          }
          _registrarEntero(tester, alto: 640 - teclado, donde: donde);
        }
        expect(debajo, greaterThan(0), reason: 'con los teclados bajos el motivo va debajo');
        expect(
          enLoQueSeDesplaza,
          greaterThan(0),
          reason: 'con los altos pasa a lo que se desplaza',
        );
      },
    );

    testWidgets('a texto 3x con el teclado abierto el motivo también está y se alcanza', (
      tester,
    ) async {
      await _montar(tester, _Artboard.gpsImpreciso, escala: 3, teclado: true);

      _registrarEntero(tester, alto: 640 - _teclado, donde: 'a 3x con el teclado');
      await motivoALaVista(
        tester,
        TextosAlta.elegiPrecision,
        alto: 640 - _teclado,
        donde: 'a 3x con el teclado',
      );
    });

    testWidgets(
      'elegido el tipo con el teclado abierto, el motivo se va y «Registrar» se habilita',
      (tester) async {
        final repo = await _montar(tester, _Artboard.gpsPreciso, escala: 2, teclado: true);
        expect(find.text(TextosAlta.elegiElTipo), findsOneWidget);

        await tocar(tester, find.text('Casa'));

        expect(find.text(TextosAlta.elegiElTipo), findsNothing);
        expect(_habilitado(tester), isTrue);
        _registrarEntero(tester, alto: 640 - _teclado, donde: 'con «Casa» y el teclado');

        await tester.tap(_registrar);
        await asentar(tester);
        expect(repo.llamadas, hasLength(1));
      },
    );

    testWidgets(
      'abrir y cerrar el teclado dos veces seguidas: el motivo no se duplica ni se pierde y '
      '«Registrar» no se mueve del pie',
      (tester) async {
        await _montar(tester, _Artboard.gpsPreciso, escala: 2);
        final sinTeclado = tester.getRect(_registrar);

        for (var vez = 0; vez < 2; vez++) {
          await _abrirTeclado(tester);
          expect(find.text(TextosAlta.elegiElTipo), findsOneWidget, reason: 'abierto, vuelta $vez');
          _registrarEntero(tester, alto: 640 - _teclado, donde: 'abierto, vuelta $vez');

          await _cerrarTeclado(tester);
          expect(find.text(TextosAlta.elegiElTipo), findsOneWidget, reason: 'cerrado, vuelta $vez');
          expect(tester.getRect(_registrar), sinTeclado, reason: 'cerrado, vuelta $vez');
        }
      },
    );

    testWidgets('volver atrás y reentrar con el teclado abierto: el motivo está de nuevo', (
      tester,
    ) async {
      await _montar(tester, _Artboard.gpsPreciso, escala: 2, teclado: true);
      await tester.enterText(_campoNumero, '1240');
      await asentar(tester);

      await tester.tap(find.byTooltip(TextosAlta.cerrar));
      await tester.pumpAndSettle();
      expect(find.text(TextosAlta.titulo), findsNothing);

      await tester.tap(find.text('abrir'));
      await asentar(tester);
      await tester.pumpAndSettle();

      expect(find.text(TextosAlta.titulo), findsOneWidget);
      expect(find.widgetWithText(TextField, '1240'), findsNothing, reason: 'arranca de cero');
      expect(find.text(TextosAlta.elegiElTipo), findsOneWidget);
      _registrarEntero(tester, alto: 640 - _teclado, donde: 'al reentrar con el teclado');
    });

    testWidgets(
      'datos límite: calle de 120 caracteres y número de 20 a texto 2x con el teclado abierto',
      (tester) async {
        await _montar(tester, _Artboard.gpsPreciso, escala: 2, teclado: true);
        await tester.enterText(
          _campoCalle,
          List.filled(12, 'Avenida Ñandú').join(' ').substring(0, 120),
        );
        await tester.enterText(_campoNumero, '12345678901234567890');
        await asentar(tester);

        _registrarEntero(tester, alto: 640 - _teclado, donde: 'con textos largos y teclado');
        campoEntero(tester, _campoNumero, donde: 'con textos largos y teclado');
        await motivoALaVista(
          tester,
          TextosAlta.elegiElTipo,
          alto: 640 - _teclado,
          donde: 'con textos largos y teclado',
        );
      },
    );
  });

  group('#305 · «Activar GPS» y los avisos de arriba siguen a mano', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('a 360×640 y texto ${escala}x «Activar GPS» se alcanza y se puede tocar', (
        tester,
      ) async {
        final gps = gpsSinPermiso;
        await montarAlta(tester, gps: gps, tamano: _telefonoChico, escala: escala);
        await tester.pumpAndSettle();

        final activar = find.text('Activar GPS');
        await tester.ensureVisible(activar);
        await tester.pump();
        expect(activar.hitTestable(), findsOneWidget, reason: '«Activar GPS» se alcanza');
        await tester.tap(activar);
        await asentar(tester);
        expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
        _registrarEntero(tester, alto: 640, donde: 'después de activar el GPS');
      });
    }

    testWidgets('el aviso «Sin conexión…» se desplaza con el resto y «Registrar» sigue entero', (
      tester,
    ) async {
      await _montar(tester, _Artboard.sinGpsYSinConexion, escala: 2);

      expect(find.byType(AvisoMapaConectado), findsOneWidget);
      expect(
        find.descendant(of: _desplazable, matching: find.byType(AvisoMapaConectado)),
        findsOneWidget,
        reason: 'el aviso va dentro de lo que se desplaza',
      );
      _registrarEntero(tester, alto: 640, donde: 'con los dos avisos');
    });
  });

  group('#305 · casos límite de la acción', () {
    testWidgets('doble toque en el botón fijo a 360×640 y texto 2x: una sola ubicación', (
      tester,
    ) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final salidas = await montarAlta(tester, repo: repo, tamano: _telefonoChico, escala: 2);
      await tocar(tester, find.text('Casa'));

      await tester.tap(_registrar);
      await tester.pump();
      await tester.tap(_registrar, warnIfMissed: false);
      repo.bloqueo!.complete();
      await asentar(tester);

      expect(repo.llamadas, hasLength(1));
      expect(salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('mientras guarda: «Registrando…» deshabilitado y a la vista, y nada se desplaza', (
      tester,
    ) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      await montarAlta(tester, repo: repo, tamano: _telefonoChico, escala: 2);
      await tocar(tester, find.text('Casa'));

      await tester.tap(_registrar);
      await asentar(tester);

      expect(find.text(TextosAlta.registrando), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      _registrarEntero(tester, alto: 640, donde: 'guardando');

      repo.bloqueo!.complete();
      await asentar(tester);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'si falla a mitad (texto ${escala}x): el aviso se lleva a la vista arriba del botón, '
        '«Registrar» vuelve a habilitarse y lo escrito queda',
        (tester) async {
          var intento = 0;
          final repo = RepoAltaFalso()
            ..comportamiento = (u) async => ++intento == 1
                ? const Left(FailureInesperado())
                : Right(AltaRegistrada(ubicacion: u));
          final salidas = await montarAlta(
            tester,
            repo: repo,
            tamano: _telefonoChico,
            escala: escala,
          );
          await tocar(tester, find.text('Casa'));
          await tester.enterText(_campoNumero, '1240');
          await asentar(tester);
          // Arriba de todo: el aviso de falla está al final de lo que se desplaza.
          await tester.drag(_desplazable, const Offset(0, 600));
          await tester.pump();

          await tester.tap(_registrar);
          await asentar(tester);

          final aviso = find.text(TextosAlta.noPudimosGuardar);
          expect(aviso, findsOneWidget);
          expect(aviso.hitTestable(), findsOneWidget, reason: 'el aviso de falla se ve');
          expect(
            tester.getRect(aviso).bottom,
            lessThanOrEqualTo(tester.getRect(_registrar).top),
            reason: 'el aviso queda arriba del botón fijo, no debajo',
          );
          expect(_habilitado(tester), isTrue, reason: 'el botón vuelve a habilitarse');
          expect(
            find.text(TextosAlta.registrar),
            findsOneWidget,
            reason: 'no queda «Registrando…»',
          );
          expect(find.widgetWithText(TextField, '1240'), findsOneWidget);
          expect(salidas, isEmpty);

          await tester.tap(_registrar);
          await asentar(tester);
          expect(salidas.single, isA<UbicacionCreada>());
        },
      );
    }

    testWidgets('dos fallas seguidas: el aviso se vuelve a llevar a la vista la segunda vez', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          intento++;
          if (intento == 1) return const Left(FailureInesperado());
          if (intento == 2) return const Left(FailureSinConexion());
          return Right(AltaRegistrada(ubicacion: u));
        };
      await montarAlta(tester, repo: repo, tamano: _telefonoChico, escala: 2);
      await tocar(tester, find.text('Casa'));

      await tester.tap(_registrar);
      await asentar(tester);
      expect(find.text(TextosAlta.noPudimosGuardar).hitTestable(), findsOneWidget);

      await tester.drag(_desplazable, const Offset(0, 600));
      await tester.pump();
      await tester.tap(_registrar);
      await asentar(tester);

      expect(find.text(TextosAlta.noPudimosGuardar), findsNothing);
      final segundo = find.textContaining('conexión');
      expect(segundo, findsWidgets);
      expect(
        find.descendant(of: _desplazable, matching: segundo).hitTestable(),
        findsWidgets,
        reason: 'el segundo aviso también se lleva a la vista',
      );
      expect(_habilitado(tester), isTrue);
    });

    testWidgets('volver atrás y reentrar: la hoja arranca de cero y «Registrar» está entero', (
      tester,
    ) async {
      await montarAlta(tester, tamano: _telefonoChico, escala: 2);
      await tocar(tester, find.text('Casa'));
      await tester.enterText(_campoNumero, '1240');
      await asentar(tester);

      await tester.tap(find.byTooltip(TextosAlta.cerrar));
      await tester.pumpAndSettle();
      expect(find.text(TextosAlta.titulo), findsNothing);

      await tester.tap(find.text('abrir'));
      await asentar(tester);
      await tester.pumpAndSettle();

      expect(find.text(TextosAlta.titulo), findsOneWidget);
      expect(find.text(TextosAlta.elegiElTipo), findsOneWidget, reason: 'sin tipo elegido');
      expect(find.widgetWithText(TextField, '1240'), findsNothing);
      _registrarEntero(tester, alto: 640, donde: 'al reentrar');
    });

    testWidgets('datos límite: calle de 120 caracteres y número de 20 a texto 2x, sin desborde', (
      tester,
    ) async {
      await montarAlta(tester, tamano: _telefonoChico, escala: 2);
      await tocar(tester, find.text('Casa'));
      await tester.enterText(
        _campoCalle,
        List.filled(12, 'Avenida Ñandú').join(' ').substring(0, 120),
      );
      await tester.enterText(_campoNumero, '12345678901234567890');
      await asentar(tester);

      _registrarEntero(tester, alto: 640, donde: 'con textos largos');
      await _abrirTeclado(tester);
      _registrarEntero(tester, alto: 640 - _teclado, donde: 'con textos largos y teclado');
    });
  });

  group('#305 · los rótulos de la 03 sobre el mapa escalan con el texto y no tapan el pin', () {
    // El chip del GPS y la pista: dos estados del chip que el canvas dibuja distinto («GPS ±6 m» con
    // punto, «Sin GPS» sin él) y la lectura todavía en curso.
    final chips = <(String, Future<void> Function(WidgetTester, double))>[
      ('GPS ±6 m', (t, e) => _montar(t, _Artboard.gpsPreciso, escala: e)),
      ('Sin GPS', (t, e) => _montar(t, _Artboard.sinGps, escala: e)),
      ('GPS ±85 m', (t, e) => _montar(t, _Artboard.gpsImpreciso, escala: e)),
    ];

    for (final (texto, montar) in chips) {
      for (final escala in [1.0, 1.3, 2.0]) {
        testWidgets('«$texto» a 360×640 y texto ${escala}x: escala y no toca el pin ni la pista', (
          tester,
        ) async {
          await montar(tester, escala);
          await tester.pumpAndSettle();

          final parrafo = tester.renderObject<RenderParagraph>(find.text(texto));
          expect(parrafo.textScaler.scale(1), escala, reason: 'el chip escala con el texto');
          final chip = tester.getRect(
            find.ancestor(
              of: find.text(texto),
              matching: find.byWidgetPredicate((w) => w is Material && w.elevation == 2),
            ),
          );
          final pin = tester.getRect(find.byType(PinAlta));
          expect(chip.overlaps(pin), isFalse, reason: 'el chip $chip tapa el pin $pin');
          expect(
            chip.bottom,
            lessThanOrEqualTo(pin.top),
            reason: 'el chip queda arriba del pin, como en el canvas',
          );
          final mapa = tester.getRect(find.byType(MapaAlta));
          expect(mapa.contains(pin.bottomCenter), isTrue, reason: 'el pin sigue a la vista');
          // «Cerrar», a la izquierda del chip, tampoco se pisa con él.
          final cerrar = tester.getRect(find.byTooltip(TextosAlta.cerrar));
          expect(cerrar.overlaps(chip), isFalse);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('buscando el GPS («Buscando GPS…») a texto 2x tampoco toca el pin', (tester) async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      await montarAlta(tester, gps: gps, tamano: _telefonoChico, escala: 2);
      addTearDown(() {
        if (!gps.bloqueo!.isCompleted) gps.bloqueo!.complete();
      });

      final chip = tester.getRect(
        find.ancestor(
          of: find.text(TextosAlta.buscandoGps),
          matching: find.byWidgetPredicate((w) => w is Material && w.elevation == 2),
        ),
      );
      final pin = tester.getRect(find.byType(PinAlta));
      expect(chip.overlaps(pin), isFalse, reason: 'el chip $chip tapa el pin $pin');
    });
  });
}
