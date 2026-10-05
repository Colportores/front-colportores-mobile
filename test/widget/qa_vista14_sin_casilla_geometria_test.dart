// QA de la vista 14 sin casilla (#272): geometría con las fuentes reales (con Ahem el texto mide
// otra cosa). Texto cortado y etiquetas que se salen de la píldora del botón con el texto al 200 %.
import 'dart:io';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _incompleto = 'Revisá el email: parece incompleto.';
const _etiquetaBoton = 'Enviar enlace de recuperación';

Finder _k(String key) => find.byKey(Key(key));

Future<void> _cargarFuentesReales() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
}

Future<void> _montar(WidgetTester tester, {required Size tamano, required double escala}) async {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(theme: temaClaro(), home: const RecuperacionPasswordPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Escribe un email incompleto y toca «Enviar…»: deja A03 a la vista.
Future<void> _llegarAA03(WidgetTester tester) async {
  await tester.enterText(_k('recuperacion_password_email'), 'lucia@');
  await tester.pump();
  await tester.ensureVisible(_k('recuperacion_password_enviar'));
  await tester.tap(_k('recuperacion_password_enviar'));
  await tester.pumpAndSettle();
}

/// Si algún punto de [p] queda fuera de la píldora (`StadiumBorder`) de [boton].
bool _fueraDeLaPildora(Rect boton, Offset p) {
  final r = boton.height / 2;
  final izq = Offset(boton.left + r, boton.center.dy);
  final der = Offset(boton.right - r, boton.center.dy);
  if (p.dx < izq.dx) return (p - izq).distance > r;
  if (p.dx > der.dx) return (p - der).distance > r;
  return (p.dy - boton.center.dy).abs() > r;
}

/// Las esquinas de cada renglón de la etiqueta del botón que quedan fuera de la píldora.
List<Offset> _esquinasFuera(WidgetTester tester) {
  final boton = tester.getRect(_k('recuperacion_password_enviar'));
  final parrafo = tester.renderObject<RenderParagraph>(
    find.descendant(of: _k('recuperacion_password_enviar'), matching: find.text(_etiquetaBoton)),
  );
  final cajas = parrafo.getBoxesForSelection(
    const TextSelection(baseOffset: 0, extentOffset: _etiquetaBoton.length),
  );
  final fuera = <Offset>[];
  for (final c in cajas) {
    for (final esquina in [
      c.left,
      c.right,
    ].expand((x) => [Offset(x, c.top), Offset(x, c.bottom)])) {
      final global = parrafo.localToGlobal(esquina);
      if (_fueraDeLaPildora(boton, global)) fuera.add(global);
    }
  }
  return fuera;
}

void main() {
  setUpAll(_cargarFuentesReales);

  group('QA #272 · vista 14 · el error del campo entero (A03)', () {
    testWidgets('a 360×640 y texto 1.0 el error cabe en un renglón', (tester) async {
      await _montar(tester, tamano: const Size(360, 640), escala: 1);
      await _llegarAA03(tester);

      final p = tester.renderObject<RenderParagraph>(find.text(_incompleto));
      expect(p.didExceedMaxLines, isFalse);
    });

    // QA #272: a texto 2x el error del campo no se corta con puntos suspensivos («Revisá el
    // email: parece…»): el `InputDecoration` pone `errorMaxLines: 3`, como las otras páginas.
    testWidgets('a 360×640 y texto 2.0 el mensaje de A03 no se corta', (tester) async {
      await _montar(tester, tamano: const Size(360, 640), escala: 2);
      await _llegarAA03(tester);

      final p = tester.renderObject<RenderParagraph>(find.text(_incompleto));
      expect(p.didExceedMaxLines, isFalse, reason: 'el error quedó cortado: «$_incompleto»');
    });
  });

  group('QA #272 · vista 14 · la etiqueta del botón dentro de la píldora', () {
    testWidgets('a 360×640 y texto 1.0 la etiqueta entra en la píldora', (tester) async {
      await _montar(tester, tamano: const Size(360, 640), escala: 1);

      expect(_esquinasFuera(tester), isEmpty);
    });

    // QA #272: a texto 2x «Enviar enlace de recuperación» pasa a dos renglones; el relleno
    // horizontal del tema (24) evita que la primera letra de cada renglón caiga sobre la curva de la
    // píldora (antes: blanco sobre el fondo, no se veía: «ecuperación»).
    testWidgets('a 360×640 y texto 2.0 ningún renglón de la etiqueta se sale de la píldora', (
      tester,
    ) async {
      await _montar(tester, tamano: const Size(360, 640), escala: 2);

      expect(_esquinasFuera(tester), isEmpty, reason: 'la etiqueta se sale de la píldora');
    });

    // Lo mismo en 412×915: al 200 % la etiqueta también pasa a dos renglones.
    testWidgets('a 412×915 y texto 2.0 la etiqueta entra en la píldora', (tester) async {
      await _montar(tester, tamano: const Size(412, 915), escala: 2);

      expect(_esquinasFuera(tester), isEmpty, reason: 'la etiqueta se sale de la píldora');
    });
  });
}
