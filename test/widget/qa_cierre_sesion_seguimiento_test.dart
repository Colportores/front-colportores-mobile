// QA del seguimiento de la vista 16 (#225, PR #258): el aviso «Cerraste sesión…» solo sale del
// cierre iniciado en Configuración, y el título y el correo se leen a su tamaño (360x640, texto 2.0).
import 'dart:typed_data';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _password = 'Secreto123';

final class _SinDatosLocales implements DatosLocalesRepository {
  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async => const Right(
    ResumenDatosLocales(
      personas: 0,
      visitas: 0,
      operacionesSinSincronizar: 0,
      hayBackupEnDrive: false,
    ),
  );

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
  }) async => const Right(ResultadoBorradoDatosLocales.completo);
}

const _textoAviso =
    'Cerraste sesión en este teléfono. Se va a cerrar por completo cuando haya conexión.';

void main() {
  group('QA 16 seguimiento — el aviso «Cerraste sesión…» no sale de otros cierres', () {
    testWidgets('cierre sin red desde la preparación de la base: login sin el aviso', (
      tester,
    ) async {
      final remoto = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': _password},
      );
      // Una DB ya creada cuya clave se perdió y sin envoltorio: la preparación falla y ofrece
      // «Cerrar sesión».
      final db = DbLocalRepositoryEnMemoria()
        ..marca = MarcaDbLocal.puesta
        ..archivo = true
        ..claveDelArchivo = Uint8List.fromList(List<int>.filled(32, 9))
        ..dekEnAlmacen = null
        ..envoltorio = null;
      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(remoto),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          dbLocalRepositoryProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);
      await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: 'ana@example.com', password: _password);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ColportoresApp()),
      );
      await tester.pumpAndSettle();
      remoto.simularSinConexion = true;

      final cerrar = find.byKey(const Key('preparacion_db_cerrar_sesion'));
      await tester.ensureVisible(cerrar);
      await tester.tap(cerrar);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
      expect(find.text(_textoAviso), findsNothing);
      expect(find.byKey(const Key('login_aviso_sesion')), findsNothing);
    });
  });

  group('QA 16 seguimiento — texto 2.0 a 360x640', () {
    Future<void> abrirConfiguracion(WidgetTester tester, String email) async {
      final container = ProviderContainer(
        overrides: [
          authRemoteDataSourceProvider.overrideWithValue(
            AuthRemoteDataSourceEnMemoria(credenciales: {email: _password}),
          ),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          datosLocalesRepositoryProvider.overrideWithValue(_SinDatosLocales()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(sesionProvider.future);
      await container
          .read(sesionProvider.notifier)
          .iniciarSesion(email: email, password: _password);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ColportoresApp()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inicio_configuracion')));
      await tester.pumpAndSettle();
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
    }

    for (final email in [
      'ana@example.com',
      'ana.rodriguez@example.com',
      'maria.fernanda.gonzalez.rodriguez@correo.com',
    ]) {
      testWidgets('el título y el correo ($email) no desbordan ni se parten', (tester) async {
        await abrirConfiguracion(tester, email);

        expect(tester.takeException(), isNull);
        for (final finder in [
          find.text('Configuración'),
          find.byKey(const Key('configuracion_email')),
        ]) {
          expect(tester.getRect(finder).right, lessThanOrEqualTo(360));
        }
      });

      testWidgets('el correo ($email) sigue legible: a su tamaño, sin encoger ni cortarse', (
        tester,
      ) async {
        await abrirConfiguracion(tester, email);

        final correo = find.byKey(const Key('configuracion_email'));
        expect(find.ancestor(of: correo, matching: find.byType(FittedBox)), findsNothing);
        final render = tester.renderObject<RenderParagraph>(correo);
        expect(render.didExceedMaxLines, isFalse, reason: 'el correo quedó cortado con elipsis');
        expect(render.textScaler.scale(14), greaterThanOrEqualTo(28));
        expect(
          find.byWidgetPredicate((w) => w is Semantics && w.properties.label == email),
          findsOneWidget,
          reason: 'la semántica lleva el correo completo, sin cortes',
        );
      });
    }
  });
}
