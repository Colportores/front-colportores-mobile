// QA de #324 / PR #342 (vistas 03 «Alta de ubicación» y 07 «Modificar ubicación», HU-UBI-001 y HU-UBI-003):
// con el teclado abierto, el campo que se escribe y la acción siguen a la vista.
//
// Mide con las fuentes reales del proyecto (con la de prueba cada letra mide un cuadrado) y de forma
// independiente de los tests del implementador: el campo se toca (no solo se le escribe), se mide contra
// la ventana que el teclado deja libre, y se mira lo que el PR no nombra: el botón «Cerrar», la
// rotación, el teclado que sube de a poco, el orden de Tab y la falla a mitad del guardado.
// Las guías de accesibilidad (que con letra real dan falsos negativos de contraste) van aparte, en
// `qa_hojas_teclado_324_guias_test.dart`.
import 'dart:async';
import 'dart:math' as math;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:dartz/dartz.dart' show Left;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_317_arnes.dart' as a;
import '../helpers/modificar_ubicacion_qa_307_arnes.dart' as m;
import '../helpers/qa_hojas_teclado_324_arnes.dart';

/// Con `--dart-define=QA_VER_HALLAZGOS=true` los tests que documentan un hallazgo corren (y fallan).
const _verHallazgos = bool.fromEnvironment('QA_VER_HALLAZGOS');

/// La barra de estado de los tests (en dp).
const _barra = 24.0;

/// Lo que cambia de una hoja a la otra: cómo se la encuentra, sus campos y su acción.
class _Hoja {
  const _Hoja({
    required this.hoja,
    required this.accion,
    required this.zona,
    required this.campos,
    required this.nombreAccion,
  });

  /// El borde (`Material`) de la hoja.
  final Finder hoja;

  /// «Registrar» o «Guardar cambios».
  final Finder accion;
  final String nombreAccion;

  /// Lo que se desplaza.
  final Finder zona;

  /// Los campos de texto que se prueban, con el texto que se les escribe.
  final List<(Finder, String, String)> campos;
}

_Hoja get _alta => _Hoja(
  hoja: find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first,
  accion: a.botonRegistrarFijo,
  nombreAccion: 'Registrar',
  zona: a.desplazable,
  campos: [(a.campoNumero, 'número', '1240'), (a.campoCalle, 'calle', 'Avenida Italia')],
);

_Hoja get _edicion => _Hoja(
  hoja: find.ancestor(of: find.byType(HojaModificarDatos), matching: find.byType(Material)).first,
  accion: m.botonGuardar,
  nombreAccion: 'Guardar cambios',
  zona: m.zonaDesplazable,
  campos: [
    (m.campoNumero, 'número', '1240'),
    (find.byType(TextField).first, 'calle', 'Avenida Italia'),
  ],
);

bool _enLaZona(_Hoja h, Finder f) => find.descendant(of: h.zona, matching: f).evaluate().isNotEmpty;

/// El botón «Cerrar» (círculo sobre el mapa).
Finder get _cerrar => find.byTooltip('Cerrar');

/// Toca cada campo de [h], le escribe y comprueba que el campo con foco se ve entero sobre el teclado,
/// que la hoja no pasa del 80 % y que la acción se alcanza entera y mide 48 dp o más de alto.
Future<void> _campoYAccionALaVista(
  WidgetTester tester,
  _Hoja h, {
  required Size tamano,
  required double teclado,
  required String donde,
  required Future<void> Function(WidgetTester) asentar,
}) async {
  final libre = tamano.height - teclado;
  expect(tester.takeException(), isNull, reason: '$donde: overflow al abrir el teclado');
  for (final (campo, nombre, texto) in h.campos) {
    await tester.ensureVisible(campo);
    await tester.pump();
    await tester.tap(campo);
    await asentar(tester);
    await tester.enterText(campo, texto);
    await asentar(tester);

    final hoja = tester.getRect(h.hoja);
    expect(
      hoja.height,
      lessThanOrEqualTo(libre * .8 + .5),
      reason: '$donde: escribiendo la $nombre la hoja pasa del 80 % del cuerpo ($hoja)',
    );
    expect(hoja.bottom, closeTo(libre, .5), reason: '$donde: la hoja apoya sobre el teclado');

    final r = tester.getRect(campo);
    expect(
      r.top,
      greaterThanOrEqualTo(_barra - .5),
      reason: '$donde: la $nombre sube a la barra ($r)',
    );
    expect(r.bottom, lessThanOrEqualTo(libre + .5), reason: '$donde: la $nombre queda tapada ($r)');
    expect(
      r.top,
      greaterThanOrEqualTo(hoja.top - .5),
      reason: '$donde: la $nombre sale de la hoja',
    );
    expect(campoConFoco(tester, campo), isTrue, reason: '$donde: la $nombre conserva el foco');
    expect(find.widgetWithText(TextField, texto), findsOneWidget);
    if (!_enLaZona(h, h.accion)) {
      final boton = tester.getRect(h.accion);
      expect(
        r.bottom,
        lessThanOrEqualTo(boton.top + .5),
        reason: '$donde: la $nombre queda detrás de «${h.nombreAccion}» ($r vs $boton)',
      );
    }
    expect(tester.takeException(), isNull, reason: '$donde: overflow escribiendo la $nombre');
  }

  if (_enLaZona(h, h.accion)) {
    await tester.ensureVisible(h.accion);
    await tester.pump();
  }
  final boton = tester.getRect(h.accion);
  expect(boton.top, greaterThanOrEqualTo(0), reason: '$donde: «${h.nombreAccion}» se corta arriba');
  expect(
    boton.bottom,
    lessThanOrEqualTo(libre + .5),
    reason: '$donde: «${h.nombreAccion}» queda tapado por el teclado ($boton)',
  );
  expect(boton.height, greaterThanOrEqualTo(48 - .5), reason: '$donde: «${h.nombreAccion}» chico');
  expect(h.accion.hitTestable(), findsOneWidget, reason: '$donde: «${h.nombreAccion}» no se toca');
  expect(tester.takeException(), isNull, reason: '$donde: overflow');
}

/// Lo que se le pide a «Cerrar» con el teclado abierto en cada celda de la matriz, y el hallazgo si hoy
/// no lo cumple. A 320×568 con texto 1× se acepta la decisión del pendiente P1 de #324 (AA 24×24); en
/// el resto, los 48 dp de la guía de Android.
({double minimo, String? hallazgo}) _exigencia(Telefono t, double escala) {
  if (t.tamano.width == 320) {
    return (
      minimo: 24,
      hallazgo: escala == 1
          ? null
          : 'de «Cerrar» quedan 22 dp a la vista (menos que los 24 de AA 2.5.8): la hoja crece al 80 %',
    );
  }
  if (escala >= 3 && t.tamano.width == 360) {
    return (
      minimo: 48,
      hallazgo: 'con texto 3× la hoja llega al 80 % y de «Cerrar» quedan 36 dp a la vista (de 48)',
    );
  }
  return (minimo: 48, hallazgo: null);
}

/// «Cerrar» se ve y se toca con el teclado abierto: la hoja no lo tapa más de lo que [minimo] deja.
void _cerrarALaVista(
  WidgetTester tester,
  _Hoja h, {
  required Size tamano,
  required double teclado,
  required String donde,
  required double minimo,
}) {
  final libre = tamano.height - teclado;
  final hoja = tester.getRect(h.hoja);
  final c = tester.getRect(_cerrar);
  final visible = math.min(c.bottom, hoja.top) - c.top;
  expect(
    visible,
    greaterThanOrEqualTo(minimo - .5),
    reason:
        '$donde: de «Cerrar» ($c) se ven ${visible.toStringAsFixed(1)} dp: la hoja ($hoja) lo tapa',
  );
  expect(
    c.bottom,
    lessThanOrEqualTo(libre + .5),
    reason: '$donde: «Cerrar» queda tapado por el teclado',
  );
  expect(c.top, greaterThanOrEqualTo(0));
  expect(c.width, greaterThanOrEqualTo(48 - .5));
  if (minimo >= 48) {
    expect(_cerrar.hitTestable(), findsOneWidget, reason: '$donde: «Cerrar» no se toca');
  }
}

/// Lleva el campo a la vista (lo desplaza) y lo toca: queda con el foco y la hoja mide lo que pide.
Future<void> _tocarCampo(
  WidgetTester tester,
  Finder campo,
  Future<void> Function(WidgetTester) asentar,
) async {
  await tester.ensureVisible(campo);
  await tester.pump();
  await tester.tap(campo);
  await asentar(tester);
}

void main() {
  setUpAll(cargarTipografias);

  // Cobertura del diseño, en el orden del canvas. Las claves son los rótulos de los artboards.
  //   03A·01 GPS preciso · 03A·02 Sin GPS o permiso denegado · 03A·03 GPS impreciso · 03A·04 Número editado
  //   (+ las variantes sin conexión y sin ciudades que el arnés del PR también monta)
  //   07·01 Editar datos · 07·02 Mover el punto · 07·03 Guardado sin conexión · 07·04 Salir con cambios
  group('QA #324 · 03 · el campo que se toca y «Registrar» se ven sobre el teclado', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in a.EstadoAlta.values) {
          testWidgets('${estado.rotulo} · ${t.nombre} · ${veces(escala)}', (tester) async {
            await a.abrirEn(tester, estado, tamano: t.tamano, escala: escala, teclado: t.teclado);
            await _campoYAccionALaVista(
              tester,
              _alta,
              tamano: t.tamano,
              teclado: t.teclado,
              donde: '${estado.rotulo} ${t.nombre} ${veces(escala)}',
              asentar: a.asentar,
            );
          });
        }
      }
    }
  });

  group('QA #324 · 03 · «Cerrar» sigue a la vista con el teclado abierto', () {
    for (final t in [...telefonos, telefonoMinimo]) {
      for (final escala in [1.0, 2.0, 3.0]) {
        for (final estado in [a.EstadoAlta.gpsPreciso, a.EstadoAlta.gpsImpreciso]) {
          final e = _exigencia(t, escala);
          testWidgets(
            '${estado.rotulo} · ${t.nombre} · ${veces(escala)}${e.hallazgo == null ? '' : ' · QA #324: ${e.hallazgo}'}',
            (tester) async {
              await a.abrirEn(tester, estado, tamano: t.tamano, escala: escala, teclado: t.teclado);
              await _tocarCampo(tester, a.campoNumero, a.asentar);
              _cerrarALaVista(
                tester,
                _alta,
                tamano: t.tamano,
                teclado: t.teclado,
                donde: '${estado.rotulo} ${t.nombre} ${veces(escala)}',
                minimo: e.minimo,
              );
            },
            skip: e.hallazgo != null && !_verHallazgos, // skip: QA #324 — ver el título del test
          );
        }
      }
    }
  });

  group('QA #324 · 07 · el campo que se toca y «Guardar cambios» se ven sobre el teclado', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        testWidgets('07·01 Editar datos · ${t.nombre} · ${veces(escala)}', (tester) async {
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await m.abrirTeclado(tester, alto: t.teclado);
          await _campoYAccionALaVista(
            tester,
            _edicion,
            tamano: t.tamano,
            teclado: t.teclado,
            donde: '07·01 ${t.nombre} ${veces(escala)}',
            asentar: m.asentar,
          );
          expect(
            find.text('Dar de baja'),
            findsNothing,
            reason: 'con el teclado no se ofrece la baja',
          );
        });
      }
    }
  });

  group('QA #324 · 07 · «Cerrar» sigue a la vista con el teclado abierto', () {
    for (final t in [...telefonos, telefonoMinimo]) {
      for (final escala in [1.0, 2.0, 3.0]) {
        final e = _exigencia(t, escala);
        testWidgets(
          '07·01 Editar datos · ${t.nombre} · ${veces(escala)}${e.hallazgo == null ? '' : ' · QA #324: ${e.hallazgo}'}',
          (tester) async {
            await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
            await m.abrirTeclado(tester, alto: t.teclado);
            await _tocarCampo(tester, m.campoNumero, m.asentar);
            _cerrarALaVista(
              tester,
              _edicion,
              tamano: t.tamano,
              teclado: t.teclado,
              donde: '07·01 ${t.nombre} ${veces(escala)}',
              minimo: e.minimo,
            );
          },
          skip: e.hallazgo != null && !_verHallazgos, // skip: QA #324 — ver el título del test
        );
      }
    }
  });

  group('QA #324 · 07 · el rótulo «EDITAR UBICACIÓN» sigue entero sobre la hoja con el teclado', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0, 3.0]) {
        final hallazgo = t.tamano.width == 360 && escala >= 2
            ? 'la hoja al 80 % corta el rótulo flotante «EDITAR UBICACIÓN» (captura 07_editar_360×640_2×)'
            : null;
        testWidgets(
          '07·01 Editar datos · ${t.nombre} · ${veces(escala)}${hallazgo == null ? '' : ' · QA #324: $hallazgo'}',
          (tester) async {
            await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
            await m.abrirTeclado(tester, alto: t.teclado);
            await _tocarCampo(tester, m.campoNumero, m.asentar);
            final rotulo = tester.getRect(find.text('EDITAR UBICACIÓN'));
            final hoja = tester.getRect(_edicion.hoja);
            expect(
              rotulo.bottom,
              lessThanOrEqualTo(hoja.top + .5),
              reason: 'rótulo $rotulo, hoja $hoja',
            );
          },
          skip: hallazgo != null && !_verHallazgos, // skip: QA #324 — ver el título del test
        );
      }
    }
  });

  group('QA #324 · 07 · los otros artboards no se rompen con la hoja que crece', () {
    for (final escala in [1.0, 2.0, 3.0]) {
      testWidgets(
        '07·02 Mover el punto · 360×640 · ${veces(escala)}: con el teclado abierto el botón '
        'no se ofrece; al cerrarlo vuelve y las dos acciones quedan enteras',
        (tester) async {
          await abrirEdicionQa(tester, escala: escala, barraInferior: 48);
          await m.abrirTeclado(tester);
          await _tocarCampo(tester, m.campoNumero, m.asentar);
          expect(find.text('Mover el punto'), findsNothing, reason: 'con el teclado no se ofrece');

          await m.cerrarTeclado(tester);
          await tester.tap(find.text('Mover el punto'));
          await m.asentar(tester);

          expect(find.text('Guardar posición'), findsOneWidget);
          for (final accion in ['Guardar posición', 'Cancelar']) {
            final f = find.text(accion);
            expect(f, findsOneWidget, reason: '«$accion»');
            final r = tester.getRect(f);
            expect(r.top, greaterThanOrEqualTo(0), reason: '«$accion» ($r)');
            expect(
              r.bottom,
              lessThanOrEqualTo(640 - 48 + .5),
              reason: '«$accion» queda debajo de la barra ($r)',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('07·03 Guardado sin conexión · con el teclado abierto: guarda, vuelve al mapa y '
        'el aviso queda a la vista', (tester) async {
      final repo = await abrirEdicionQa(tester, conexion: TipoConexion.sinConexion);
      await m.abrirTeclado(tester);
      await tester.enterText(m.campoNumero, '1240');
      await m.asentarConTeclado(tester);
      await tester.ensureVisible(m.botonGuardar);
      await tester.pump();
      await tester.tap(m.botonGuardar);
      await m.asentarConTeclado(tester);

      expect(repo.escrituras, hasLength(1));
      expect(find.text('abrir'), findsOneWidget, reason: 'vuelve al mapa');
      final aviso = find.textContaining('Cambios guardados en tu celular');
      expect(aviso, findsOneWidget);
      expect(tester.getRect(aviso).bottom, lessThanOrEqualTo(640 + .5));
      expect(tester.takeException(), isNull);
    });

    for (final escala in [1.0, 2.0, 3.0]) {
      final hallazgo = escala < 3
          ? null
          : 'el AlertDialog de «¿Descartar los cambios?» no se desplaza: a ${veces(escala)} se desborda 114 px '
                'y los botones quedan fuera de la pantalla (previo al PR: dialogos_modificar.dart)';
      testWidgets(
        '07·04 Salir con cambios sin guardar · 360×640 · ${veces(escala)}: el diálogo cabe y sus dos '
        'botones miden 48 dp${hallazgo == null ? '' : ' · QA #324: $hallazgo'}',
        (tester) async {
          await abrirEdicionQa(tester, escala: escala);
          await tester.enterText(m.campoNumero, '1240');
          await m.asentar(tester);
          await m.cerrarTeclado(tester);
          await tester.tap(_cerrar);
          await m.asentar(tester);

          expect(find.text('¿Descartar los cambios?'), findsOneWidget);
          for (final boton in ['Seguir editando', 'Descartar']) {
            final b = find
                .ancestor(of: find.text(boton), matching: find.bySubtype<ButtonStyleButton>())
                .first;
            final r = tester.getRect(b);
            expect(r.height, greaterThanOrEqualTo(48 - .5), reason: '«$boton» mide $r');
            expect(r.right, lessThanOrEqualTo(360 + .5));
            expect(
              r.bottom,
              lessThanOrEqualTo(640 + .5),
              reason: '«$boton» queda fuera de la pantalla ($r)',
            );
          }
          expect(tester.takeException(), isNull);
        },
        skip: hallazgo != null && !_verHallazgos, // skip: QA #324 — ver el título del test
      );
    }
  });

  group('QA #324 · tocar la acción apagada · casos límite', () {
    testWidgets('03 · tocar «Registrar» apagado 5 veces seguidas anuncia 5 veces, no registra y '
        'el foco no se mueve', (tester) async {
      final anuncios = escucharAnuncios(tester);
      final montada = await a.abrirEn(tester, a.EstadoAlta.gpsPreciso, teclado: a.tecladoAbierto);
      await _tocarCampo(tester, a.campoNumero, a.asentar);
      final foco = quienTieneElFoco(tester);
      for (var i = 0; i < 5; i++) {
        await tester.tap(a.botonRegistrarFijo);
        await tester.pump(const Duration(milliseconds: 40));
      }
      await a.asentar(tester);
      expect(anuncios, everyElement(TextosAlta.elegiElTipo));
      expect(anuncios, hasLength(5), reason: 'uno por toque');
      expect(montada.repo.llamadas, isEmpty);
      expect(quienTieneElFoco(tester), foco, reason: 'el foco no se movió');
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets(
      '03 · el motivo cambia con lo que falta: tipo, luego precisión, y el anuncio sigue al '
      'motivo vigente',
      (tester) async {
        final anuncios = escucharAnuncios(tester);
        await a.abrirEn(tester, a.EstadoAlta.gpsImpreciso, teclado: a.tecladoAbierto);
        await tester.tap(a.botonRegistrarFijo);
        await a.asentar(tester);
        expect(anuncios.last, TextosAlta.elegiPrecision, reason: 'primero la precisión');

        await tester.ensureVisible(find.text(TextosAlta.continuar));
        await tester.pump();
        await tester.tap(find.text(TextosAlta.continuar));
        await a.asentar(tester);
        await tester.tap(a.botonRegistrarFijo);
        await a.asentar(tester);
        expect(
          anuncios.last,
          TextosAlta.elegiElTipo,
          reason: 'resuelta la precisión, falta el tipo',
        );
      },
    );
  });

  group('QA #324 · 03 · la falla a mitad del guardado no traba la hoja con el teclado', () {
    testWidgets(
      'falla inesperada: aviso a la vista, lo escrito sigue, «Registrar» vuelve y reintenta',
      (tester) async {
        final montada = await a.abrirEn(tester, a.EstadoAlta.gpsPreciso, teclado: a.tecladoAbierto);
        montada.repo.comportamiento = (_) async => const Left(FailureInesperado());
        await tester.ensureVisible(find.text('Casa'));
        await tester.pump();
        await tester.tap(find.text('Casa'));
        await a.asentar(tester);
        await tester.enterText(a.campoNumero, '1240');
        await m.asentarConTeclado(tester);
        await tester.tap(a.botonRegistrarFijo);
        await m.asentarConTeclado(tester);

        expect(montada.repo.llamadas, hasLength(1));
        final aviso = find.text(TextosAlta.noPudimosGuardar);
        expect(aviso, findsOneWidget, reason: 'dice qué pasó y qué hacer');
        final zona = a.zonaQueSeDesplaza(tester);
        final ra = tester.getRect(aviso);
        expect(
          ra.top,
          greaterThanOrEqualTo(zona.top - .5),
          reason: 'el aviso está fuera de la vista ($ra / $zona)',
        );
        expect(
          ra.bottom,
          lessThanOrEqualTo(zona.bottom + .5),
          reason: 'el aviso está fuera de la vista ($ra / $zona)',
        );
        expect(
          a.registrarHabilitado(tester),
          isTrue,
          reason: '«Registrar» no vuelve a habilitarse',
        );
        expect(
          find.widgetWithText(TextField, '1240'),
          findsOneWidget,
          reason: 'se perdió lo escrito',
        );
        expect(find.text(TextosAlta.registrando), findsNothing);

        // Reintenta con el teclado otra vez arriba: nada quedó trabado.
        await tester.tap(a.campoNumero);
        m.ponerTeclado(tester, a.tecladoAbierto);
        await m.asentar(tester);
        await tester.tap(a.botonRegistrarFijo);
        await m.asentarConTeclado(tester);
        expect(
          montada.repo.llamadas,
          hasLength(2),
          reason: 'el segundo intento llega al repositorio',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('sin conexión: «Necesitás conexión para …» con la acción a mano', (tester) async {
      final montada = await a.abrirEn(tester, a.EstadoAlta.gpsPreciso, teclado: a.tecladoAbierto);
      montada.repo.comportamiento = (_) async => const Left(FailureSinConexion());
      await tester.ensureVisible(find.text('Casa'));
      await tester.pump();
      await tester.tap(find.text('Casa'));
      await a.asentar(tester);
      await tester.tap(a.botonRegistrarFijo);
      await m.asentarConTeclado(tester);

      expect(find.textContaining('Necesitás conexión para'), findsOneWidget);
      expect(a.registrarHabilitado(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dos toques a «Registrar» antes de que termine el primero registran una vez', (
      tester,
    ) async {
      final montada = await a.abrirEn(tester, a.EstadoAlta.gpsPreciso, teclado: a.tecladoAbierto);
      montada.repo.bloqueo = Completer<void>();
      await tester.ensureVisible(find.text('Casa'));
      await tester.pump();
      await tester.tap(find.text('Casa'));
      await a.asentar(tester);
      await tester.tap(a.botonRegistrarFijo);
      await tester.pump();
      await tester.tap(a.botonRegistrarFijo, warnIfMissed: false);
      await tester.pump();
      expect(montada.repo.llamadas, hasLength(1));
      montada.repo.bloqueo!.complete();
      await m.asentarConTeclado(tester);
      expect(montada.repo.llamadas, hasLength(1));
    });
  });

  group('QA #324 · 07 · la falla a mitad del guardado no traba la hoja con el teclado', () {
    testWidgets('falla inesperada: aviso a la vista, lo escrito sigue y «Guardar cambios» vuelve', (
      tester,
    ) async {
      final repo = await abrirEdicionQa(tester);
      repo.comportamiento = (nueva, numero, duplicados) async => const Left(FailureInesperado());
      await m.abrirTeclado(tester);
      await tester.enterText(m.campoNumero, '1240');
      await m.asentarConTeclado(tester);
      await tester.ensureVisible(m.botonGuardar);
      await tester.pump();
      await tester.tap(m.botonGuardar);
      await m.asentarConTeclado(tester);

      expect(repo.escrituras, hasLength(1));
      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
      expect(
        find.widgetWithText(TextField, '1240'),
        findsOneWidget,
        reason: 'se perdió lo escrito',
      );
      expect(tester.widget<FilledButton>(m.botonGuardar).onPressed, isNotNull);
      expect(find.text(TextosModificar.guardando), findsNothing);
      final r = tester.getRect(find.text(TextosModificar.noPudimosGuardar));
      expect(r.bottom, lessThanOrEqualTo(640 + .5));
      expect(r.top, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #324 · rotación: horizontal con el teclado a medias', () {
    testWidgets(
      '03 · 640×360 con 180 dp de teclado: sin overflow, el número y «Registrar» se alcanzan',
      (tester) async {
        await a.abrirEn(
          tester,
          a.EstadoAlta.gpsPreciso,
          tamano: const Size(640, 360),
          teclado: 180,
        );
        await _campoYAccionALaVista(
          tester,
          _alta,
          tamano: const Size(640, 360),
          teclado: 180,
          donde: '03 horizontal',
          asentar: a.asentar,
        );
      },
    );

    testWidgets(
      '07 · 640×360 con 180 dp de teclado: sin overflow, el número y «Guardar cambios» se '
      'alcanzan',
      (tester) async {
        await abrirEdicionQa(tester, tamano: const Size(640, 360));
        await m.abrirTeclado(tester, alto: 180);
        await _campoYAccionALaVista(
          tester,
          _edicion,
          tamano: const Size(640, 360),
          teclado: 180,
          donde: '07 horizontal',
          asentar: m.asentar,
        );
      },
    );

    testWidgets(
      '03 · girar el teléfono con el teclado abierto y un texto escrito no pierde lo escrito',
      (tester) async {
        await a.abrirEn(tester, a.EstadoAlta.gpsPreciso, teclado: a.tecladoAbierto);
        await tester.enterText(a.campoNumero, '1240');
        await a.asentar(tester);
        tester.view.physicalSize = const Size(640, 360);
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await a.asentar(tester);
        expect(find.widgetWithText(TextField, '1240'), findsOneWidget);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.viewInsets = const FakeViewPadding(bottom: a.tecladoAbierto);
        await a.asentar(tester);
        expect(find.widgetWithText(TextField, '1240'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('QA #324 · el teclado que sube y baja de a poco', () {
    testWidgets('03 · 360×640: sube de a 20 dp por cuadro con el número enfocado, sin overflow en '
        'ningún cuadro, y termina igual que de golpe', (tester) async {
      await a.abrirEn(tester, a.EstadoAlta.gpsPreciso);
      await _tocarCampo(tester, a.campoNumero, a.asentar);
      for (var alto = 20.0; alto <= 300; alto += 20) {
        m.ponerTeclado(tester, alto);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'overflow con el teclado en $alto dp');
      }
      await a.asentar(tester);
      final gradual = tester.getRect(
        find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first,
      );
      final r = tester.getRect(a.campoNumero);
      expect(r.bottom, lessThanOrEqualTo(640 - 300 + .5), reason: 'el número termina tapado ($r)');

      await m.bajarTecladoDeAPoco(tester);
      await a.asentar(tester);
      expect(tester.takeException(), isNull);
      m.ponerTeclado(tester, 300);
      await a.asentar(tester);
      expect(
        tester.getRect(
          find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first,
        ),
        gradual,
        reason: 'la hoja no termina donde terminaba',
      );
    });

    testWidgets('07 · 360×640 · 2×: sube y baja de a poco con el número enfocado, sin overflow', (
      tester,
    ) async {
      await abrirEdicionQa(tester, escala: 2);
      await _tocarCampo(tester, m.campoNumero, m.asentar);
      for (var alto = 20.0; alto <= 300; alto += 20) {
        m.ponerTeclado(tester, alto);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'overflow con el teclado en $alto dp');
      }
      await m.asentar(tester);
      expect(tester.getRect(m.campoNumero).bottom, lessThanOrEqualTo(640 - 300 + .5));
      await m.bajarTecladoDeAPoco(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #324 · orden de Tab y foco', () {
    testWidgets('03 · con teclado físico, Tab recorre calle y número en orden, no se traba y vuelve '
        'a empezar', (tester) async {
      await a.abrirEn(tester, a.EstadoAlta.gpsPreciso, teclado: a.tecladoAbierto);
      await _tocarCampo(tester, a.campoCalle, a.asentar);
      expect(quienTieneElFoco(tester), 'campo#0');
      final visto = <String>[quienTieneElFoco(tester)];
      for (var i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        visto.add(quienTieneElFoco(tester));
      }
      // La calle va antes que el número, y el recorrido cierra el ciclo sin pegarse a un elemento.
      expect(visto.indexOf('campo#1'), greaterThan(visto.indexOf('campo#0')), reason: '$visto');
      expect(visto.toSet().length, greaterThan(2), reason: 'Tab no avanza: $visto');
      expect(
        visto.where((v) => v == 'campo#0').length,
        greaterThan(1),
        reason: 'no cierra el ciclo: $visto',
      );
      expect(visto, isNot(contains('(nadie)')), reason: '$visto');
      expect(tester.takeException(), isNull);
    });

    testWidgets('07 · con teclado físico, Tab recorre los campos en orden y no se traba', (
      tester,
    ) async {
      await abrirEdicionQa(tester);
      await m.abrirTeclado(tester);
      await _tocarCampo(tester, find.byType(TextField).first, m.asentar);
      final visto = <String>[quienTieneElFoco(tester)];
      for (var i = 0; i < 30; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        visto.add(quienTieneElFoco(tester));
      }
      expect(visto.first, 'campo#0');
      expect(visto.indexOf('campo#1'), greaterThan(0), reason: '$visto');
      expect(visto.toSet().length, greaterThan(2), reason: '$visto');
      expect(visto.where((v) => v == 'campo#0').length, greaterThan(1), reason: '$visto');
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #324 · datos límite con el teclado abierto', () {
    testWidgets('03 · 360×640 · 2×: pegar 500 caracteres y un emoji en la calle no rompe nada', (
      tester,
    ) async {
      await a.abrirEn(tester, a.EstadoAlta.gpsPreciso, escala: 2, teclado: a.tecladoAbierto);
      await tester.ensureVisible(a.campoCalle);
      await tester.pump();
      await tester.tap(a.campoCalle);
      await a.asentar(tester);
      await tester.enterText(a.campoCalle, '${'Avenida Italia ' * 40}😀');
      await a.asentar(tester);
      expect(tester.takeException(), isNull, reason: 'overflow con un texto largo');
      expect(
        tester
            .getRect(
              find.ancestor(of: find.byType(HojaAlta), matching: find.byType(Material)).first,
            )
            .height,
        lessThanOrEqualTo((640 - 300) * .8 + .5),
      );
      if (_enLaZona(_alta, a.botonRegistrarFijo)) {
        await tester.ensureVisible(a.botonRegistrarFijo);
        await tester.pump();
      }
      expect(tester.getRect(a.botonRegistrarFijo).bottom, lessThanOrEqualTo(640 - 300 + .5));
    });

    testWidgets('07 · 360×640 · 2×: calle vacía y solo espacios con el teclado abierto', (
      tester,
    ) async {
      await abrirEdicionQa(tester, escala: 2);
      await m.abrirTeclado(tester);
      await tester.enterText(find.byType(TextField).first, '   ');
      await m.asentar(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField).first, '');
      await m.asentar(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(m.botonGuardar);
      await tester.pump();
      expect(tester.getRect(m.botonGuardar).bottom, lessThanOrEqualTo(640 - 300 + .5));
    });
  });

  group('QA #324 · capturas (solo con --dart-define=QA_CAPTURAS=true)', () {
    for (final t in telefonos) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in a.EstadoAlta.values) {
          testWidgets('03 ${estado.name} ${t.nombre} ${veces(escala)}', (tester) async {
            await a.cargarIconosParaCapturas(tester);
            await a.abrirEn(tester, estado, tamano: t.tamano, escala: escala, teclado: t.teclado);
            await _tocarCampo(tester, a.campoNumero, a.asentar);
            await capturarEn(
              tester,
              a.raizCaptura,
              '03_${estado.name}_${t.nombre}_${veces(escala)}',
            );
          }, skip: !conCapturas);
        }
        testWidgets('07 editar ${t.nombre} ${veces(escala)}', (tester) async {
          await a.cargarIconosParaCapturas(tester);
          await abrirEdicionQa(tester, tamano: t.tamano, escala: escala);
          await m.abrirTeclado(tester, alto: t.teclado);
          await _tocarCampo(tester, m.campoNumero, m.asentar);
          await capturarEn(tester, raizQa, '07_editar_${t.nombre}_${veces(escala)}');
        }, skip: !conCapturas);
      }
    }
  });
}
