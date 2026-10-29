// QA de #540 (PR #557): «Cerrar» de «Editar ubicación» (vista 07, HU-UBI-004) pasó de la zona del mapa a
// un `Stack` por encima del mapa y de la hoja (`modificar_ubicacion_page.dart`). Lo que mide este archivo,
// además de lo que ya prueba `qa_avisos_modificar_379_test.dart` (que «✕» abre el aviso):
//
// - 320×568 con el teclado arriba y 360×640 con texto 1,8×–2,0× (y 412×915): «Cerrar» mide 48 dp, está
//   entera en la pantalla y recibe el toque en todo el círculo (nada de la hoja se lo roba);
// - «Cerrar» no tapa ningún campo, botón ni texto de la hoja (lo que hay debajo sigue tocable);
// - el orden de lectura: «Cerrar» va antes que la hoja;
// - los estados 07·01 (editar datos) y 07·02 (mover el punto), guardando (deshabilitado) y el toque;
// - guías de accesibilidad de Flutter (toque 48/44 dp, etiquetas, contraste) y sin overflow.
//
// Capturas: `--dart-define=QA_CAPTURAS=true` las deja en `.dart_tool/qa_capturas/` (gitignored: nunca se
// commitean). Un test que documenta un hallazgo va con `skip: 'QA #540: …'`.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/modificar_ubicacion_falsos.dart' show RepoEdicionFalso, ubicacionGuardada;
import '../../helpers/modificar_ubicacion_qa_307_arnes.dart';
import '../../helpers/qa_hojas_teclado_324_arnes.dart' show conCapturas, veces;

typedef _Caso = ({String nombre, Size tamano, double escala, bool teclado, double barra});

_Caso _caso(Size tamano, double escala, {bool teclado = false, double barra = barraDeEstado}) => (
  nombre:
      '${tamano.width.round()}×${tamano.height.round()} · ${veces(escala)} · '
      '${teclado ? 'teclado arriba' : 'teclado abajo'}'
      '${barra == barraDeEstado ? '' : ' · barra de ${barra.round()} dp'}',
  tamano: tamano,
  escala: escala,
  teclado: teclado,
  barra: barra,
);

final _casos = <_Caso>[
  _caso(telefono320x568, 1, teclado: true),
  _caso(telefono320x568, 1.8, teclado: true),
  _caso(telefono320x568, 2, teclado: true),
  _caso(telefono320x568, 2, teclado: true, barra: 48),
  _caso(telefono320x568, 1),
  _caso(telefono320x568, 2),
  _caso(telefono360x640, 1.8),
  _caso(telefono360x640, 2),
  _caso(telefono360x640, 1.8, teclado: true),
  _caso(telefono360x640, 2, teclado: true),
  _caso(const Size(412, 915), 2),
  _caso(const Size(412, 915), 2, teclado: true),
];

/// Las guías de contraste de Flutter miden el pixel de la captura: con estos dos casos marcan rótulos de la
/// hoja que el desplazamiento corta a medias (no son «Cerrar»). Se prueban las demás guías.
const _sinContraste = {
  '320×568 · 1× · teclado abajo',
  '360×640 · 1,8× · teclado arriba',
  // Con la barra de 48 dp el encabezado corre su relleno izquierdo (P2 de #540) y el renglón de resumen
  // cae en el borde de lo que se desplaza: el pixel que mide la guía queda cortado a medias.
  '320×568 · 2× · teclado arriba · barra de 48 dp',
};

final _cerrar = find.ancestor(
  of: find.widgetWithIcon(IconButton, Icons.close),
  matching: find.byType(BotonRedondoMapa),
);
final _botonCerrar = find.widgetWithIcon(IconButton, Icons.close);

Future<void> _abrir(WidgetTester tester, _Caso c, {RepoEdicionFalso? repo}) async {
  await abrirEdicion(
    tester,
    tamano: c.tamano,
    escala: c.escala,
    barraSuperior: c.barra,
    repo: repo,
  );
  if (c.teclado) await abrirTeclado(tester);
}

/// Si tocar en [p] cae en [objetivo] (o en algo que cuelga de él).
bool _cae(WidgetTester tester, Offset p, RenderObject objetivo) {
  final resultado = HitTestResult();
  tester.binding.hitTestInView(resultado, p, tester.view.viewId);
  return resultado.path.any((e) => e.target == objetivo);
}

/// Nueve puntos del círculo de «Cerrar»: el centro y ocho a 0,7 del radio.
List<Offset> _puntosDelCirculo(Rect r) => [
  r.center,
  for (var i = 0; i < 8; i++)
    r.center + Offset.fromDirection(i * 3.14159265 / 4, r.width / 2 * 0.7),
];

Rect _rectDe(Element e) {
  final ro = e.renderObject! as RenderBox;
  return ro.localToGlobal(Offset.zero) & ro.size;
}

void main() {
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  group('QA #540 · «Cerrar» de 07·01 «Editar datos»', () {
    for (final c in _casos) {
      testWidgets(
        '${c.nombre}: 48 dp, entera en la pantalla y recibe el toque en todo el círculo',
        (tester) async {
          await cargarFuentesReales();
          await _abrir(tester, c);
          expect(_cerrar, findsOneWidget);

          final boton = tester.getRect(_botonCerrar);
          expect(boton.width, greaterThanOrEqualTo(48));
          expect(boton.height, greaterThanOrEqualTo(48));
          final pantalla = Offset.zero & c.tamano;
          expect(
            pantalla.contains(boton.topLeft) && pantalla.contains(boton.bottomRight),
            isTrue,
            reason: '«Cerrar» $boton se sale de la pantalla $pantalla',
          );

          final objetivo = tester.renderObject(_botonCerrar);
          final fallan = [
            for (final p in _puntosDelCirculo(boton))
              if (!_cae(tester, p, objetivo)) p,
          ];
          expect(fallan, isEmpty, reason: 'estos puntos de «Cerrar» $boton caen en otra cosa');
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('${c.nombre}: «Cerrar» no tapa ningún campo, botón ni texto de la hoja', (
        tester,
      ) async {
        await cargarFuentesReales();
        await _abrir(tester, c);
        final boton = tester.getRect(_botonCerrar);
        final visor = tester.getRect(zonaDesplazable);
        final tapados = <String>[];

        // Lo que se toca: campos y botones de la hoja (los que se ven en lo que se desplaza).
        for (final (tipo, buscador) in <(String, Finder)>[
          ('TextField', find.byType(TextField)),
          ('Botón', find.byWidgetPredicate((w) => w is ButtonStyleButton)),
        ]) {
          for (final e
              in find
                  .descendant(of: find.byType(HojaModificarDatos), matching: buscador)
                  .evaluate()) {
            final r = _rectDe(e);
            final visible = r.overlaps(visor) ? r.intersect(visor) : Rect.zero;
            final choque = visible.overlaps(boton) ? visible.intersect(boton) : Rect.zero;
            if (choque.width > 2 && choque.height > 2) {
              tapados.add('$tipo $r (se tapa $choque)');
            }
          }
        }
        // Lo que se lee: los textos de la hoja.
        for (final e
            in find
                .descendant(of: find.byType(HojaModificarDatos), matching: find.byType(Text))
                .evaluate()) {
          final r = _rectDe(e);
          final fueraDelVisor = r.bottom <= visor.top || r.top >= visor.bottom;
          final dentroDelScroll = find
              .descendant(of: zonaDesplazable, matching: find.byWidget(e.widget))
              .evaluate()
              .isNotEmpty;
          if (dentroDelScroll && fueraDelVisor) continue;
          final choque = r.overlaps(boton) ? r.intersect(boton) : Rect.zero;
          if (choque.width > 2 && choque.height > 2) {
            tapados.add('Text «${(e.widget as Text).data}» $r (se tapa $choque)');
          }
        }
        expect(tapados, isEmpty, reason: '«Cerrar» $boton tapa: ${tapados.join('; ')}');
      });
    }

    testWidgets(
      '«Cerrar» va antes que la hoja en el orden de lectura (320×568, teclado arriba, 2×)',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await _abrir(tester, _caso(telefono320x568, 2, teclado: true));
        final raiz = tester.binding.rootElement!.renderObject!.debugSemantics!;
        final orden = raiz
            .toStringDeep(childOrder: DebugSemanticsDumpOrder.traversalOrder)
            .split('\n')
            .where((l) => l.contains('tooltip: "Cerrar"') || l.contains('label: "Av. Italia 1234"'))
            .toList();
        expect(orden, hasLength(2));
        expect(
          orden.first,
          contains('Cerrar'),
          reason: 'el lector llega a la hoja antes que a «Cerrar»',
        );
        semantica.dispose();
      },
    );

    testWidgets(
      'tocar «Cerrar» sin cambios vuelve a la pantalla de abajo (320×568, 2×, teclado arriba)',
      (tester) async {
        await _abrir(tester, _caso(telefono320x568, 2, teclado: true));
        await tester.tap(_botonCerrar);
        await asentar(tester, 14);
        expect(find.text('abrir'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'con lo escrito sin guardar, «Cerrar» pregunta antes de descartar y «Seguir editando» conserva lo escrito',
      (tester) async {
        await _abrir(tester, _caso(telefono320x568, 2, teclado: true));
        await tester.enterText(campoNumero, '1299');
        await asentarConTeclado(tester);
        await tester.tap(_botonCerrar);
        await asentarConTeclado(tester, 14);
        expect(find.text('¿Descartar los cambios?'), findsOneWidget);
        await tester.ensureVisible(find.text('Seguir editando'));
        await tester.pump();
        await tester.tap(find.text('Seguir editando'));
        await asentarConTeclado(tester, 14);
        expect(
          find.widgetWithText(TextField, '1299'),
          findsOneWidget,
          reason: 'se perdió lo escrito',
        );
        expect(find.text('abrir'), findsNothing);
      },
    );

    testWidgets('guardando, «Cerrar» queda deshabilitado y al terminar la hoja no queda trabada', (
      tester,
    ) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoEscritura = Completer<void>();
      await abrirEdicion(tester, repo: repo);
      await tester.enterText(campoNumero, '1299');
      await asentar(tester);
      await tester.ensureVisible(botonGuardar);
      await tester.pump();
      await tester.tap(botonGuardar);
      await asentar(tester, 4);
      expect(
        tester.widget<IconButton>(_botonCerrar).onPressed,
        isNull,
        reason: '«Cerrar» sigue activo guardando',
      );
      repo.bloqueoEscritura!.complete();
      await asentar(tester, 20);
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #540 · «Cerrar» de 07·02 «Mover el punto»', () {
    for (final c in [
      _caso(telefono320x568, 2),
      _caso(telefono360x640, 2),
      _caso(telefono360x640, 1),
    ]) {
      testWidgets(
        '${c.nombre}: «Cerrar» recibe el toque y no choca con «Volver a mi ubicación» ni el título',
        (tester) async {
          await cargarFuentesReales();
          await _abrir(tester, c);
          final mover = find.text(TextosModificar.moverElPunto);
          await tester.ensureVisible(mover);
          await tester.pump();
          await tester.tap(mover);
          await asentar(tester, 14);

          final boton = tester.getRect(_botonCerrar);
          final objetivo = tester.renderObject(_botonCerrar);
          final fallan = [
            for (final p in _puntosDelCirculo(boton))
              if (!_cae(tester, p, objetivo)) p,
          ];
          expect(fallan, isEmpty, reason: '«Cerrar» $boton: puntos que caen en otra cosa');

          // Ningún otro botón redondo (p. ej. «Volver a mi ubicación») ni texto flotante pisa a «Cerrar».
          final pisan = <String>[];
          for (final e in find.byType(Text).evaluate()) {
            if (e.findAncestorWidgetOfExactType<BotonRedondoMapa>() != null) continue;
            final r = _rectDe(e);
            final choque = r.overlaps(boton) ? r.intersect(boton) : Rect.zero;
            if (choque.width > 2 && choque.height > 2) pisan.add('«${(e.widget as Text).data}» $r');
          }
          expect(
            pisan,
            isEmpty,
            reason: 'estos textos pisan a «Cerrar» $boton: ${pisan.join('; ')}',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group(
    'QA #540 · guías de accesibilidad con «Cerrar» (sin fuentes reales: el contraste da falsos negativos con ellas)',
    () {
      for (final c in _casos) {
        testWidgets(c.nombre, (tester) async {
          final semantica = tester.ensureSemantics();
          await _abrir(tester, c);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (!_sinContraste.contains(c.nombre)) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          }
          semantica.dispose();
        });
      }
    },
  );

  group('QA #540 · capturas (solo con --dart-define=QA_CAPTURAS=true)', () {
    for (final c in _casos) {
      testWidgets(c.nombre, (tester) async {
        await cargarFuentesReales();
        await cargarIconosParaCapturas(tester);
        await _abrir(tester, c);
        await capturar(
          tester,
          '540_cerrar_${c.tamano.width.round()}x${c.tamano.height.round()}_${veces(c.escala)}'
          '${c.teclado ? '_teclado' : ''}${c.barra == barraDeEstado ? '' : '_barra${c.barra.round()}'}',
        );
      }, skip: !conCapturas);
    }
  });
}
