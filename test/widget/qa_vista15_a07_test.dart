// QA de la vista 15, artboard 15-A07 «enlace ya usado» (HU-AUTH-005, #247). Complementa
// `confirmar_recuperacion_password_page_test.dart`: A07 en los tamaños del checklist (360x640 y
// 412x915, texto al 100 % y al 200 %), la pista que sobrevive a reiniciar la app (almacén seguro
// real, no en memoria) y que A07 nunca ofrece pedir otro enlace.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cambios_por_recuperacion_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _titulo = 'Este enlace ya fue utilizado';
const _detalle = 'Si ya cambiaste la contraseña, entrá con la nueva.';

void _pantalla(WidgetTester tester, Size tam, double texto) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
});

Future<void> _montarA07(WidgetTester tester) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(RecuperacionPasswordEnMemoria()),
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      home: const ConfirmarRecuperacionPasswordPage(enlace: EnlaceRecuperacion.usado),
    ),
  ),
);

void main() {
  group('QA #247 — 15-A07 en los tamaños del checklist', () {
    for (final (tam, texto) in const [
      (Size(360, 640), 1.0),
      (Size(360, 640), 2.0),
      (Size(412, 915), 1.0),
      (Size(412, 915), 2.0),
    ]) {
      testWidgets('${tam.width.toInt()}x${tam.height.toInt()} a ${(texto * 100).toInt()} %: textos '
          'enteros, una sola salida, sin overflow y accesible', (tester) async {
        _pantalla(tester, tam, texto);
        final semantica = tester.ensureSemantics();
        await _cargarFuentes(tester);
        await _montarA07(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(_titulo), findsOneWidget);
        expect(find.text(_detalle), findsOneWidget);
        expect(find.text('Volver al login'), findsOneWidget);
        expect(find.text('Solicitar un enlace nuevo'), findsNothing);
        expect(find.textContaining('expiró'), findsNothing);
        expect(find.byType(TextField), findsNothing, reason: 'no hay formulario');
        for (final t in [_titulo, _detalle]) {
          expect(tester.getRect(find.text(t)).right, lessThanOrEqualTo(tam.width));
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Captura fuera del repo (build/qa_capturas está en .gitignore).
        await tester.runAsync(() async {
          final render = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final img = await render.toImage();
          final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
          final dir = Directory('build/qa_capturas')..createSync(recursive: true);
          File(
            '${dir.path}/264_a07_${tam.width.toInt()}x${tam.height.toInt()}_$texto.png',
          ).writeAsBytesSync(bytes.buffer.asUint8List());
        });
        semantica.dispose();
      });
    }
  });

  group('QA #247 — la pista sobrevive a reiniciar la app', () {
    testWidgets('con el almacén seguro real: el cambio hecho antes de cerrar la app sigue '
        'contando al reabrirla dentro de la hora, y no pasada', (tester) async {
      final almacen = AlmacenSeguroEnMemoria();
      var ahora = DateTime.utc(2026, 10, 2, 12);
      final antes = CambiosPorRecuperacionEnAlmacen(almacen, ahora: () => ahora);
      await antes.registrar();
      expect(almacen.contenido.keys, [ClaveSegura.cambioPorRecuperacion]);

      // La app se cierra y se reabre: otra instancia, el mismo almacén, sin memoria compartida.
      ahora = ahora.add(const Duration(minutes: 59));
      final despues = CambiosPorRecuperacionEnAlmacen(almacen, ahora: () => ahora);
      expect(await despues.hayUnoReciente(), isTrue);

      ahora = ahora.add(const Duration(minutes: 2));
      expect(await CambiosPorRecuperacionEnAlmacen(almacen, ahora: () => ahora).hayUnoReciente(),
          isFalse);
    });

    testWidgets('sin la marca (se borró el almacén o nunca hubo) el enlace vuelve «vencido»', (
      tester,
    ) async {
      final almacen = AlmacenSeguroEnMemoria();
      final ahora = DateTime.utc(2026, 10, 2, 12);
      final cambios = CambiosPorRecuperacionEnAlmacen(almacen, ahora: () => ahora);
      expect(await cambios.hayUnoReciente(), isFalse);

      await almacen.escribir(ClaveSegura.cambioPorRecuperacion, 'no es una fecha');
      expect(await cambios.hayUnoReciente(), isFalse, reason: 'ilegible: ante la duda, vencido');
    });
  });

  testWidgets('A07 dentro de la app: el atrás del sistema también lleva al login', (tester) async {
    final recuperacion = RecuperacionPasswordEnMemoria();
    final ahora = DateTime.utc(2026, 10, 2, 12);
    final cambios = CambiosPorRecuperacionEnMemoria(ahora: () => ahora);
    await cambios.registrar();
    final container = ProviderContainer(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(recuperacion),
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        cambiosPorRecuperacionProvider.overrideWithValue(cambios),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ColportoresApp()),
    );
    await tester.pumpAndSettle();

    recuperacion.simularEnlace(EnlaceRecuperacion.vencido);
    await tester.pumpAndSettle();
    expect(find.text(_titulo), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(_titulo), findsNothing);
    expect(find.byKey(const Key('login_enviar')), findsOneWidget);
  });
}
