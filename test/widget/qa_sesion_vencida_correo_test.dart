// QA del delta de la vista 17 (#226), decisión de Cristian del 01/10: en el arranque en frío con la
// sesión vencida, el login trae el correo de la última cuenta (y nada más). Acá corre de punta a
// punta: el repositorio REAL sobre un almacén seguro en memoria, que se comparte entre dos
// arranques de la app. El cierre a propósito lo deja vacío.
//
// Decisión de Cristian del 07/10 (#302): el motivo y la fecha del último cierre que la persona no
// pidió se guardan al lado del correo (y nada más), y el aviso de la vista 17 vale en cada arranque
// sin sesión hasta que entra.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cierre_forzado_repository_impl.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/tiles_falsos.dart';

const _correo = 'lucia.silva@correo.com';
const _password = 'Secreto123';
const _inactividad = 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.';
const _revocada =
    'Tu sesión se cerró porque se cerró sesión en todos tus teléfonos o se cambió la contraseña. '
    'Entrá de nuevo.';

/// Texto literal de HU-AUTH-003, «Edge - JWT expirado y sin conexión» (17-A02).
const _sinConexion = 'Tu sesión expiró. Necesitás conexión para renovarla.';

final _aviso = find.byKey(const Key('login_aviso_sesion'));
final _principal = find.byKey(const Key('inicio_principal'));

late AlmacenSeguroEnMemoria _almacen;

/// El remoto del último arranque, para que un test pueda terminarle la sesión desde el servidor.
late AuthRemoteDataSourceEnMemoria _remoto;

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
  ConectividadFalsa? conectividad,
}) async {
  final remoto = _remoto = AuthRemoteDataSourceEnMemoria(credenciales: credenciales)
    ..vencidaPorInactividadAlArrancar = enFrioVencida;
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remoto),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(_almacen)),
      cierreForzadoRepositoryProvider.overrideWithValue(CierreForzadoRepositoryImpl(_almacen)),
      if (conectividad != null) monitorConectividadProvider.overrideWithValue(conectividad),
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

Future<void> _entrarDesdeElLogin(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_password')), _password);
  await tester.tap(find.byKey(const Key('login_enviar')));
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
      expect(
        _almacen.contenido.keys,
        unorderedEquals([ClaveSegura.ultimoCorreo, ClaveSegura.cierreForzado]),
        reason: 'junto al correo, solo el motivo del cierre y su fecha (#302)',
      );
      expect(
        _almacen.contenido[ClaveSegura.cierreForzado],
        matches(r'^inactividad\|\d{4}-\d{2}-\d{2}T[\d:.]+Z$'),
      );
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

  group('QA #302 — el aviso de la vista 17 vale en cada arranque sin sesión hasta que entra', () {
    /// Entra, se vence la sesión en frío y la app se cierra: el almacén queda con el cierre.
    Future<void> cierreEnFrio(WidgetTester tester) async {
      await _arrancar(tester, entrarCon: _correo);
      await _reiniciarApp(tester);
      await _arrancar(tester, enFrioVencida: true);
      await _reiniciarApp(tester);
    }

    testWidgets('Escenario: segundo arranque — sin nada por detectar, la sesión ya descartada, el '
        'aviso, el saludo y el correo siguen', (tester) async {
      await cierreEnFrio(tester);

      await _arrancar(tester);

      expect(find.text(_inactividad), findsOneWidget);
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(_campoCorreo(tester), _correo);
      expect(
        tester.widget<TextField>(find.byKey(const Key('login_password'))).controller!.text,
        isEmpty,
      );
    });

    testWidgets('y en el tercero y el cuarto, mientras no entre', (tester) async {
      await cierreEnFrio(tester);

      for (var arranque = 2; arranque <= 4; arranque++) {
        await _arrancar(tester);
        expect(find.text(_inactividad), findsOneWidget, reason: 'arranque $arranque');
        expect(_campoCorreo(tester), _correo, reason: 'arranque $arranque');
        await _reiniciarApp(tester);
      }
    });

    testWidgets('descartar el aviso con la ✕ vale hasta cerrar la app: al arrancar vuelve', (
      tester,
    ) async {
      await cierreEnFrio(tester);
      await _arrancar(tester);

      await tester.tap(find.byKey(const Key('login_aviso_sesion_cerrar')));
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);
      await _reiniciarApp(tester);
      await _arrancar(tester);

      expect(find.text(_inactividad), findsOneWidget);
    });

    testWidgets('dado el segundo arranque sin señal, 17-A02 con el correo; vuelve la señal y '
        'pasa a 17-A01', (tester) async {
      await cierreEnFrio(tester);
      final conexion = ConectividadFalsa()..tipo = TipoConexion.sinConexion;

      await _arrancar(tester, conectividad: conexion);

      expect(find.text(_sinConexion), findsOneWidget);
      expect(_campoCorreo(tester), _correo);
      conexion.cambiarA(TipoConexion.wifi);
      await tester.pumpAndSettle();
      expect(find.text(_inactividad), findsOneWidget);
    });

    testWidgets('la sesión revocada por el servidor también: 17-A03 en los arranques siguientes', (
      tester,
    ) async {
      await _arrancar(tester, entrarCon: _correo);
      _remoto.simularExpiracion(MotivoExpiracion.revocada);
      await tester.pumpAndSettle();
      expect(find.text(_revocada), findsOneWidget);
      expect(_almacen.contenido[ClaveSegura.cierreForzado], startsWith('revocada|'));
      await _reiniciarApp(tester);

      await _arrancar(tester);

      expect(find.text(_revocada), findsOneWidget);
      expect(_campoCorreo(tester), _correo);
    });

    testWidgets('entrar en el segundo arranque borra el motivo: el tercero es un login común, y '
        'en el almacén queda solo el correo', (tester) async {
      await cierreEnFrio(tester);
      await _arrancar(tester);

      await _entrarDesdeElLogin(tester);

      expect(_principal, findsOneWidget);
      expect(_almacen.contenido, {ClaveSegura.ultimoCorreo: _correo});
      await _reiniciarApp(tester);
      await _arrancar(tester);
      expect(_aviso, findsNothing);
      expect(find.text('Hola de nuevo'), findsNothing);
    });

    testWidgets('cerrar sesión a propósito después de entrar deja el almacén vacío', (
      tester,
    ) async {
      await cierreEnFrio(tester);
      final container = await _arrancar(tester);
      await _entrarDesdeElLogin(tester);

      await container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pumpAndSettle();

      expect(_almacen.contenido, isEmpty);
    });

    testWidgets('un valor ilegible en el almacén es un login común, sin aviso', (tester) async {
      _almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: _correo,
        ClaveSegura.cierreForzado: 'cualquier cosa',
      });

      await _arrancar(tester);

      expect(_aviso, findsNothing);
      expect(find.text('Hola de nuevo'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con el correo largo, 360x640 a 200 %: el aviso del segundo arranque sin recorte', (
      tester,
    ) async {
      const largo = 'lucia.silva.de.la.congregacion.central@correo-largo-de-la-iglesia.com';
      _almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: largo,
        ClaveSegura.cierreForzado: 'inactividad|2026-10-07T08:02:30.000Z',
      });
      _pantalla(tester, const Size(360, 640), texto: 2);

      await _arrancar(tester);

      expect(find.text(_inactividad), findsOneWidget);
      expect(_campoCorreo(tester), largo);
      expect(tester.takeException(), isNull);
      final ancho = tester.view.physicalSize.width;
      expect(tester.getRect(find.text(_inactividad)).right, lessThanOrEqualTo(ancho));
    });
  });
}
