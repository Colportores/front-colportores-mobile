// QA del PR #308 (issue #302): el motivo del último cierre forzado se guarda y el aviso de la vista
// 17 vuelve en cada arranque sin sesión hasta que la persona entra (decisión de Cristian, 07/10).
//
// Tres partes:
//  1. Los cuatro artboards de la vista 17 (A01 a A04) en el SEGUNDO arranque, a 360x640 y 412x915,
//     con texto 100 % y 200 %: textos del canvas, guías de accesibilidad de Flutter, sin overflow,
//     semántica y foco del aviso. Capturas en `.dart_tool/qa_capturas/` (gitignored).
//  2. El cierre a propósito: ni aviso ni correo en la misma corrida ni en el arranque siguiente.
//  3. Hallazgos de la revisión (M1, M2, M3) reproducidos con un test cada uno.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/recuperacion_password_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cierre_forzado_repository_impl.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/cierre_forzado.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/cierre_forzado_repository.dart';
import 'package:colportores_mobile/features/auth/domain/services/reloj_sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/confirmar_recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/aviso_sesion_notifier.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/recuperacion_password_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/logger_mudo.dart';
import '../helpers/tiles_falsos.dart';

const _correo = 'lucia.silva@correo.com';
const _password = 'Secreto123';
const _inactividad = 'Tu sesión expiró por inactividad. Iniciá sesión nuevamente.';
const _revocada =
    'Tu sesión se cerró porque se cerró sesión en todos tus teléfonos o se cambió la contraseña. '
    'Entrá de nuevo.';

/// Texto literal de HU-AUTH-003, «Edge - JWT expirado y sin conexión» (17-A02).
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

/// Lo que guarda el almacén seguro cuando el cierre ya se detectó en un arranque anterior.
const _guardadoInactividad = 'inactividad|2026-10-07T08:02:30.000Z';
const _guardadoRevocada = 'revocada|2026-10-07T08:02:30.000Z';

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

/// Con `--dart-define=QA_CAPTURAS=true` el test carga las fuentes del proyecto y escribe un PNG de
/// cada estado en `.dart_tool/qa_capturas/` (gitignored). Con las fuentes reales la guía de
/// contraste de Flutter mide el borde suavizado de las letras chicas y da falsos negativos (la
/// misma razón que en `qa_vista15_a06_test.dart`): en ese modo no corre; en el CI sí, con la
/// fuente de prueba (bloques sólidos).
const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

Future<void> _cargarFuentes(WidgetTester tester) async {
  if (!_conCapturas) return;
  await _cargarFuentesReales(tester);
}

Future<void> _cargarFuentesReales(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final loader = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
});

/// Captura fuera del repo: `.dart_tool` está en el .gitignore y se borra al cerrar el QA.
Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await _capturarPng(tester, nombre);
}

Future<void> _capturarPng(WidgetTester tester, String nombre) => tester.runAsync(() async {
  final render = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final img = await render.toImage();
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
  File('${dir.path}/308_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
});

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (!_conCapturas) await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

/// Dónde está el foco: dentro del widget que encuentra [donde].
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

/// Un arranque de la app con el almacén seguro [almacen] (el cierre y el correo ya guardados).
Future<ProviderContainer> _arrancar(
  WidgetTester tester,
  AlmacenSeguroEnMemoria almacen, {
  ConectividadFalsa? conectividad,
  AuthRemoteDataSourceEnMemoria? remoto,
}) async {
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        remoto ?? AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(almacen)),
      cierreForzadoRepositoryProvider.overrideWithValue(CierreForzadoRepositoryImpl(almacen)),
      if (conectividad != null) monitorConectividadProvider.overrideWithValue(conectividad),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
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

/// Un almacén que tarda en escribir: sirve para ordenar las operaciones.
final class _AlmacenLento implements AlmacenSeguro {
  String? contenido;
  final operaciones = <String>[];

  @override
  Future<String?> leer(ClaveSegura clave) async => contenido;

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    operaciones.add('escribir');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    contenido = valor;
  }

  @override
  Future<void> borrar(ClaveSegura clave) async {
    operaciones.add('borrar');
    contenido = null;
  }

  @override
  Future<void> borrarTodo() async => contenido = null;
}

/// Control del test de la carrera: el mismo almacén lento pero SIN la cola del repositorio real.
/// Si el test de la carrera no falla con este, no prueba nada.
final class _CierreSinCola implements CierreForzadoRepository {
  _CierreSinCola(this._almacen);

  final _AlmacenLento _almacen;

  @override
  Future<CierreForzado?> leer() async => null;

  @override
  Future<void> guardar(CierreForzado cierre) =>
      _almacen.escribir(ClaveSegura.cierreForzado, 'x|${cierre.fecha.toIso8601String()}');

  @override
  Future<void> borrar() => _almacen.borrar(ClaveSegura.cierreForzado);
}

/// Un reloj de la sesión cuya lectura tarda hasta que el test la completa (el Keystore lento).
final class _RelojLento implements RelojSesion {
  final puerta = Completer<DateTime>();

  @override
  Future<DateTime> ahora() => puerta.future;

  @override
  Future<void> registrar(DateTime visto) async {}
}

/// El cierre guardado se lee cuando el test abre la [puerta]: un teléfono lento al arrancar.
final class _CierreQueTardaEnLeer implements CierreForzadoRepository {
  _CierreQueTardaEnLeer(this.puerta, this._cierre);

  final Completer<void> puerta;
  CierreForzado? _cierre;

  @override
  Future<CierreForzado?> leer() async {
    await puerta.future;
    return _cierre;
  }

  @override
  Future<void> guardar(CierreForzado cierre) async => _cierre = cierre;

  @override
  Future<void> borrar() async => _cierre = null;
}

void main() {
  group('QA #302 — vista 17 en el segundo arranque: los cuatro artboards', () {
    // (nombre del artboard, qué hay guardado, sin señal, descarta con la ✕)
    final artboards = <(String, String, bool, bool)>[
      ('A01', _guardadoInactividad, false, false),
      ('A02', _guardadoInactividad, true, false),
      ('A03', _guardadoRevocada, false, false),
      ('A04', _guardadoInactividad, false, true),
    ];
    final tamanios = <(Size, double)>[
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 1.0),
      (const Size(412, 915), 2.0),
    ];

    for (final (nombre, guardadoEnAlmacen, sinSenal, descarta) in artboards) {
      for (final (tam, texto) in tamanios) {
        testWidgets(
          '17-$nombre en el segundo arranque, ${tam.width.toInt()}x${tam.height.toInt()} a '
          '${(texto * 100).toInt()} %: textos del canvas, sin overflow y con las guías de '
          'accesibilidad',
          (tester) async {
            _pantalla(tester, tam, texto: texto);
            final semantica = tester.ensureSemantics();
            await _cargarFuentes(tester);
            final almacen = AlmacenSeguroEnMemoria({
              ClaveSegura.ultimoCorreo: _correo,
              ClaveSegura.cierreForzado: guardadoEnAlmacen,
            });
            final conexion = ConectividadFalsa()
              ..tipo = sinSenal ? TipoConexion.sinConexion : TipoConexion.wifi;

            await _arrancar(tester, almacen, conectividad: conexion);
            if (descarta) {
              await tester.ensureVisible(_cerrar);
              await tester.tap(_cerrar);
              await tester.pumpAndSettle();
            }

            expect(_campoCorreo(tester), _correo, reason: 'el correo viene del almacén seguro');
            expect(find.text('Hola de nuevo'), findsOneWidget);
            expect(_saludo, findsOneWidget);
            switch (nombre) {
              case 'A01':
                expect(find.text(_inactividad), findsOneWidget);
                expect(_cerrar, findsOneWidget);
                expect(_datosGuardados, findsOneWidget);
                expect(find.text(_guardado), findsOneWidget);
                expect(_recuperar, findsOneWidget);
              case 'A02':
                expect(find.text(_sinConexion), findsOneWidget);
                expect(_borde, findsOneWidget, reason: 'borde de trazos del canvas');
                expect(_cerrar, findsNothing, reason: 'A02 dura mientras no haya señal: sin ✕');
                expect(find.text(_ayudaSinConexion), findsOneWidget);
                expect(_datosGuardados, findsNothing);
                expect(_recuperar, findsNothing, reason: 'recuperar también pide red');
              case 'A03':
                expect(find.text(_revocada), findsOneWidget);
                expect(_cerrar, findsOneWidget);
                expect(_datosGuardados, findsNothing, reason: 'el canvas A03 no lo dibuja');
                expect(_recuperar, findsOneWidget);
                expect(_ayuda, findsNothing);
              case 'A04':
                expect(_aviso, findsNothing);
                expect(_datosGuardados, findsOneWidget);
                expect(_recuperar, findsOneWidget);
            }
            // Nada se sale por la derecha.
            final ancho = tester.view.physicalSize.width;
            for (final f in [_saludo, find.byKey(const Key('login_email')), _aviso]) {
              if (f.evaluate().isEmpty) continue;
              expect(tester.getRect(f).right, lessThanOrEqualTo(ancho), reason: '$f');
              expect(tester.getRect(f).left, greaterThanOrEqualTo(0));
            }
            await _guias(tester);
            await _capturar(
              tester,
              '${nombre}_${tam.width.toInt()}x${tam.height.toInt()}_${texto.toInt()}x',
            );
            semantica.dispose();
          },
        );
      }
    }

    testWidgets('el aviso del segundo arranque es una región viva y la ✕ tiene etiqueta', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: _correo,
        ClaveSegura.cierreForzado: _guardadoRevocada,
      });

      await _arrancar(tester, almacen);

      expect(tester.getSemantics(_aviso), isSemantics(isLiveRegion: true));
      expect(find.byTooltip('Cerrar aviso'), findsOneWidget);
      expect(tester.getSemantics(_cerrar), isSemantics(isButton: true, tooltip: 'Cerrar aviso'));
      semantica.dispose();
    });

    testWidgets('foco con el teclado: el primer Tab llega a la ✕ del aviso y después al correo, '
        'en el orden en que se ve', (tester) async {
      final almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: _correo,
        ClaveSegura.cierreForzado: _guardadoInactividad,
      });
      await _arrancar(tester, almacen);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focoEn(tester, _cerrar), isTrue, reason: 'primero el aviso');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        _focoEn(tester, find.byKey(const Key('login_email'))),
        isTrue,
        reason:
            'después el '
            'correo',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focoEn(tester, find.byKey(const Key('login_password'))), isTrue);
    });

    testWidgets('17-A02 sin ✕: el primer Tab va directo al correo', (tester) async {
      final almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: _correo,
        ClaveSegura.cierreForzado: _guardadoInactividad,
      });
      await _arrancar(
        tester,
        almacen,
        conectividad: ConectividadFalsa()..tipo = TipoConexion.sinConexion,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(_focoEn(tester, find.byKey(const Key('login_email'))), isTrue);
    });

    testWidgets('con el motivo guardado pero sin correo: aviso y saludo igual, campo vacío', (
      tester,
    ) async {
      final almacen = AlmacenSeguroEnMemoria({ClaveSegura.cierreForzado: _guardadoInactividad});

      await _arrancar(tester, almacen);

      expect(find.text(_inactividad), findsOneWidget);
      expect(find.text('Hola de nuevo'), findsOneWidget);
      expect(_campoCorreo(tester), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'entrar con una contraseña incorrecta en el segundo arranque: el aviso, el correo y '
      'lo tipeado se conservan y el botón vuelve',
      (tester) async {
        final almacen = AlmacenSeguroEnMemoria({
          ClaveSegura.ultimoCorreo: _correo,
          ClaveSegura.cierreForzado: _guardadoInactividad,
        });
        await _arrancar(tester, almacen);

        await tester.enterText(find.byKey(const Key('login_password')), 'Equivocada9');
        await tester.tap(find.byKey(const Key('login_enviar')));
        await tester.pumpAndSettle();

        expect(find.text(_inactividad), findsOneWidget);
        expect(_campoCorreo(tester), _correo);
        expect(
          tester.widget<FilledButton>(find.byKey(const Key('login_enviar'))).onPressed,
          isNotNull,
        );
        expect(almacen.contenido[ClaveSegura.cierreForzado], _guardadoInactividad);
      },
    );
  });

  group('QA #302 — cierre manual: sin aviso, ni ahora ni después', () {
    testWidgets('segundo arranque, entra y toca «Cerrar sesión»: el login sale sin aviso ni '
        'saludo y el almacén queda vacío; el arranque siguiente también', (tester) async {
      final almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: _correo,
        ClaveSegura.cierreForzado: _guardadoInactividad,
      });
      final container = await _arrancar(tester, almacen);
      await _entrarDesdeElLogin(tester);
      expect(_principal, findsOneWidget);

      await container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(_saludo, findsNothing);
      expect(find.text('Iniciá tu jornada'), findsOneWidget);
      expect(_campoCorreo(tester), isEmpty);
      expect(almacen.contenido, isEmpty);
      await _reiniciarApp(tester);
      await _arrancar(tester, almacen);
      expect(_aviso, findsNothing);
      expect(_saludo, findsNothing);
      expect(_campoCorreo(tester), isEmpty);
    });

    testWidgets('revocada con la app abierta y después «Cerrar sesión» a propósito tras volver a '
        'entrar: el arranque siguiente es un login común', (tester) async {
      final almacen = AlmacenSeguroEnMemoria();
      final remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password});
      final container = await _arrancar(tester, almacen, remoto: remoto);
      await _entrarDesdeElLogin(tester);
      remoto.simularExpiracion(MotivoExpiracion.revocada);
      await tester.pumpAndSettle();
      expect(find.text(_revocada), findsOneWidget);
      expect(almacen.contenido[ClaveSegura.cierreForzado], startsWith('revocada|'));

      await _entrarDesdeElLogin(tester);
      await container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pumpAndSettle();

      expect(almacen.contenido, isEmpty);
      await _reiniciarApp(tester);
      await _arrancar(tester, almacen);
      expect(_aviso, findsNothing);
      expect(_saludo, findsNothing);
    });
  });

  group('QA #302 — privacidad', () {
    test('el motivo guardado no lleva el correo: ni en el valor del almacén ni en el toString', () {
      final cierre = CierreForzado(
        motivo: MotivoExpiracion.revocada,
        fecha: DateTime.utc(2026, 10, 7, 8, 2, 30),
      );

      expect(cierre.toString(), isNot(contains(_correo)));
      expect(_guardadoRevocada, isNot(contains('@')));
    });
  });

  group('QA #302 — hallazgos de la revisión', () {
    testWidgets('M2: registrar una cuenta (que queda pendiente de verificar) limpia el motivo y el '
        'aviso de la cuenta anterior; el arranque siguiente es un login común con el correo nuevo', (
      tester,
    ) async {
      // Decisión del 07/10 (P1 del archivo de pendientes de este QA): un registro que termina bien,
      // con sesión o sin ella, deja atrás la cuenta anterior.
      final almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: _correo,
        ClaveSegura.cierreForzado: _guardadoInactividad,
      });
      final remoto = AuthRemoteDataSourceEnMemoria(
        credenciales: const {_correo: _password},
        requiereVerificacionAlRegistrar: true,
      );
      final container = await _arrancar(tester, almacen, remoto: remoto);
      expect(find.text(_inactividad), findsOneWidget);

      final resultado = await container
          .read(sesionProvider.notifier)
          .registrar(
            nombre: 'Ana',
            apellido: 'Pérez',
            cedula: '12345672',
            email: 'Nueva@Correo.com',
            password: _password,
            aceptaTerminos: true,
            aceptaTradeOffE2E: true,
          );
      await tester.pumpAndSettle();

      expect(resultado.isRight(), isTrue);
      expect(container.read(sesionProvider).value, isNull, reason: 'falta verificar el email');
      expect(container.read(avisoSesionProvider), isNull);
      expect(find.text(_inactividad), findsNothing);
      expect(almacen.contenido.containsKey(ClaveSegura.cierreForzado), isFalse);
      expect(almacen.contenido[ClaveSegura.ultimoCorreo], 'nueva@correo.com');
      await _reiniciarApp(tester);
      await _arrancar(tester, almacen);
      expect(_aviso, findsNothing, reason: 'login común: no hay motivo guardado');
      expect(find.text(_inactividad), findsNothing);
      expect(_campoCorreo(tester), 'nueva@correo.com', reason: 'el correo de la cuenta nueva');
    });

    // M3 (arreglado en `app.dart`): con un motivo guardado, el aviso se fija al final de `build()`;
    // el `popUntil(isFirst)` sacaba la pantalla «Nueva contraseña» de un enlace de recuperación que
    // llegó antes y la persona quedaba en el login con el aviso (y el enlace gastado).
    testWidgets(
      'M3: arranque en frío con el motivo guardado y el enlace de recuperación que llega antes de '
      'que se lea el almacén: la pantalla de la contraseña nueva se queda',
      (tester) async {
        final puerta = Completer<void>();
        final recuperacion = RecuperacionPasswordEnMemoria();
        final container = ProviderContainer(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
            recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(recuperacion),
            cierreForzadoRepositoryProvider.overrideWithValue(
              _CierreQueTardaEnLeer(
                puerta,
                CierreForzado(
                  motivo: MotivoExpiracion.inactividad,
                  fecha: DateTime.utc(2026, 10, 7, 8, 2, 30),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        // La app se monta con la sesión todavía cargándose (el Keystore tarda).
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: const ColportoresApp()),
        );
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        recuperacion.simularEnlace(EnlaceRecuperacion.valido);
        await tester.pump();
        await tester.pump();
        expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);

        puerta.complete();
        await tester.pumpAndSettle();

        expect(
          find.byType(ConfirmarRecuperacionPasswordPage),
          findsOneWidget,
          reason: 'la pantalla del enlace no se debe ir porque terminó de leerse el almacén',
        );
      },
    );

    // M3 (mismo origen): el enlace de verificación del email que llega antes.
    testWidgets(
      'M3: arranque en frío con el motivo guardado y el enlace de verificación que llega antes de '
      'que se lea el almacén: «Email verificado» se queda',
      (tester) async {
        final puerta = Completer<void>();
        final remoto = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password});
        final container = ProviderContainer(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(remoto),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
            cierreForzadoRepositoryProvider.overrideWithValue(
              _CierreQueTardaEnLeer(
                puerta,
                CierreForzado(
                  motivo: MotivoExpiracion.revocada,
                  fecha: DateTime.utc(2026, 10, 7, 8, 2, 30),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: const ColportoresApp()),
        );
        await tester.pump();

        remoto.simularEnlaceVerificacionExitoso('nueva@correo.com');
        await tester.pump();
        await tester.pump();
        expect(find.byType(VerificacionEmailPage), findsOneWidget);

        puerta.complete();
        await tester.pumpAndSettle();

        expect(find.byType(VerificacionEmailPage), findsOneWidget);
      },
    );

    testWidgets('M3 (control): con el almacén ya leído, el enlace de recuperación que llega '
        'después abre la pantalla de la contraseña nueva sobre el login con aviso', (tester) async {
      final almacen = AlmacenSeguroEnMemoria({
        ClaveSegura.ultimoCorreo: _correo,
        ClaveSegura.cierreForzado: _guardadoInactividad,
      });
      final recuperacion = RecuperacionPasswordEnMemoria();
      final container = ProviderContainer(
        overrides: [
          dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
          authRemoteDataSourceProvider.overrideWithValue(
            AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password}),
          ),
          authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          recuperacionPasswordRemoteDataSourceProvider.overrideWithValue(recuperacion),
          ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoRepositoryImpl(almacen)),
          cierreForzadoRepositoryProvider.overrideWithValue(CierreForzadoRepositoryImpl(almacen)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const ColportoresApp()),
      );
      await tester.pumpAndSettle();
      expect(find.text(_inactividad), findsOneWidget);

      recuperacion.simularEnlace(EnlaceRecuperacion.valido);
      await tester.pumpAndSettle();

      expect(find.byType(ConfirmarRecuperacionPasswordPage), findsOneWidget);
    });

    group('M1 — la carrera entre el fin de sesión forzado (stream) y un «Entrar» enseguida', () {
      ProviderContainer contenedor(CierreForzadoRepository cierres, {RelojSesion? reloj}) {
        final c = ProviderContainer(
          overrides: [
            if (reloj != null) relojSesionProvider.overrideWithValue(reloj),
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _password}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
            cierreForzadoRepositoryProvider.overrideWithValue(cierres),
          ],
        );
        addTearDown(c.dispose);
        return c;
      }

      test('el servidor revoca con el login a la vista y la persona entra sin esperar el guardado: '
          'queda sin motivo guardado (con la cola del repositorio)', () async {
        final lento = _AlmacenLento();
        final container = contenedor(CierreForzadoRepositoryImpl(lento, logger: loggerMudo()));
        await container.read(sesionProvider.future);
        final remoto = container.read(authRemoteDataSourceProvider);

        (remoto as AuthRemoteDataSourceEnMemoria).simularExpiracion(MotivoExpiracion.revocada);
        final falla = await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: _correo, password: _password);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(falla, isNull);
        expect(lento.operaciones, ['escribir', 'borrar']);
        expect(lento.contenido, isNull);
      });

      // M1b (arreglado en `SesionNotifier._guardarCierre`): la cola del repositorio ordena `guardar` y
      // `borrar` desde que se piden, pero `_alExpirar` primero espera `relojSesion.ahora()` (Keystore)
      // y recién después pedía `guardar`: si «Entrar» terminaba antes, el `borrar` entraba primero en
      // la cola y el motivo quedaba guardado con la persona adentro.
      test('M1b: la lectura del reloj tarda y la persona entra antes: el motivo no queda guardado '
          'con la sesión abierta', () async {
        final lento = _AlmacenLento();
        final reloj = _RelojLento();
        final container = contenedor(
          CierreForzadoRepositoryImpl(lento, logger: loggerMudo()),
          reloj: reloj,
        );
        await container.read(sesionProvider.future);
        final remoto = container.read(authRemoteDataSourceProvider);

        (remoto as AuthRemoteDataSourceEnMemoria).simularExpiracion(MotivoExpiracion.revocada);
        await pumpEventQueue();
        final falla = await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: _correo, password: _password);
        reloj.puerta.complete(DateTime.utc(2026, 10, 7, 8, 2, 30));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(falla, isNull);
        expect(container.read(sesionProvider).value, isNotNull);
        expect(lento.contenido, isNull, reason: 'entró: el motivo no debería quedar guardado');
      });

      test('control: sin la cola el mismo escenario deja el motivo guardado (el test de arriba sí '
          'puede fallar)', () async {
        final lento = _AlmacenLento();
        final container = contenedor(_CierreSinCola(lento));
        await container.read(sesionProvider.future);
        final remoto = container.read(authRemoteDataSourceProvider);

        (remoto as AuthRemoteDataSourceEnMemoria).simularExpiracion(MotivoExpiracion.revocada);
        await container
            .read(sesionProvider.notifier)
            .iniciarSesion(email: _correo, password: _password);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(lento.contenido, isNotNull, reason: 'sin cola, el guardado lento pisa al borrado');
      });
    });
  });
}
