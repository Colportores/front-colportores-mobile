// Vista 17 «Sesión vencida» (HU-AUTH-007, #226): el login con el aviso arriba, el saludo y el correo
// precargado. Inventario del canvas `17 Sesion Vencida.dc.html`:
//   17-A01 expiró por inactividad · 17-A02 vencida y sin conexión (#248) · 17-A03 revocada por el
//   servidor · 17-A04 aviso descartado
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/tiles_falsos.dart';

const _inactividad = 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.';
const _revocada =
    'Tu sesión se cerró porque se cerró sesión en todos tus teléfonos o se cambió la contraseña. '
    'Entrá de nuevo.';
const _guardado = 'Tus visitas y cobranzas siguen guardadas en el teléfono.';

/// Texto literal de HU-AUTH-003, «Edge - JWT expirado y sin conexión».
const _sinConexion = 'Tu sesión expiró. Necesitás conexión para renovarla.';

/// Propuesta del canvas 17-A02 (no está en la HU: queda «para confirmar» en el PR).
const _ayudaSinConexion = 'Vas a poder entrar cuando vuelva la señal.';

final _aviso = find.byKey(const Key('login_aviso_sesion'));
final _cerrar = find.byKey(const Key('login_aviso_sesion_cerrar'));
final _borde = find.byKey(const Key('login_aviso_sesion_borde_discontinuo'));
final _ayuda = find.byKey(const Key('login_vencida_sin_conexion_ayuda'));
final _errorGeneral = find.byKey(const Key('login_error_general'));
final _olvidaste = find.text('¿Olvidaste tu clave?');
final _clave = find.byKey(const Key('login_password'));
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
Future<_Entorno> _montar(
  WidgetTester tester, {
  Duration? vencidaHace,
  ConectividadFalsa? conectividad,
}) async {
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
        if (conectividad != null) monitorConectividadProvider.overrideWithValue(conectividad),
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

    testWidgets('«Recuperar acceso» abre la recuperación con el correo que ya está en el login', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.revocada);

      await tester.tap(_recuperar);
      await tester.pumpAndSettle();

      final campo = tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email')));
      expect(campo.controller?.text, 'lucia.silva@correo.com');
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

    testWidgets('17-A02 vencida y sin conexión: aviso con borde de trazos y sin ✕, saludo sin '
        '«guardadas», correo, «Entrar» y la ayuda; sin «Recuperar acceso»', (tester) async {
      final conexion = ConectividadFalsa()..tipo = TipoConexion.sinConexion;
      final e = await _montar(tester, conectividad: conexion);
      await _expirar(tester, e, MotivoExpiracion.inactividad);

      expect(find.text(_sinConexion), findsOneWidget);
      expect(_borde, findsOneWidget);
      expect(_cerrar, findsNothing, reason: 'el canvas no le da ✕: dura mientras no haya señal');
      expect(find.text(_inactividad), findsNothing, reason: 'el aviso de A02 reemplaza al de A01');
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(find.text(_guardado), findsNothing, reason: 'el canvas no lo pone en A02');
      expect(_correo(tester), 'lucia.silva@correo.com');
      expect(_recuperar, findsNothing, reason: 'recuperar la contraseña también pide red');
      expect(_olvidaste, findsNothing);
      expect(find.text('Entrar'), findsOneWidget);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
      expect(find.text(_ayudaSinConexion), findsOneWidget);
      // El aviso queda arriba de la marca y la ayuda debajo del botón.
      expect(tester.getTopLeft(_aviso).dy, lessThan(tester.getTopLeft(find.text('COLPORTAJE')).dy));
      expect(tester.getTopLeft(_entrar).dy, lessThan(tester.getTopLeft(_ayuda).dy));
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

    testWidgets('contraseña incorrecta con la respuesta tardando: el login sigue en pantalla con '
        '«Entrando…» y el error aparece al llegar', (tester) async {
      final e = await _montar(tester);
      await _expirar(tester, e, MotivoExpiracion.inactividad);
      e.remoto.demoraIniciarSesion = Completer<void>();

      await tester.enterText(find.byKey(const Key('login_password')), 'Incorrecta1');
      await tester.tap(_entrar);
      await tester.pump();

      expect(
        find.byType(LoginPage),
        findsOneWidget,
        reason: 'no se desmonta con la respuesta en camino',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNull);

      e.remoto.demoraIniciarSesion!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
      expect(find.text(_inactividad), findsOneWidget);
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
  group('Vista 17 — 17-A02 vencida y sin conexión (#248)', () {
    /// Con la sesión de Lucía vencida por inactividad y el login a la vista, con el teléfono en
    /// [tipo] (con señal o sin ella).
    Future<({_Entorno entorno, ConectividadFalsa conexion})> vencida(
      WidgetTester tester, {
      TipoConexion tipo = TipoConexion.sinConexion,
    }) async {
      final conexion = ConectividadFalsa()..tipo = tipo;
      final e = await _montar(tester, conectividad: conexion);
      await _expirar(tester, e, MotivoExpiracion.inactividad);
      return (entorno: e, conexion: conexion);
    }

    Future<void> tocarEntrar(WidgetTester tester, {String clave = 'Secreto123'}) async {
      await tester.enterText(_clave, clave);
      await tester.tap(_entrar);
      await tester.pumpAndSettle();
    }

    test('dado el escenario «JWT expirado y sin conexión», el texto es el literal de la HU', () {
      const failure = FailureSesionVencidaSinConexion();

      expect(failure.mensaje, _sinConexion);
      expect(failure.codigo, 'AUTH_SESION_VENCIDA_SIN_CONEXION');
    });

    testWidgets('dado A02 y que vuelve la señal, cuando la sesión sigue vencida, el aviso vuelve a '
        'ser el de A01 y se va de nuevo si se corta', (tester) async {
      final v = await vencida(tester);
      expect(find.text(_sinConexion), findsOneWidget);

      v.conexion.cambiarA(TipoConexion.wifi);
      await tester.pumpAndSettle();
      expect(find.text(_sinConexion), findsNothing);
      expect(find.text(_inactividad), findsOneWidget);
      expect(_cerrar, findsOneWidget);
      expect(find.text(_guardado), findsOneWidget);
      expect(_recuperar, findsOneWidget);
      expect(_ayuda, findsNothing);
      expect(_borde, findsNothing);

      v.conexion.cambiarA(TipoConexion.sinConexion);
      await tester.pumpAndSettle();
      expect(find.text(_sinConexion), findsOneWidget);
      expect(_cerrar, findsNothing);
      expect(_recuperar, findsNothing);
    });

    testWidgets('dado A01 con señal, cuando se corta, pasa a A02 y el lector de pantalla lo '
        'anuncia sin botón de cerrar', (tester) async {
      final semantica = tester.ensureSemantics();
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      expect(find.text(_inactividad), findsOneWidget);

      v.conexion.cambiarA(TipoConexion.sinConexion);
      await tester.pumpAndSettle();

      expect(find.text(_sinConexion), findsOneWidget);
      expect(tester.getSemantics(_aviso), isSemantics(isLiveRegion: true));
      expect(tester.getSemantics(_aviso).label, contains(_sinConexion));
      expect(find.byTooltip('Cerrar aviso'), findsNothing);
      semantica.dispose();
    });

    testWidgets('dado A04 (aviso descartado), cuando se corta la señal, aparece A02 y al volver '
        'la señal no reaparece el aviso descartado', (tester) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      await tester.tap(_cerrar);
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);

      v.conexion.cambiarA(TipoConexion.sinConexion);
      await tester.pumpAndSettle();
      expect(find.text(_sinConexion), findsOneWidget);
      expect(_cerrar, findsNothing);

      v.conexion.cambiarA(TipoConexion.datosMoviles);
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(_recuperar, findsOneWidget);
    });

    testWidgets('dado el arranque en frío con la sesión descartada y sin señal, A02 con el correo '
        'que había quedado guardado', (tester) async {
      final conexion = ConectividadFalsa()..tipo = TipoConexion.sinConexion;
      final remoto = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..vencidaPorInactividadAlArrancar = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(remoto),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
            ultimoCorreoRepositoryProvider.overrideWithValue(
              UltimoCorreoEnMemoria('lucia.silva@correo.com'),
            ),
            monitorConectividadProvider.overrideWithValue(conexion),
          ],
          child: const ColportoresApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_sinConexion), findsOneWidget);
      expect(_cerrar, findsNothing);
      expect(_correo(tester), 'lucia.silva@correo.com');
      expect(_recuperar, findsNothing);

      conexion.cambiarA(TipoConexion.wifi);
      await tester.pumpAndSettle();
      expect(find.text(_inactividad), findsOneWidget);
      expect(_recuperar, findsOneWidget);
    });

    testWidgets('dado que el teléfono dice que hay señal y el servidor no responde, cuando toca '
        '«Entrar», pasa a A02 sin repetir el error debajo del formulario', (tester) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto.simularSinConexion = true;

      await tocarEntrar(tester);

      expect(find.text(_sinConexion), findsOneWidget);
      expect(_borde, findsOneWidget);
      expect(_cerrar, findsNothing);
      expect(_errorGeneral, findsNothing);
      expect(find.textContaining('Necesitás conexión para iniciar sesión'), findsNothing);
      expect(find.text(_guardado), findsNothing);
      expect(_recuperar, findsNothing);
      expect(find.text(_ayudaSinConexion), findsOneWidget);
      // Nada queda trabado ni se pierde lo escrito.
      expect(find.text('Entrando…'), findsNothing);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
      expect(_correo(tester), 'lucia.silva@correo.com');
      expect(tester.widget<TextField>(_clave).controller!.text, 'Secreto123');
      expect(v.entorno.remoto.llamadasIniciarSesion, 1);
    });

    testWidgets('dado A02 por un intento fallido, cuando vuelve la señal y toca «Entrar», entra y '
        'se limpian los avisos', (tester) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto.simularSinConexion = true;
      await tocarEntrar(tester);
      expect(find.text(_sinConexion), findsOneWidget);

      v.entorno.remoto.simularSinConexion = false;
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      final container = _contenedor(tester);
      expect(container.read(avisoSesionProvider), isNull);
      expect(container.read(reingresoSesionProvider), isNull);
    });

    testWidgets('dado A02 por un intento fallido, cuando el teléfono cambia de red, vuelve A01', (
      tester,
    ) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto.simularSinConexion = true;
      await tocarEntrar(tester);
      expect(find.text(_sinConexion), findsOneWidget);

      v.conexion.cambiarA(TipoConexion.datosMoviles);
      await tester.pumpAndSettle();

      expect(find.text(_sinConexion), findsNothing);
      expect(find.text(_inactividad), findsOneWidget);
      expect(_cerrar, findsOneWidget);
      expect(_recuperar, findsOneWidget);
      expect(_ayuda, findsNothing);
    });

    testWidgets('dado doble toque en «Entrar» sin conexión, se hace una sola llamada y queda A02', (
      tester,
    ) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto
        ..simularSinConexion = true
        ..demoraIniciarSesion = Completer<void>();
      await tester.enterText(_clave, 'Secreto123');

      await tester.tap(_entrar);
      await tester.pump();
      await tester.tap(_entrar, warnIfMissed: false);
      await tester.pump();
      v.entorno.remoto.demoraIniciarSesion!.complete();
      await tester.pumpAndSettle();

      expect(v.entorno.remoto.llamadasIniciarSesion, 1);
      expect(find.text(_sinConexion), findsOneWidget);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado dos intentos seguidos sin conexión, hay un solo aviso y el botón vuelve cada '
        'vez', (tester) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto.simularSinConexion = true;

      await tocarEntrar(tester);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(v.entorno.remoto.llamadasIniciarSesion, 2);
      expect(find.text(_sinConexion), findsOneWidget);
      expect(_errorGeneral, findsNothing);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
    });

    testWidgets('dado que la señal cambia con el intento en vuelo, cuando el servidor igual no '
        'responde, queda A02: manda la respuesta', (tester) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto
        ..simularSinConexion = true
        ..demoraIniciarSesion = Completer<void>();
      await tester.enterText(_clave, 'Secreto123');
      await tester.tap(_entrar);
      await tester.pump();

      v.conexion.cambiarA(TipoConexion.datosMoviles);
      await tester.pump();
      v.entorno.remoto.demoraIniciarSesion!.complete();
      await tester.pumpAndSettle();

      expect(find.text(_sinConexion), findsOneWidget);
      expect(find.text(_inactividad), findsNothing);
    });

    testWidgets('dado A02, cuando falta la contraseña, el campo lo dice y el aviso sigue', (
      tester,
    ) async {
      final v = await vencida(tester);

      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(find.text(_sinConexion), findsOneWidget);
      expect(v.entorno.remoto.llamadasIniciarSesion, 0, reason: 'sin red no sale ni se intenta');
    });

    testWidgets('dado A02 por un intento fallido, cuando después falla la validación, el aviso '
        'sigue', (tester) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto.simularSinConexion = true;
      await tocarEntrar(tester);
      expect(find.text(_sinConexion), findsOneWidget);

      await tocarEntrar(tester, clave: '');

      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(find.text(_sinConexion), findsOneWidget);
      expect(_borde, findsOneWidget);
    });

    testWidgets('dado A01, cuando se vuelve de «Recuperar acceso» con la señal cortada, queda A02 '
        'con el correo intacto', (tester) async {
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      await tester.tap(_recuperar);
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);

      v.conexion.cambiarA(TipoConexion.sinConexion);
      await tester.pump();
      Navigator.of(tester.element(find.byType(RecuperacionPasswordPage))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(find.text(_sinConexion), findsOneWidget);
      expect(_recuperar, findsNothing);
      expect(_correo(tester), 'lucia.silva@correo.com');
    });

    testWidgets('dado una sesión revocada, cuando no hay señal, no es A02: se queda el aviso de '
        'A03 y el error de entrar va debajo', (tester) async {
      final conexion = ConectividadFalsa()..tipo = TipoConexion.sinConexion;
      final e = await _montar(tester, conectividad: conexion);
      await _expirar(tester, e, MotivoExpiracion.revocada);

      expect(find.text(_revocada), findsOneWidget);
      expect(_cerrar, findsOneWidget);
      expect(find.text(_sinConexion), findsNothing);
      expect(_ayuda, findsNothing);
      expect(_recuperar, findsOneWidget);

      e.remoto.simularSinConexion = true;
      await tocarEntrar(tester);

      expect(_errorGeneral, findsOneWidget);
      expect(find.text(_sinConexion), findsNothing);
      expect(find.text(_revocada), findsOneWidget);
    });

    testWidgets('dado A02 sin conexión, intentar entrar no toca la base local del teléfono', (
      tester,
    ) async {
      final v = await vencida(tester);
      v.entorno.db.llamadas.clear();
      v.entorno.remoto.simularSinConexion = true;
      await tocarEntrar(tester);

      expect(v.entorno.db.archivo, isTrue);
      expect(
        v.entorno.db.llamadas.where((l) => l.contains('borr') || l.contains('reconstruir')),
        isEmpty,
        reason: 'los datos siguen intactos hasta que vuelva la señal',
      );
    });

    for (final (nombre, tam, texto) in [
      ('360x640 al 200 %', const Size(360, 640), 2.0),
      ('412x915', const Size(412, 915), 1.0),
    ]) {
      testWidgets('$nombre: A02 con nombre y correo larguísimos, sin overflow y con guías', (
        tester,
      ) async {
        _pantalla(tester, tam, texto: texto);
        final semantica = tester.ensureSemantics();
        await vencida(tester);
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

        expect(find.text(_sinConexion), findsOneWidget);
        expect(find.textContaining('Hola de nuevo, María'), findsOneWidget);
        await _guias(tester);
        semantica.dispose();
      });
    }

    testWidgets('360x640 al 200 %: tras un intento sin conexión, el aviso de A02 se lleva a la '
        'vista', (tester) async {
      _pantalla(tester, const Size(360, 640), texto: 2);
      final v = await vencida(tester, tipo: TipoConexion.wifi);
      v.entorno.remoto.simularSinConexion = true;
      await tester.enterText(_clave, 'Secreto123');
      await tester.ensureVisible(_entrar);
      await tester.pumpAndSettle();

      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(find.text(_sinConexion), findsOneWidget);
      final aviso = tester.getRect(_aviso);
      expect(aviso.top, greaterThanOrEqualTo(0));
      expect(aviso.bottom, lessThanOrEqualTo(640));
      expect(tester.takeException(), isNull);
    });
  });
  group('Vista 17 — arranque en frío: el correo viene del almacén seguro', () {
    /// La app arranca con la sesión ya descartada por 30 días sin uso: no hay sesión de dónde
    /// sacar el correo, solo lo que quedó guardado aparte.
    Future<AuthRemoteDataSourceEnMemoria> arrancarEnFrio(
      WidgetTester tester,
      UltimoCorreoEnMemoria guardado,
    ) async {
      final remoto = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..vencidaPorInactividadAlArrancar = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(remoto),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
            ultimoCorreoRepositoryProvider.overrideWithValue(guardado),
          ],
          child: const ColportoresApp(),
        ),
      );
      await tester.pumpAndSettle();
      return remoto;
    }

    testWidgets('17-A01 en frío con correo guardado: aviso, saludo y el correo ya puesto', (
      tester,
    ) async {
      await arrancarEnFrio(tester, UltimoCorreoEnMemoria('lucia.silva@correo.com'));

      expect(find.text(_inactividad), findsOneWidget);
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(_correo(tester), 'lucia.silva@correo.com');
      expect(_recuperar, findsOneWidget);
    });

    testWidgets('en frío sin correo guardado: el campo queda vacío y el aviso se muestra igual', (
      tester,
    ) async {
      await arrancarEnFrio(tester, UltimoCorreoEnMemoria());

      expect(find.text(_inactividad), findsOneWidget);
      expect(_correo(tester), isEmpty);
    });

    testWidgets('en frío con correo precargado: entrar con la contraseña lleva a la principal '
        'y deja el correo guardado', (tester) async {
      final guardado = UltimoCorreoEnMemoria('lucia.silva@correo.com');
      await arrancarEnFrio(tester, guardado);

      await tester.enterText(find.byKey(const Key('login_password')), 'Secreto123');
      await tester.pump();
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(await guardado.leer(), 'lucia.silva@correo.com');
    });

    testWidgets('en frío con el correo precargado a texto grande (200 %): sin overflow', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 740), texto: 2);
      await arrancarEnFrio(
        tester,
        UltimoCorreoEnMemoria('lucia.silva.con.un.correo.largo@correo.com'),
      );

      expect(_correo(tester), 'lucia.silva.con.un.correo.largo@correo.com');
      expect(tester.takeException(), isNull);
    });
  });
}
