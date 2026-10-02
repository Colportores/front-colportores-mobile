// QA del delta de la vista 17 (#226), decisión de Cristian del 01/10: en el arranque en frío con la
// sesión vencida, el login trae el correo de la última cuenta (y nada más). Acá corre de punta a
// punta: el repositorio REAL sobre un almacén seguro en memoria, que se comparte entre dos
// arranques de la app. El cierre a propósito lo deja vacío.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _correo = 'lucia.silva@correo.com';
const _password = 'Secreto123';
const _inactividad = 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.';

late AlmacenSeguroEnMemoria _almacen;

String _campoCorreo(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('login_email'))).controller!.text;

void _pantalla(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Un arranque de la app con el almacén compartido. Con [enFrioVencida] la sesión guardada se
/// descartó por inactividad antes de arrancar; con [entrarCon] entra con esa cuenta.
Future<ProviderContainer> _arrancar(
  WidgetTester tester, {
  bool enFrioVencida = false,
  String? entrarCon,
  Map<String, String> credenciales = const {_correo: _password},
}) async {
  final remoto = AuthRemoteDataSourceEnMemoria(credenciales: credenciales)
    ..vencidaPorInactividadAlArrancar = enFrioVencida;
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remoto),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(_almacen)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  if (entrarCon != null) {
    await container
        .read(sesionProvider.notifier)
        .iniciarSesion(email: entrarCon, password: _password);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _reiniciarApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _almacen = AlmacenSeguroEnMemoria());

  group('QA #226 — correo de la última cuenta en el arranque en frío', () {
    testWidgets('con sesión vencida en frío, el correo de la última cuenta viene precargado y en '
        'el almacén no hay nada más', (tester) async {
      await _arrancar(tester, entrarCon: _correo);
      expect(_almacen.contenido, {ClaveSegura.ultimoCorreo: _correo});
      await _reiniciarApp(tester);

      await _arrancar(tester, enFrioVencida: true);

      expect(find.text(_inactividad), findsOneWidget);
      expect(_campoCorreo(tester), _correo);
      expect(
        tester.widget<TextField>(find.byKey(const Key('login_password'))).controller!.text,
        isEmpty,
        reason: 'solo el correo: la contraseña nunca',
      );
      expect(find.text('Hola de nuevo'), findsOneWidget, reason: 'el nombre no se guarda aparte');
      expect(_almacen.contenido.keys, [ClaveSegura.ultimoCorreo]);
    });

    testWidgets('tras cerrar sesión a propósito, el arranque siguiente no trae el correo', (
      tester,
    ) async {
      final container = await _arrancar(tester, entrarCon: _correo);
      await container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pumpAndSettle();
      expect(_almacen.contenido, isEmpty);
      await _reiniciarApp(tester);

      await _arrancar(tester, enFrioVencida: true);

      expect(find.text(_inactividad), findsOneWidget);
      expect(_campoCorreo(tester), isEmpty);
    });

    testWidgets('entrar con otra cuenta reemplaza al correo guardado', (tester) async {
      await _arrancar(tester, entrarCon: _correo);
      expect(_almacen.contenido[ClaveSegura.ultimoCorreo], _correo);
      await _reiniciarApp(tester);

      await _arrancar(
        tester,
        entrarCon: 'otra@correo.com',
        credenciales: const {'otra@correo.com': _password},
      );

      expect(_almacen.contenido[ClaveSegura.ultimoCorreo], 'otra@correo.com');
    });

    for (final (tam, texto) in const [
      (Size(360, 640), 2.0),
      (Size(412, 915), 2.0),
      (Size(360, 640), 1.0),
    ]) {
      testWidgets('arranque en frío con el correo precargado y largo: ${tam.width.toInt()}x'
          '${tam.height.toInt()} a ${(texto * 100).toInt()} %, sin recorte ni overflow', (
        tester,
      ) async {
        const largo = 'lucia.silva.de.la.congregacion.central@correo-largo-de-la-iglesia.com';
        _almacen = AlmacenSeguroEnMemoria({ClaveSegura.ultimoCorreo: largo});
        _pantalla(tester, tam, texto: texto);

        await _arrancar(tester, enFrioVencida: true);

        expect(_campoCorreo(tester), largo);
        expect(find.text(_inactividad), findsOneWidget);
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        final ancho = tester.view.physicalSize.width;
        expect(
          tester.getRect(find.byKey(const Key('login_email'))).right,
          lessThanOrEqualTo(ancho),
        );
        expect(tester.getRect(find.text(_inactividad)).right, lessThanOrEqualTo(ancho));
      });
    }
  });
}
