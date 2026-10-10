// QA del PR #346 (issue #311): la vista 17 «Sesión vencida» (HU-AUTH-007) cuando el fin de sesión
// llega con la app todavía leyendo la sesión guardada.
//
// El widget del aviso no cambia en el PR; cambia CÓMO se llega a él. Por eso acá se llega a cada
// artboard por el camino nuevo (stream antes de que termine la lectura de la sesión) y se mira lo
// que ve la persona:
//  1. 17-A01 y 17-A03, 360x640 y 412x915, texto 100 % y 200 %: textos literales de la HU, sin
//     overflow, guías de accesibilidad de Flutter. Capturas en `.dart_tool/qa_capturas/` (gitignored)
//     con `--dart-define=QA_CAPTURAS=true`.
//  2. 17-A02 (sin señal) y 17-A04 (aviso descartado) alcanzados por el mismo camino.
//  3. Región viva, etiqueta de la ✕ y orden del foco con el teclado.
//  4. Volver a entrar, contraseña incorrecta y «Cerrar sesión» a propósito después del aviso.
//  5. La ventana entre que se publica la sesión y se cierra: la pantalla principal no debería verse.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cierre_forzado_repository_impl.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/services/reloj_sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/revisando_cuenta_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/tiles_falsos.dart';

const _correo = 'lucia.silva@correo.com';
const _password = 'Secreto123';

// Textos literales de HU-AUTH-007 (17-A01 y 17-A03) y de HU-AUTH-003 (17-A02).
const _inactividad = 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.';
const _revocada =
    'Tu sesión se cerró porque se cerró sesión en todos tus teléfonos o se cambió la contraseña. '
    'Entrá de nuevo.';
const _sinConexion = 'Tu sesión expiró. Necesitás conexión para renovarla.';
const _ayudaSinConexion = 'Vas a poder entrar cuando vuelva la señal.';
const _guardado = 'Tus visitas y cobranzas siguen guardadas en el teléfono.';

final _aviso = find.byKey(const Key('login_aviso_sesion'));
final _cerrar = find.byKey(const Key('login_aviso_sesion_cerrar'));
final _borde = find.byKey(const Key('login_aviso_sesion_borde_discontinuo'));
final _saludo = find.byKey(const Key('login_saludo'));
final _datosGuardados = find.byKey(const Key('login_datos_guardados'));
final _ayuda = find.byKey(const Key('login_vencida_sin_conexion_ayuda'));
final _recuperar = find.text('Recuperar acceso');
final _principal = find.byKey(const Key('inicio_principal'));

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

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

Future<void> _cargarFuentes(WidgetTester tester) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
    // Sin la fuente de los íconos, flutter_test pinta cajas en lugar de la ✕ y el candado.
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
      await loader.load();
    }
  });
}

/// Captura fuera del repo: `.dart_tool` está en el .gitignore.
Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/311_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Con las fuentes reales la guía de contraste mide el borde suavizado de las letras chicas y da
/// falsos negativos: en el modo de capturas no corre; en el CI sí, con la fuente de prueba.
Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (!_conCapturas) await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

bool _focoEn(WidgetTester tester, Finder donde) {
  final contexto = FocusManager.instance.primaryFocus?.context;
  if (contexto == null) return false;
  final objetivo = tester.element(donde);
  if (contexto == objetivo) return true;
  var dentro = false;
  contexto.visitAncestorElements((e) {
    if (e == objetivo) {
      dentro = true;
      return false;
    }
    return true;
  });
  return dentro;
}

/// La sesión guardada en el teléfono, que se lee cuando el test abre la [puerta].
final class _LocalQueTardaEnLeer implements AuthLocalDataSource {
  _LocalQueTardaEnLeer(this.puerta, this._sesion);

  final Completer<void> puerta;
  SesionModel? _sesion;

  @override
  Future<SesionModel?> leerSesion() async {
    await puerta.future;
    return _sesion;
  }

  @override
  Future<void> guardarSesion(SesionModel sesion) async => _sesion = sesion;

  @override
  Future<void> borrarSesion() async => _sesion = null;
}

/// Reloj de la sesión cuya lectura se retiene (el Keystore lento): cada lectura espera su turno.
final class _RelojPorTurnos implements RelojSesion {
  final turnos = <Completer<DateTime>>[];

  @override
  Future<DateTime> ahora() {
    final turno = Completer<DateTime>();
    turnos.add(turno);
    return turno.future;
  }

  @override
  Future<void> registrar(DateTime visto) async {}
}

SesionModel _sesionGuardada() => SesionModel(
  usuarioId: '11111111-1111-4111-8111-111111111111',
  email: _correo,
  accessToken: 'token-guardado',
  expiraEn: DateTime.now().toUtc().add(const Duration(days: 20)),
);

/// La app montada con la sesión todavía leyéndose.
final class _AppArrancando {
  _AppArrancando(
    this.tester, {
    ConectividadFalsa? conectividad,
    RelojSesion? reloj,
    Map<ClaveSegura, String>? almacenInicial,
  }) : almacen = AlmacenSeguroEnMemoria(almacenInicial),
       puerta = Completer<void>(),
       remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password}) {
    container = ProviderContainer(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(
          _LocalQueTardaEnLeer(puerta, _sesionGuardada()),
        ),
        ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(almacen)),
        cierreForzadoRepositoryProvider.overrideWithValue(CierreForzadoRepositoryImpl(almacen)),
        if (conectividad != null) monitorConectividadProvider.overrideWithValue(conectividad),
        if (reloj != null) relojSesionProvider.overrideWithValue(reloj),
      ],
    );
    addTearDown(container.dispose);
  }

  final WidgetTester tester;
  final AlmacenSeguroEnMemoria almacen;
  final Completer<void> puerta;
  final AuthRemoteDataSourceEnMemoria remoto;
  late final ProviderContainer container;

  Future<void> montar() async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ColportoresApp()),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'arrancando');
  }

  /// El fin de sesión llega por el stream mientras se lee la sesión, y después termina la lectura.
  Future<void> finDeSesionTemprano(MotivoExpiracion motivo) async {
    remoto.simularExpiracion(motivo);
    await tester.pump();
    puerta.complete();
    await tester.pumpAndSettle();
  }
}

Future<void> _entrarDesdeElLogin(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_password')), _password);
  await tester.tap(find.byKey(const Key('login_enviar')));
  await tester.pumpAndSettle();
}

void main() {
  group('QA #311 — 17-A01 y 17-A03 alcanzados con el fin de sesión temprano', () {
    final artboards = <(String, MotivoExpiracion, String)>[
      ('A01', MotivoExpiracion.inactividad, _inactividad),
      ('A03', MotivoExpiracion.revocada, _revocada),
    ];
    final tamanios = <(Size, double)>[
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 1.0),
      (const Size(412, 915), 2.0),
    ];

    for (final (nombre, motivo, texto) in artboards) {
      for (final (tam, escala) in tamanios) {
        testWidgets(
          '17-$nombre, ${tam.width.toInt()}x${tam.height.toInt()} a ${(escala * 100).toInt()} %: '
          'texto literal, saludo con el correo, sin overflow y con las guías de accesibilidad',
          (tester) async {
            _pantalla(tester, tam, texto: escala);
            final semantica = tester.ensureSemantics();
            await _cargarFuentes(tester);
            final app = _AppArrancando(tester, almacenInicial: {ClaveSegura.ultimoCorreo: _correo});
            await app.montar();

            await app.finDeSesionTemprano(motivo);

            expect(_principal, findsNothing);
            expect(find.text(texto), findsOneWidget);
            expect(_cerrar, findsOneWidget);
            expect(_saludo, findsOneWidget);
            expect(find.text('Hola de nuevo'), findsOneWidget);
            expect(_campoCorreo(tester), _correo);
            expect(_recuperar, findsOneWidget);
            if (motivo == MotivoExpiracion.inactividad) {
              expect(_datosGuardados, findsOneWidget);
              expect(find.text(_guardado), findsOneWidget);
            } else {
              expect(_datosGuardados, findsNothing, reason: 'el canvas A03 no lo dibuja');
            }
            expect(_ayuda, findsNothing);
            final ancho = tester.view.physicalSize.width;
            for (final f in [_saludo, find.byKey(const Key('login_email')), _aviso]) {
              expect(tester.getRect(f).right, lessThanOrEqualTo(ancho), reason: '$f');
              expect(tester.getRect(f).left, greaterThanOrEqualTo(0));
            }
            await _guias(tester);
            await _capturar(
              tester,
              '${nombre}_${tam.width.toInt()}x${tam.height.toInt()}_${escala.toInt()}x',
            );
            semantica.dispose();
          },
        );
      }
    }
  });

  group('QA #311 — 17-A02 y 17-A04 por el mismo camino', () {
    testWidgets('17-A02: sin señal, el fin de sesión por inactividad llega temprano: el aviso de '
        'sin conexión, sin ✕ ni «Recuperar acceso»', (tester) async {
      _pantalla(tester, const Size(360, 640), texto: 2);
      final semantica = tester.ensureSemantics();
      await _cargarFuentes(tester);
      final app = _AppArrancando(
        tester,
        conectividad: ConectividadFalsa()..tipo = TipoConexion.sinConexion,
        almacenInicial: {ClaveSegura.ultimoCorreo: _correo},
      );
      await app.montar();

      await app.finDeSesionTemprano(MotivoExpiracion.inactividad);

      expect(_principal, findsNothing);
      expect(find.text(_sinConexion), findsOneWidget);
      expect(_borde, findsOneWidget);
      expect(_cerrar, findsNothing);
      expect(find.text(_ayudaSinConexion), findsOneWidget);
      expect(_datosGuardados, findsNothing);
      expect(_recuperar, findsNothing);
      await _guias(tester);
      await _capturar(tester, 'A02_360x640_2x');
      semantica.dispose();
    });

    for (final (motivo, nombre, conSubtitulo) in <(MotivoExpiracion, String, bool)>[
      (MotivoExpiracion.inactividad, 'A04', true),
      (MotivoExpiracion.revocada, 'A04-revocada', false),
    ]) {
      testWidgets(
        '17-$nombre: descartar el aviso con la ✕: el aviso se va, el saludo se queda y el '
        'motivo sigue guardado para el arranque siguiente',
        (tester) async {
          _pantalla(tester, const Size(412, 915));
          final semantica = tester.ensureSemantics();
          await _cargarFuentes(tester);
          final app = _AppArrancando(tester, almacenInicial: {ClaveSegura.ultimoCorreo: _correo});
          await app.montar();
          await app.finDeSesionTemprano(motivo);

          await tester.ensureVisible(_cerrar);
          await tester.tap(_cerrar);
          await tester.pumpAndSettle();

          expect(_aviso, findsNothing);
          expect(_saludo, findsOneWidget);
          expect(find.text('Hola de nuevo'), findsOneWidget);
          expect(_campoCorreo(tester), _correo);
          expect(_datosGuardados, conSubtitulo ? findsOneWidget : findsNothing);
          expect(_recuperar, findsOneWidget);
          expect(app.almacen.contenido[ClaveSegura.cierreForzado], startsWith('${motivo.name}|'));
          await _guias(tester);
          await _capturar(tester, '${nombre}_412x915_1x');
          semantica.dispose();
        },
      );
    }
  });

  group('QA #311 — lector de pantalla y teclado', () {
    testWidgets('el aviso es una región viva con la ✕ etiquetada y el primer Tab llega a la ✕ y '
        'después al correo', (tester) async {
      final semantica = tester.ensureSemantics();
      final app = _AppArrancando(tester, almacenInicial: {ClaveSegura.ultimoCorreo: _correo});
      await app.montar();
      await app.finDeSesionTemprano(MotivoExpiracion.revocada);

      expect(tester.getSemantics(_aviso), isSemantics(isLiveRegion: true));
      expect(tester.getSemantics(_cerrar), isSemantics(isButton: true, tooltip: 'Cerrar aviso'));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focoEn(tester, _cerrar), isTrue, reason: 'primero el aviso');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focoEn(tester, find.byKey(const Key('login_email'))), isTrue);
      semantica.dispose();
    });
  });

  group('QA #311 — después del aviso', () {
    testWidgets('contraseña incorrecta: el aviso, el correo y lo tipeado se conservan, el botón '
        'vuelve y el motivo sigue guardado', (tester) async {
      final app = _AppArrancando(tester, almacenInicial: {ClaveSegura.ultimoCorreo: _correo});
      await app.montar();
      await app.finDeSesionTemprano(MotivoExpiracion.inactividad);

      await tester.enterText(find.byKey(const Key('login_password')), 'Equivocada9');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();

      expect(find.text(_inactividad), findsOneWidget);
      expect(_campoCorreo(tester), _correo);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('login_enviar'))).onPressed,
        isNotNull,
      );
      expect(app.almacen.contenido[ClaveSegura.cierreForzado], startsWith('inactividad|'));
    });

    testWidgets('entrar y después «Cerrar sesión» a propósito: sin aviso ni saludo, el almacén '
        'queda vacío', (tester) async {
      final app = _AppArrancando(tester, almacenInicial: {ClaveSegura.ultimoCorreo: _correo});
      await app.montar();
      await app.finDeSesionTemprano(MotivoExpiracion.revocada);
      await _entrarDesdeElLogin(tester);
      expect(_principal, findsOneWidget);
      expect(app.container.read(avisoSesionProvider), isNull);

      await app.container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(_saludo, findsNothing);
      expect(_campoCorreo(tester), isEmpty);
      expect(app.almacen.contenido, isEmpty);
    });

    testWidgets('segundo fin de sesión (otro motivo) con el login a la vista: el aviso cambia al '
        'nuevo, una sola vez, y la persona puede entrar', (tester) async {
      final app = _AppArrancando(tester, almacenInicial: {ClaveSegura.ultimoCorreo: _correo});
      await app.montar();
      await app.finDeSesionTemprano(MotivoExpiracion.revocada);
      expect(find.text(_revocada), findsOneWidget);

      app.remoto.simularExpiracion(MotivoExpiracion.inactividad);
      await tester.pumpAndSettle();

      expect(find.text(_inactividad), findsOneWidget);
      expect(find.text(_revocada), findsNothing);
      expect(app.almacen.contenido[ClaveSegura.cierreForzado], startsWith('inactividad|'));
      await _entrarDesdeElLogin(tester);
      expect(_principal, findsOneWidget);
      expect(_aviso, findsNothing);
    });
  });

  group('QA #311 — la ventana entre publicar la sesión y cerrarla', () {
    testWidgets(
      'con el Keystore lento al guardar el motivo, mientras tanto se ve «Revisando con el '
      'servidor…» y nunca la pantalla principal; después, el login con el aviso',
      (tester) async {
        final reloj = _RelojPorTurnos();
        final app = _AppArrancando(
          tester,
          reloj: reloj,
          almacenInicial: {ClaveSegura.ultimoCorreo: _correo},
        );
        await app.montar();
        app.remoto.simularExpiracion(MotivoExpiracion.revocada);
        await tester.pump();
        app.puerta.complete();
        await tester.pump();
        await tester.pump();
        expect(reloj.turnos, hasLength(1), reason: 'la lectura de la vigencia de la sesión');
        reloj.turnos[0].complete(DateTime.now().toUtc());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // El guardado del motivo espera su turno del reloj (turno 2): la sesión ya está publicada.
        expect(reloj.turnos, hasLength(2));
        expect(_principal, findsNothing, reason: 'la sesión ya terminó');
        expect(find.byType(RevisandoCuentaPage), findsOneWidget, reason: 'espera con contexto');
        expect(find.text(_revocada), findsNothing, reason: 'el aviso sale con el login');
        reloj.turnos[1].complete(DateTime.now().toUtc());
        await tester.pumpAndSettle();
        expect(find.text(_revocada), findsOneWidget);
        expect(_principal, findsNothing);
        expect(find.byType(RevisandoCuentaPage), findsNothing);
      },
    );
  });
}
