// QA de la vista 17 (HU-AUTH-007, #226), complemento de sesion_vencida_vista17_test.dart: tema
// oscuro y privacidad y avisos superpuestos.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final _cerrar = find.byKey(const Key('login_aviso_sesion_cerrar'));

SesionModel _sesionVencidaHace(Duration sinUso) => SesionModel(
  usuarioId: '01920000-0000-7000-8000-000000000001',
  email: 'lucia.silva@correo.com',
  accessToken: 'jwt',
  expiraEn: DateTime.now().toUtc().subtract(sinUso).add(const Duration(days: 30)),
);

class _Entorno {
  _Entorno(this.remoto, this.db);

  final AuthRemoteDataSourceEnMemoria remoto;
  final DbLocalRepositoryEnMemoria db;
}

void _pantalla(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Monta la app con la sesión de Lucía iniciada (o, con [vencidaHace], guardada y ya vencida).
Future<_Entorno> _montar(WidgetTester tester, {Duration? vencidaHace}) async {
  final remoto = AuthRemoteDataSourceEnMemoria(
    credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
  );
  final local = AuthLocalDataSourceEnMemoria();
  await local.guardarSesion(_sesionVencidaHace(vencidaHace ?? const Duration(days: 1)));
  final db = dbLocalYaPreparada();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(db),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(local),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  return _Entorno(remoto, db);
}

Future<void> _expirar(WidgetTester tester, _Entorno e, MotivoExpiracion motivo) async {
  e.remoto.simularExpiracion(motivo);
  await tester.pumpAndSettle();
}

ProviderContainer _contenedor(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

void main() {
  // La app solo tiene tema claro (app.dart: temaClaro): no hay tema oscuro que probar.
  for (final oscuro in [false]) {
    final tema = oscuro ? 'oscuro' : 'claro';
    for (final (tam, texto) in [(const Size(412, 915), 1.0), (const Size(360, 640), 2.0)]) {
      final etiqueta = '${tam.width.toInt()}x${tam.height.toInt()} x$texto';
      testWidgets('tema $tema $etiqueta: A01, A03 y A04 sin overflow y con las guías', (
        tester,
      ) async {
        _pantalla(tester, tam, texto: texto);
        tester.platformDispatcher.platformBrightnessTestValue = oscuro
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final semantica = tester.ensureSemantics();
        final e = await _montar(tester);
        await _expirar(tester, e, MotivoExpiracion.inactividad);
        await _guias(tester);

        _contenedor(
          tester,
        ).read(avisoSesionProvider.notifier).mostrar(const FailureSesionRevocada());
        await tester.pumpAndSettle();
        await _guias(tester);

        await tester.ensureVisible(_cerrar);
        await tester.tap(_cerrar);
        await tester.pumpAndSettle();
        await _guias(tester);
        semantica.dispose();
      });
    }
  }

  testWidgets('los datos del reingreso no salen en toString (privacidad)', (tester) async {
    const datos = DatosReingreso(
      motivo: MotivoExpiracion.inactividad,
      email: 'lucia.silva@correo.com',
      nombre: 'Lucía',
    );
    expect(datos.toString(), isNot(contains('lucia')));
    expect(datos.toString(), isNot(contains('Lucía')));
  });

  testWidgets('dos avisos de sesión seguidos: el correo de la cuenta no se pierde', (tester) async {
    final e = await _montar(tester);
    await _expirar(tester, e, MotivoExpiracion.inactividad);
    await _expirar(tester, e, MotivoExpiracion.revocada);
    expect(_contenedor(tester).read(reingresoSesionProvider)?.email, 'lucia.silva@correo.com');
  });

  testWidgets('17-A01 al 200 %: «Recuperar acceso» se lee completo, sin puntos suspensivos', (
    tester,
  ) async {
    _pantalla(tester, const Size(360, 640), texto: 2.0);
    final e = await _montar(tester);
    await _expirar(tester, e, MotivoExpiracion.inactividad);
    final parrafo = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byType(TextButton), matching: find.text('Recuperar acceso')),
    );
    expect(parrafo.didExceedMaxLines, isFalse);
  });
}
