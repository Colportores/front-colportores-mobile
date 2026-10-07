// QA de #248 (PR #297), vista 17, artboard 17-A02 «vencida y sin conexión» (HU-AUTH-003, «Edge - JWT
// expirado y sin conexión»; HU-AUTH-007). Complementa `sesion_vencida_vista17_test.dart` con los
// casos adversariales: señal que cambia mientras se escribe, lectura de la conexión que llega tarde,
// revocada contra vencida, fallas a mitad del intento, doble envío por teclado, teclado abierto,
// orden del foco y tamaños.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/tiles_falsos.dart';

const _revocada =
    'Tu sesión se cerró porque se cerró sesión en todos tus teléfonos o se cambió la contraseña. '
    'Entrá de nuevo.';
const _guardado = 'Tus visitas y cobranzas siguen guardadas en el teléfono.';
const _sinConexion = 'Tu sesión expiró. Necesitás conexión para renovarla.';
const _ayudaSinConexion = 'Vas a poder entrar cuando vuelva la señal.';

final _aviso = find.byKey(const Key('login_aviso_sesion'));
final _cerrar = find.byKey(const Key('login_aviso_sesion_cerrar'));
final _ayuda = find.byKey(const Key('login_vencida_sin_conexion_ayuda'));
final _errorGeneral = find.byKey(const Key('login_error_general'));
final _email = find.byKey(const Key('login_email'));
final _clave = find.byKey(const Key('login_password'));
final _entrar = find.byKey(const Key('login_enviar'));
final _registro = find.byKey(const Key('login_ir_a_registro'));
final _recuperar = find.text('Recuperar acceso');
final _principal = find.byKey(const Key('inicio_principal'));

SesionModel _sesionDeLucia() => SesionModel(
  usuarioId: '01920000-0000-7000-8000-000000000001',
  email: 'lucia.silva@correo.com',
  accessToken: 'jwt',
  expiraEn: DateTime.now().toUtc().add(const Duration(days: 29)),
);

/// Lo que el login muestra en el aviso de arriba (o `null` si no hay).
String? _textoDelAviso(WidgetTester tester) {
  if (_aviso.evaluate().isEmpty) return null;
  return tester.widget<Text>(find.descendant(of: _aviso, matching: find.byType(Text))).data;
}

void _pantalla(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

/// Un almacén de sesión que lee lo guardado pero no puede escribir (el Keystore falla al guardar).
final class _LocalQueNoGuarda implements AuthLocalDataSource {
  _LocalQueNoGuarda(this._sesion);

  SesionModel? _sesion;
  int intentosDeGuardar = 0;

  @override
  Future<SesionModel?> leerSesion() async => _sesion;

  @override
  Future<void> guardarSesion(SesionModel sesion) async {
    intentosDeGuardar++;
    throw StateError('el almacén seguro no responde');
  }

  @override
  Future<void> borrarSesion() async => _sesion = null;
}

/// Un almacén de sesión lento (el Keystore de un teléfono de gama baja): la lectura tarda [demora].
final class _LocalLento implements AuthLocalDataSource {
  const _LocalLento(this.demora);

  final Duration demora;

  @override
  Future<SesionModel?> leerSesion() async {
    await Future<void>.delayed(demora);
    return null;
  }

  @override
  Future<void> guardarSesion(SesionModel sesion) async {}

  @override
  Future<void> borrarSesion() async {}
}

/// Un monitor cuya primera lectura tarda [demora] (el canal de la plataforma no contesta al toque).
final class _MonitorLento implements MonitorConectividad {
  const _MonitorLento(this.demora, this.tipo);

  final Duration demora;
  final TipoConexion tipo;

  @override
  Future<TipoConexion> actual() async {
    await Future<void>.delayed(demora);
    return tipo;
  }

  @override
  Stream<TipoConexion> get cambios => const Stream<TipoConexion>.empty();
}

class _Entorno {
  _Entorno(this.remoto, this.db, this.conexion);

  final AuthRemoteDataSourceEnMemoria remoto;
  final DbLocalRepositoryEnMemoria db;
  final ConectividadFalsa conexion;
}

/// La app con la sesión de Lucía adentro, que vence por inactividad con el teléfono en [tipo].
Future<_Entorno> _vencida(
  WidgetTester tester, {
  TipoConexion tipo = TipoConexion.sinConexion,
  AuthLocalDataSource? local,
  MotivoExpiracion motivo = MotivoExpiracion.inactividad,
}) async {
  final conexion = ConectividadFalsa()..tipo = tipo;
  final remoto = AuthRemoteDataSourceEnMemoria(
    credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
  );
  final almacen = local ?? AuthLocalDataSourceEnMemoria();
  if (local == null) await almacen.guardarSesion(_sesionDeLucia());
  final db = dbLocalYaPreparada();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(db),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(almacen),
        monitorConectividadProvider.overrideWithValue(conexion),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  remoto.simularExpiracion(motivo);
  await tester.pumpAndSettle();
  return _Entorno(remoto, db, conexion);
}

/// Arranque en frío: la sesión se descartó por 30 días sin uso y no hay sesión de dónde sacar nada.
Future<AuthRemoteDataSourceEnMemoria> _arrancarEnFrio(
  WidgetTester tester, {
  required MonitorConectividad monitor,
  UltimoCorreoEnMemoria? guardado,
  AuthLocalDataSource? local,
  bool asentar = true,
}) async {
  final remoto = AuthRemoteDataSourceEnMemoria(
    credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
  )..vencidaPorInactividadAlArrancar = true;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remoto),
        authLocalDataSourceProvider.overrideWithValue(local ?? AuthLocalDataSourceEnMemoria()),
        ultimoCorreoRepositoryProvider.overrideWithValue(guardado ?? UltimoCorreoEnMemoria()),
        monitorConectividadProvider.overrideWithValue(monitor),
      ],
      child: const ColportoresApp(),
    ),
  );
  if (asentar) await tester.pumpAndSettle();
  return remoto;
}

Future<void> _tocarEntrar(WidgetTester tester, {String clave = 'Secreto123'}) async {
  await tester.enterText(_clave, clave);
  await tester.tap(_entrar);
  await tester.pumpAndSettle();
}

EditableText _editable(WidgetTester tester, Finder campo) =>
    tester.widget<EditableText>(find.descendant(of: campo, matching: find.byType(EditableText)));

void main() {
  group('QA #248 — la señal cambia mientras se escribe (señal que cambia en vuelo)', () {
    // Hallazgo B1 (menor, arreglado): pasar de 17-A01/A04 a 17-A02 (o al revés) cambia la lista de
    // hijos de la `Column` del login por arriba (aviso) y por el medio («guardadas», ayuda). Sin
    // `key` en los `_CampoLogin`, Flutter no podía emparejarlos y los volvía a crear, con lo que el
    // campo que se está escribiendo perdía el foco (se cerraba el teclado) y «Mostrar contraseña»
    // volvía a ocultar.
    for (final (nombre, desde, hasta, descartarAntes) in [
      ('17-A01 → 17-A02 (se corta la señal)', TipoConexion.wifi, TipoConexion.sinConexion, false),
      (
        '17-A04 → 17-A02 (aviso descartado y se corta)',
        TipoConexion.wifi,
        TipoConexion.sinConexion,
        true,
      ),
      ('17-A02 → 17-A01 (vuelve la señal)', TipoConexion.sinConexion, TipoConexion.wifi, false),
    ]) {
      testWidgets(
        'dado $nombre, cuando la señal cambia con la contraseña en edición, el campo sigue con '
        'el foco, lo escrito y «Mostrar contraseña»',
        (tester) async {
          final e = await _vencida(tester, tipo: desde);
          if (descartarAntes) {
            await tester.tap(_cerrar);
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byTooltip('Mostrar contraseña'));
          await tester.pump();
          await tester.tap(_clave);
          await tester.enterText(_clave, 'Secreto123');
          await tester.pump();
          expect(_editable(tester, _clave).focusNode.hasFocus, isTrue, reason: 'precondición');
          expect(_editable(tester, _clave).obscureText, isFalse, reason: 'precondición');
          final antes = tester.element(_clave);

          e.conexion.cambiarA(hasta);
          await tester.pumpAndSettle();

          // Un solo `expect` con todo el cuadro: si falla, se ve qué se perdió y qué no.
          final cuadro = {
            'mismo campo (no se volvió a crear)': identical(tester.element(_clave), antes),
            'sigue con el foco': _editable(tester, _clave).focusNode.hasFocus,
            'sigue visible (Mostrar contraseña)': !_editable(tester, _clave).obscureText,
            'conserva lo escrito': _editable(tester, _clave).controller.text == 'Secreto123',
          };
          expect(
            [
              for (final c in cuadro.entries)
                if (!c.value) c.key,
            ],
            isEmpty,
            reason: 'tras el cambio de señal',
          );
        },
      );
    }

    testWidgets('dado A02 con el intento en vuelo, cuando vuelve la señal y el servidor contesta '
        'bien, entra a la principal', (tester) async {
      final e = await _vencida(tester);
      e.remoto.demoraIniciarSesion = Completer<void>();
      await tester.enterText(_clave, 'Secreto123');
      await tester.tap(_entrar);
      await tester.pump();

      e.conexion.cambiarA(TipoConexion.wifi);
      await tester.pump();
      e.remoto.demoraIniciarSesion!.complete();
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado que el teléfono dice «sin conexión» pero el servidor contesta, cuando toca '
        '«Entrar» con la contraseña bien, entra: el aviso no bloquea el intento', (tester) async {
      final e = await _vencida(tester);
      expect(find.text(_sinConexion), findsOneWidget);

      await _tocarEntrar(tester);

      expect(e.remoto.llamadasIniciarSesion, 1);
      expect(_principal, findsOneWidget);
    });
  });

  group('QA #248 — la conexión se lee tarde en un arranque en frío', () {
    // Hallazgo B2 (menor, arreglado): `conexionProvider` es perezoso y lo leía recién el login, ya
    // dibujado: mientras la plataforma contestaba, el login afirmaba 17-A01 («Recuperar acceso» y
    // «guardadas») con el teléfono sin señal, y el lector de pantalla anunciaba dos avisos seguidos.
    // Ahora la raíz de la app la lee desde el arranque, en paralelo a la sesión.
    testWidgets(
      'dado el arranque en frío sin señal y la lectura de la sesión más lenta que la de la '
      'conexión, cuando aparece el login, nunca afirma 17-A01',
      (tester) async {
        await _arrancarEnFrio(
          tester,
          monitor: const _MonitorLento(Duration(milliseconds: 50), TipoConexion.sinConexion),
          local: const _LocalLento(Duration(milliseconds: 300)),
          guardado: UltimoCorreoEnMemoria('lucia.silva@correo.com'),
          asentar: false,
        );

        final vistos = <String?>[];
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          final texto = _textoDelAviso(tester);
          if (texto != null && (vistos.isEmpty || vistos.last != texto)) vistos.add(texto);
        }

        expect(vistos, [_sinConexion], reason: 'el login pasó por $vistos');
      },
    );

    testWidgets('dado el arranque en frío sin señal, cuando se asienta, queda 17-A02 con el correo '
        'guardado y nada de 17-A01', (tester) async {
      await _arrancarEnFrio(
        tester,
        monitor: const _MonitorLento(Duration(milliseconds: 50), TipoConexion.sinConexion),
        guardado: UltimoCorreoEnMemoria('lucia.silva@correo.com'),
      );

      expect(_textoDelAviso(tester), _sinConexion);
      expect(find.text(_guardado), findsNothing);
      expect(_recuperar, findsNothing);
      expect(tester.widget<TextField>(_email).controller!.text, 'lucia.silva@correo.com');
    });
  });

  group('QA #248 — revocada contra vencida', () {
    testWidgets('dado A02, cuando el servidor revoca la sesión, pasa a 17-A03 con su ✕ y '
        '«Recuperar acceso», y si vuelve a vencer por inactividad vuelve 17-A02', (tester) async {
      final e = await _vencida(tester);
      e.remoto.simularSinConexion = true;
      await _tocarEntrar(tester); // además marca «el último intento no llegó al servidor»
      expect(_textoDelAviso(tester), _sinConexion);

      e.remoto.simularExpiracion(MotivoExpiracion.revocada);
      await tester.pumpAndSettle();

      expect(_textoDelAviso(tester), _revocada);
      expect(_cerrar, findsOneWidget);
      expect(_recuperar, findsOneWidget);
      expect(_ayuda, findsNothing);
      expect(find.text(_sinConexion), findsNothing);
      expect(find.text(_guardado), findsNothing);

      e.remoto.simularExpiracion(MotivoExpiracion.inactividad);
      await tester.pumpAndSettle();

      expect(_textoDelAviso(tester), _sinConexion);
      expect(_cerrar, findsNothing);
      expect(_recuperar, findsNothing);
      expect(find.text(_ayudaSinConexion), findsOneWidget);
    });

    testWidgets('dado una sesión revocada y sin señal, cuando toca «Entrar», el error de entrar va '
        'debajo y el aviso de arriba sigue siendo el de 17-A03', (tester) async {
      final e = await _vencida(tester, motivo: MotivoExpiracion.revocada);
      e.remoto.simularSinConexion = true;

      await _tocarEntrar(tester);

      expect(_textoDelAviso(tester), _revocada);
      expect(_errorGeneral, findsOneWidget);
      expect(find.text(_sinConexion), findsNothing);
      expect(find.text(_ayudaSinConexion), findsNothing);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
    });
  });

  group('QA #248 — fallas a mitad del intento y entradas', () {
    testWidgets('dado A02, cuando el almacén seguro falla al guardar la sesión, el botón vuelve, '
        'hay un error debajo y el aviso de arriba sigue', (tester) async {
      final local = _LocalQueNoGuarda(_sesionDeLucia());
      await _vencida(tester, local: local);
      expect(_textoDelAviso(tester), _sinConexion);

      await _tocarEntrar(tester);

      expect(local.intentosDeGuardar, 1);
      expect(_errorGeneral, findsOneWidget);
      expect(_textoDelAviso(tester), _sinConexion);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'nada queda «Entrando…»',
      );
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
      expect(tester.widget<TextField>(_clave).controller!.text, 'Secreto123');
      expect(tester.takeException(), isNull);
    });

    testWidgets('dado A02, cuando se envía dos veces por el teclado y por el botón con la '
        'respuesta tardando, se hace una sola llamada', (tester) async {
      final e = await _vencida(tester);
      e.remoto
        ..simularSinConexion = true
        ..demoraIniciarSesion = Completer<void>();
      await tester.enterText(_clave, 'Secreto123');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.tap(_entrar, warnIfMissed: false);
      await tester.pump();
      e.remoto.demoraIniciarSesion!.complete();
      await tester.pumpAndSettle();

      expect(e.remoto.llamadasIniciarSesion, 1);
      expect(_textoDelAviso(tester), _sinConexion);
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
    });

    testWidgets('dado el arranque en frío sin correo guardado y sin señal, cuando toca «Entrar» '
        'con todo vacío, cada campo dice qué falta, no sale a la red y el aviso sigue', (
      tester,
    ) async {
      final remoto = await _arrancarEnFrio(
        tester,
        monitor: ConectividadFalsa()..tipo = TipoConexion.sinConexion,
      );
      expect(_textoDelAviso(tester), _sinConexion);
      expect(tester.widget<TextField>(_email).controller!.text, isEmpty);

      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(remoto.llamadasIniciarSesion, 0);
      expect(_textoDelAviso(tester), _sinConexion);
    });

    testWidgets('dado A02, cuando se pega una contraseña larguísima y un correo con emoji, el '
        'login lo valida sin salirse de la pantalla', (tester) async {
      final e = await _vencida(tester);
      await tester.enterText(_email, 'lucía😀@correo.com');
      await tester.enterText(_clave, 'a' * 500);
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_textoDelAviso(tester), _sinConexion);
      expect(e.remoto.llamadasIniciarSesion, lessThanOrEqualTo(1));
      expect(tester.widget<FilledButton>(_entrar).onPressed, isNotNull);
    });
  });

  group('QA #248 — navegación', () {
    testWidgets('dado A02, cuando se abre «Registrate» y se vuelve, el aviso, la ayuda y lo '
        'escrito siguen igual', (tester) async {
      await _vencida(tester);
      await tester.enterText(_clave, 'Secreto123');

      await tester.ensureVisible(_registro);
      await tester.tap(_registro);
      await tester.pumpAndSettle();
      expect(find.byType(RegistroPage), findsOneWidget);

      Navigator.of(tester.element(find.byType(RegistroPage))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(RegistroPage), findsNothing);
      expect(_textoDelAviso(tester), _sinConexion);
      expect(find.text(_ayudaSinConexion), findsOneWidget);
      expect(tester.widget<TextField>(_clave).controller!.text, 'Secreto123');
      expect(tester.widget<TextField>(_email).controller!.text, 'lucia.silva@correo.com');
    });

    testWidgets('dado A02, cuando se recorre con Tab, el foco pasa por correo, contraseña, ojo, '
        '«Mantener sesión», «Entrar» y «Registrate» sin trampas y sin «Recuperar acceso»', (
      tester,
    ) async {
      _pantalla(tester, const Size(412, 915));
      await _vencida(tester);

      String? dondeEstaElFoco() {
        final contexto = FocusManager.instance.primaryFocus?.context;
        if (contexto == null) return null;
        bool dentroDe(Finder f) {
          if (f.evaluate().isEmpty) return false;
          final objetivo = tester.element(f);
          if (contexto == objetivo) return true;
          var halla = false;
          contexto.visitAncestorElements((a) {
            if (a == objetivo) halla = true;
            return !halla;
          });
          return halla;
        }

        if (dentroDe(find.byTooltip('Mostrar contraseña'))) return 'ojo';
        if (dentroDe(_email)) return 'correo';
        if (dentroDe(_clave)) return 'contraseña';
        if (dentroDe(find.byType(Checkbox))) return 'mantener';
        if (dentroDe(_entrar)) return 'entrar';
        if (dentroDe(_registro)) return 'registro';
        return 'otro';
      }

      final visitados = <String?>[];
      for (var i = 0; i < 7; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        visitados.add(dondeEstaElFoco());
      }

      expect(visitados.take(6), ['correo', 'contraseña', 'ojo', 'mantener', 'entrar', 'registro']);
      expect(visitados[6], 'correo', reason: 'dio la vuelta: no hay trampa de foco');
      expect(_recuperar, findsNothing);
    });
  });

  group('QA #248 — teclado abierto, tamaños y guías', () {
    testWidgets('360x640 con el teclado abierto: sin overflow y «Entrar» se alcanza y funciona', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      final e = await _vencida(tester);
      e.remoto.simularSinConexion = true;

      await tester.enterText(_clave, 'Secreto123');
      await tester.pumpAndSettle();
      await tester.ensureVisible(_entrar);
      await tester.pumpAndSettle();
      await tester.tap(_entrar);
      await tester.pumpAndSettle();

      expect(e.remoto.llamadasIniciarSesion, 1);
      expect(_textoDelAviso(tester), _sinConexion);
      expect(tester.takeException(), isNull);
    });

    for (final (nombre, tam, texto) in [
      ('360x640', const Size(360, 640), 1.0),
      ('360x640 al 200 %', const Size(360, 640), 2.0),
      ('412x915', const Size(412, 915), 1.0),
      ('412x915 al 200 %', const Size(412, 915), 2.0),
    ]) {
      testWidgets('$nombre: 17-A02 sin overflow, con las guías de toque, etiqueta y contraste', (
        tester,
      ) async {
        _pantalla(tester, tam, texto: texto);
        final semantica = tester.ensureSemantics();
        await _vencida(tester);

        expect(_textoDelAviso(tester), _sinConexion);
        await _guias(tester);
        semantica.dispose();
      });
    }
  });

  group('QA #248 — tras «Entrar» sin conexión el aviso de 17-A02 queda a la vista', () {
    // Hallazgo B3 (bloqueante, arreglado): el login lleva el aviso arriba de la vista tras un
    // «Entrar» sin conexión (`_llevarAVista(_claveAvisoSesion, alineacion: 0)`), pero el campo de
    // contraseña seguía con el foco y su cursor pedía ser visible: ganaba el cursor y el aviso
    // quedaba cortado o fuera de la pantalla, justo el «el toque parecía no hacer nada» que el PR
    // dice evitar. Ahora el campo suelta el foco al fallar sin conexión en 17-A02.
    for (final (nombre, texto, teclado) in [
      ('360x640 al 200 %, sin teclado', 2.0, 0.0),
      ('360x640 al 200 %, teclado abierto', 2.0, 280.0),
    ]) {
      testWidgets('$nombre: el aviso entero se ve después de «Entrar» sin conexión', (
        tester,
      ) async {
        const alto = 640.0;
        _pantalla(tester, const Size(360, alto), texto: texto);
        tester.view.viewInsets = FakeViewPadding(bottom: teclado);
        addTearDown(tester.view.resetViewInsets);
        final e = await _vencida(tester);
        e.remoto.simularSinConexion = true;

        // A 200 % «Entrar» queda debajo del borde: se baja hasta él, como lo hace quien usa la app
        // (sin esto el toque cae fuera del botón y el intento no sale).
        await tester.enterText(_clave, 'Secreto123');
        await tester.pumpAndSettle();
        await tester.ensureVisible(_entrar);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(_aviso).top,
          lessThan(0),
          reason: 'precondición: aviso fuera de vista',
        );
        await tester.tap(_entrar);
        await tester.pumpAndSettle();

        expect(e.remoto.llamadasIniciarSesion, 1, reason: 'el toque llegó al botón');
        final r = tester.getRect(_aviso);
        final visibles = alto - teclado;
        expect(
          {'arriba': r.top >= 0, 'abajo': r.bottom <= visibles},
          {'arriba': true, 'abajo': true},
          reason: 'el aviso quedó en y=${r.top}..${r.bottom} con ${visibles}dp de pantalla útil',
        );
        expect(
          _editable(tester, _clave).focusNode.hasFocus,
          isFalse,
          reason: 'el campo suelta el foco: su cursor no le gana al desplazamiento hacia el aviso',
        );
      });
    }
  });

  group('QA #248 — privacidad', () {
    test('ni el motivo de reingreso ni el aviso de 17-A02 sueltan el correo o el nombre en un '
        'toString', () {
      const datos = DatosReingreso(
        motivo: MotivoExpiracion.inactividad,
        email: 'lucia.silva@correo.com',
        nombre: 'Lucía',
      );

      expect(datos.toString(), isNot(contains('lucia.silva')));
      expect(datos.toString(), isNot(contains('Lucía')));
      expect(const FailureSesionVencidaSinConexion().toString(), isNot(contains('@')));
    });
  });
}
