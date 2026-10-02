// QA de front-colportores-mobile#242 (HU-AUTH-002, enlace de verificación usado): casos límite que
// se superponen —«Ya verifiqué» a la vez que el login en silencio del enlace— y capturas de la
// vista 12 (A05 «ya verificado» y «enlace que ya no sirve»), que van fuera del repo.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _correo = 'lucia.silva@correo.com';
const _clave = 'Secreto123';

Future<AuthRemoteDataSourceEnMemoria> _remoto() async {
  final remote = AuthRemoteDataSourceEnMemoria(
    credenciales: const {},
    requiereVerificacionAlRegistrar: true,
  );
  await remote.registrar(
    nombre: 'Lucía',
    apellido: 'Silva',
    cedula: '12345678',
    email: _correo,
    password: _clave,
  );
  remote.confirmarEmail(_correo);
  return remote;
}

void _pantalla(WidgetTester tester, [Size tamanio = const Size(390, 844)]) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'dado «Ya verifiqué» en curso, cuando llega el enlace usado, entonces ninguna UI queda '
    'trabada y se llega a A05 y de ahí a Inicio/login',
    (tester) async {
      _pantalla(tester);
      final remote = await _remoto();
      final demora = Completer<void>();
      remote.demoraIniciarSesion = demora;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(remote),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: const ColportoresApp(),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        navigatorKeyColportores.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const VerificacionEmailPage(email: _correo, password: _clave),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('verificacion_email_ya_verifique')));
      await tester.pump();
      remote.simularEnlaceVerificacionInvalido();
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Tu email ya está verificado'), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_ir_login')), findsOneWidget);
      // No sale sola: se queda hasta que la colportora toca el botón.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Tu email ya está verificado'), findsOneWidget);

      await tester.tap(find.byKey(const Key('verificacion_email_ir_login')));
      await tester.pumpAndSettle();
      expect(find.text('Tu email ya está verificado'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );

  // Capturas: fuera del repo (qa_capturas_tmp, no se commitea).
  for (final estado in [
    EstadoVerificacionEmail.yaVerificado,
    EstadoVerificacionEmail.enlaceInutil,
  ]) {
    {
      for (final escala in [1.0, 2.0]) {
        testWidgets('captura $estado escala=$escala', (tester) async {
          _pantalla(tester, const Size(360, 640));
          await tester.runAsync(() async {
            for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
              final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
              final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
              await loader.load();
            }
          });
          final clave = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
                authRemoteDataSourceProvider.overrideWithValue(
                  AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _clave}),
                ),
                authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
              ],
              child: RepaintBoundary(
                key: clave,
                child: MaterialApp(
                  theme: temaClaro(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                    child: child!,
                  ),
                  home: VerificacionEmailPage(email: _correo, estadoInicial: estado),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final render = clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final img = await render.toImage();
            final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
            final dir = Directory('qa_capturas_tmp')..createSync(recursive: true);
            File(
              '${dir.path}/242_${estado.name}_claro_$escala.png',
            ).writeAsBytesSync(bytes.buffer.asUint8List());
          });
        });
      }
    }
  }
}
