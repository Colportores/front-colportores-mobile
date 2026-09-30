// Vista 17 «Sesión vencida» (HU-AUTH-007, #226): el login con el aviso arriba, el saludo y el correo
// precargado. Inventario del canvas `17 Sesion Vencida.dc.html`:
//   17-A01 expiró por inactividad · 17-A03 revocada por el servidor · 17-A04 aviso descartado
//   17-A02 vencida y sin conexión → #248 (este archivo prueba que la entrada no la rompe).
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _inactividad = 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.';
const _revocada =
    'Tu sesión se cerró porque se cerró sesión en todos tus teléfonos o se cambió la contraseña. '
    'Entrá de nuevo.';
const _guardado = 'Tus visitas y cobranzas siguen guardadas en el teléfono.';

final _aviso = find.byKey(const Key('login_aviso_sesion'));
final _cerrar = find.byKey(const Key('login_aviso_sesion_cerrar'));
final _entrar = find.byKey(const Key('login_enviar'));
final _recuperar = find.text('Recuperar acceso');
final _principal = find.byKey(const Key('inicio_principal'));

String _correo(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const Key('login_email'))).controller!.text;

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
  group('Vista 17 — inventario de artboards', () {
    testWidgets('17-A01 expiró por inactividad: aviso arriba con ✕, saludo, «guardadas», correo y '
        '«Recuperar acceso»', (tester) async {
      final e = await _montar(tester);
      expect(_principal, findsOneWidget);
      await _expirar(tester, e, MotivoExpiracion.inactividad);

      expect(find.text(_inactividad), findsOneWidget);
      expect(_cerrar, findsOneWidget);
      expect(find.text('Hola de nuevo'), findsOneWidget, reason: 'sin nombre hasta #243');
      expect(find.text(_guardado), findsOneWidget);
      expect(_correo(tester), 'lucia.silva@correo.com');
      expect(_recuperar, findsOneWidget);
      expect(find.text('¿Olvidaste tu clave?'), findsNothing);
      expect(find.text('Entrar'), findsOneWidget);
      // El aviso queda arriba de la marca.
      expect(tester.getTopLeft(_aviso).dy, lessThan(tester.getTopLeft(find.text('COLPORTAJE')).dy));
    });

    testWidgets('17-A01 con nombre (cuando #243 lo ponga en la sesión): «Hola de nuevo, Lucía»', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);
      _contenedor(tester)
          .read(reingresoSesionProvider.notifier)
          .iniciar(
            const DatosReingreso(
              motivo: MotivoExpiracion.inactividad,
              email: 'lucia.silva@correo.com',
              nombre: 'Lucía',
            ),
          );
      await tester.pump();
      expect(find.text('Hola de nuevo, Lucía'), findsOneWidget);
    });

    testWidgets(
      '17-A03 revocada: texto de la propuesta, saludo y «Recuperar acceso», sin «guardadas»',
      (tester) async {
        final e = await _montar(tester);
        await _expirar(tester, e, MotivoExpiracion.revocada);

        expect(find.text(_revocada), findsOneWidget);
        expect(_cerrar, findsOneWidget);
        expect(find.text('Hola de nuevo'), findsOneWidget);
        expect(find.text(_guardado), findsNothing, reason: 'el canvas no lo pone en A03');
        expect(_correo(tester), 'lucia.silva@correo.com');
        expect(_recuperar, findsOneWidget);
      },
    );

    testWidgets('17-A04 aviso descartado: se va el aviso y quedan saludo, correo y enlace', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);

      await tester.tap(_cerrar);
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(find.text(_guardado), findsOneWidget);
      expect(_correo(tester), 'lucia.silva@correo.com');
      expect(_recuperar, findsOneWidget);
    });

    testWidgets('«Recuperar acceso» abre la recuperación de contraseña y volver deja todo igual', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.revocada);

      await tester.tap(_recuperar);
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);

      Navigator.of(tester.element(find.byType(RecuperacionPasswordPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(find.text(_revocada), findsOneWidget);
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(_correo(tester), 'lucia.silva@correo.com');
    });

    testWidgets('17-A02 (entra en #248): sin conexión, el login sigue usable y dice qué pasó si '
        'falla el ingreso', (tester) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);
      e.remoto.simularSinConexion = true;

      await tester.enterText(find.byKey(const Key('login_password')), 'Secreto123');
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_error_general')), findsOneWidget);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull, reason: 'no queda trabado');
      expect(find.text(_inactividad), findsOneWidget);
    });
  });

  group('Vista 17 — sin perder nada y casos límite', () {
    testWidgets('vencer o revocar la sesión no toca la base local del teléfono', (tester) async {
      final e = await _montar(tester);
      e.db.llamadas.clear();
      await _expirar(tester, e, MotivoExpiracion.revocada);

      expect(e.db.archivo, isTrue);
      expect(
        e.db.llamadas.where((l) => l.contains('borr') || l.contains('reconstruir')),
        isEmpty,
        reason: 'nunca se borra nada del teléfono',
      );
    });

    testWidgets(
      'arranque en frío con la sesión vencida: aviso y saludo, sin correo que precargar',
      (tester) async {
        await _montar(tester, vencidaHace: const Duration(days: 40));

        expect(find.text(_inactividad), findsOneWidget);
        expect(find.text('Hola de nuevo'), findsOneWidget);
        expect(_correo(tester), isEmpty);
      },
    );

    testWidgets('entrar de nuevo limpia aviso y saludo', (tester) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);

      await tester.enterText(find.byKey(const Key('login_password')), 'Secreto123');
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      final container = _contenedor(tester);
      expect(container.read(avisoSesionProvider), isNull);
      expect(container.read(reingresoSesionProvider), isNull);
    });

    testWidgets('contraseña incorrecta: el botón vuelve, el correo y el aviso se conservan', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);

      await tester.enterText(find.byKey(const Key('login_password')), 'Incorrecta1');
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
      expect(find.text(_inactividad), findsOneWidget);
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(_correo(tester), 'lucia.silva@correo.com');
    });

    testWidgets('doble toque en ✕: se cierra una vez y no pasa nada raro', (tester) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);

      await tester.tap(_cerrar);
      await tester.tap(_cerrar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.text('Hola de nuevo'), findsOneWidget);
    });

    testWidgets('cerrar el aviso y que llegue otro motivo: el aviso nuevo aparece completo', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);
      await tester.tap(_cerrar);
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);

      _contenedor(tester).read(avisoSesionProvider.notifier).mostrar(const FailureSesionRevocada());
      await tester.pumpAndSettle();
      expect(find.text(_revocada), findsOneWidget);
      expect(_cerrar, findsOneWidget);
    });

    testWidgets('revocar, entrar otra vez y volver a vencer: el aviso reaparece completo', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.revocada);
      await tester.tap(_cerrar);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('login_password')), 'Secreto123');
      await tester.tap(_entrar);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);

      await _expirar(tester, e, MotivoExpiracion.inactividad);
      expect(find.text(_inactividad), findsOneWidget);
      expect(find.text(_guardado), findsOneWidget);
    });

    for (final (nombre, tam, texto) in [
      ('360x640 al 200 %', const Size(360, 640), 2.0),
      ('412x915', const Size(412, 915), 1.0),
    ]) {
      testWidgets(
        '$nombre: A01, A04 y A03 con nombre y correo larguísimos, sin overflow y con guías',
        (tester) async {
          _pantalla(tester, tam, texto: texto);
          final semantica = tester.ensureSemantics();
          final e = await _montar(tester);
          await _expirar(tester, e, MotivoExpiracion.inactividad);
          _contenedor(tester)
              .read(reingresoSesionProvider.notifier)
              .iniciar(
                DatosReingreso(
                  motivo: MotivoExpiracion.inactividad,
                  email: '${'lucia.silva.de.los.santos'.padRight(60, 'x')}@correo.com',
                  nombre: 'María Lucía de los Ángeles Silva Fernández de la Vega',
                ),
              );
          await tester.pumpAndSettle();
          expect(find.textContaining('Hola de nuevo, María'), findsOneWidget);
          await _guias(tester);

          await tester.ensureVisible(_cerrar);
          await tester.tap(_cerrar);
          await tester.pumpAndSettle();
          expect(_aviso, findsNothing);
          await _guias(tester);

          _contenedor(
            tester,
          ).read(avisoSesionProvider.notifier).mostrar(const FailureSesionRevocada());
          await tester.pumpAndSettle();
          expect(find.text(_revocada), findsOneWidget);
          await _guias(tester);
          semantica.dispose();
        },
      );
    }

    testWidgets('el lector de pantalla anuncia el aviso (región viva) y la ✕ tiene etiqueta', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);

      expect(tester.getSemantics(_aviso), isSemantics(isLiveRegion: true));
      expect(find.byTooltip('Cerrar aviso'), findsOneWidget);
      semantica.dispose();
    });
  });
}
