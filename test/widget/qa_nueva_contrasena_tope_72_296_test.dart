// QA de la vista 15 «Nueva contraseña» con el tope de 72 bytes (#296, PR #645): accesibilidad,
// tamaños, anuncio del aviso, ambas contraseñas largas, y capturas (solo con
// `--dart-define=QA_CAPTURAS=true`; no se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _tope72 = 'Es demasiado larga. Acortala.';
late RecuperacionPasswordEnMemoria _recuperacion;

Finder _k(String k) => find.byKey(Key('confirmar_recuperacion_$k'));
Finder get _guardar => _k('guardar');

Future<void> _montar(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'Vieja1234'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(_recuperacion),
      dbLocalRepositoryProvider.overrideWithValue(DbLocalRepositoryEnMemoria()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  _recuperacion.simularEnlace(EnlaceRecuperacion.valido);
  await tester.pumpAndSettle();
}

Future<void> _escribir(WidgetTester tester, String nueva, {String? repetida}) async {
  await tester.enterText(_k('nueva'), nueva);
  await tester.enterText(_k('repetida'), repetida ?? nueva);
  await tester.pump();
}

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_guardar).onPressed != null;

void _pantalla(WidgetTester tester, Size tam, {double texto = 1.0}) {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _guias(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await c.load();
  }
  final raiz = Platform.environment['FLUTTER_ROOT'];
  final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (iconos.existsSync()) {
    final c = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
    await c.load();
  }
});

Future<void> _captura(WidgetTester tester, String nombre) => tester.runAsync(() async {
  final render = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final img = await render.toImage();
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = Directory(Platform.environment['QA_OUT'] ?? '.dart_tool/qa_capturas')
    ..createSync(recursive: true);
  File('${dir.path}/$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
});

void main() {
  const capturar = bool.fromEnvironment('QA_CAPTURAS');
  setUp(() {
    _recuperacion = RecuperacionPasswordEnMemoria(passwordActual: 'Vieja1234');
  });

  final largaAscii = 'Aa1${'x' * 70}';
  final largaEmoji = 'Aa1${'😀' * 18}';

  group('QA #296 — vista 15 con la contraseña pasada de 72 bytes', () {
    for (final (nombre, tam, escala) in [
      ('360x640 x1.0', const Size(360, 640), 1.0),
      ('360x640 x2.0', const Size(360, 640), 2.0),
      ('412x915 x1.0', const Size(412, 915), 1.0),
      ('412x915 x2.0', const Size(412, 915), 2.0),
    ]) {
      testWidgets('guías de toque, etiquetas y contraste, sin overflow ($nombre)', (tester) async {
        _pantalla(tester, tam, texto: escala);
        await _montar(tester);
        await _escribir(tester, largaEmoji);
        await tester.ensureVisible(find.text(_tope72));
        await _guias(tester);
        expect(find.text(_tope72), findsOneWidget);
      });

      testWidgets('captura ($nombre)', (tester) async {
        _pantalla(tester, tam, texto: escala);
        await _cargarFuentes(tester);
        await _montar(tester);
        await _escribir(tester, largaAscii);
        await tester.pumpAndSettle();
        await _captura(tester, 'v15_larga_${tam.width.toInt()}_${escala.toInt()}');
        await tester.ensureVisible(find.text(_tope72));
        await tester.pumpAndSettle();
        await _captura(tester, 'v15_larga_aviso_${tam.width.toInt()}_${escala.toInt()}');
      }, skip: !capturar);
    }

    testWidgets('el aviso viaja en la semántica del campo (lo lee el lector de pantalla)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await _montar(tester);
        await _escribir(tester, largaAscii);
        // El aviso viaja en el nodo del campo (hint): el lector lo dice al enfocarlo, y Flutter lo
        // anuncia solo al aparecer (InputDecorator.errorText).
        expect(tester.getSemantics(find.byType(EditableText).first).hint, contains(_tope72));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('las dos contraseñas largas e iguales: «Guardar» apagado, un solo aviso, nada se '
        'envía', (tester) async {
      await _montar(tester);
      await _escribir(tester, largaAscii, repetida: largaAscii);
      expect(find.text(_tope72), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_recuperacion.actualizaciones, isEmpty);
    });

    testWidgets('rechazo del servidor por largo: lo tipeado no se pierde', (tester) async {
      await _montar(tester);
      _recuperacion.fallaAlActualizar = const PasswordDemasiadoLargaException();
      await _escribir(tester, 'NuevaClave1');
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await tester.pumpAndSettle();
      expect(find.text(_tope72), findsOneWidget);
      expect(tester.widget<TextField>(_k('nueva')).controller!.text, 'NuevaClave1');
      expect(tester.widget<TextField>(_k('repetida')).controller!.text, 'NuevaClave1');
    });

    testWidgets('con espacios que pasan los 72 bytes también avisa', (tester) async {
      await _montar(tester);
      await _escribir(tester, 'Aa1 ${'  ' * 40}');
      expect(find.text(_tope72), findsOneWidget);
      expect(_habilitado(tester), isFalse);
    });
  });
}
