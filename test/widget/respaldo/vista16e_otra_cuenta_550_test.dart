// #550 (HU-SYNC-004) — Vista 16, 16E·01 a 16E·04: Ana reconecta su Drive y, sin darse cuenta, elige otra
// cuenta de Google. La hoja le dice dónde quedó su respaldo anterior y con qué cuenta sigue. Un test
// por artboard, con el texto literal del canvas, más los casos límite: doble toque, falla a mitad,
// cancelar en Google, cerrar y reentrar, sin conexión y letra al 200 %.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../helpers/db_local_repository_en_memoria.dart';
import '../../helpers/respaldo_drive_falsos.dart';

const _otra = CuentaGoogle(id: 'g-200', email: 'ana.casa@gmail.com');
const _tercera = CuentaGoogle(id: 'g-300', email: 'ana.trabajo@gmail.com');
const _anterior = 'ana.gomez@gmail.com';
const _nueva = 'ana.casa@gmail.com';

Future<ProviderContainer> _montar(
  WidgetTester tester,
  RespaldoDriveArmado drive, {
  TipoConexion? conexion,
  Future<void> Function(String usuarioId)? antes,
  Size pantalla = const Size(2400, 3000),
  double? escalaTexto,
  DateTime Function()? ultimo,
}) async {
  tester.view.physicalSize = pantalla;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (escalaTexto != null) {
    tester.platformDispatcher.textScaleFactorTestValue = escalaTexto;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      respaldoDriveRepositoryProvider.overrideWithValue(drive.repo),
      if (conexion != null) conexionProvider.overrideWith((ref) => Stream.value(conexion)),
      if (ultimo != null) ultimoRespaldoDriveProvider.overrideWith((ref) => Stream.value(ultimo())),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container
      .read(sesionProvider.notifier)
      .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
  final usuarioId = container.read(sesionProvider).value!.usuarioId;
  await antes?.call(usuarioId);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('inicio_configuracion')));
  await tester.pumpAndSettle();
  return container;
}

Finder get _fila => find.byKey(const Key('configuracion_drive_fila'));
Finder get _hojaOtra => find.byKey(const Key('drive_hoja_otra_cuenta'));
Finder get _hojaSeguir => find.byKey(const Key('drive_hoja_seguir_con_la_nueva'));
Finder get _conectar => find.byKey(const Key('drive_conectar'));
Finder get _volver => find.byKey(const Key('drive_otra_cuenta_volver'));
Finder get _seguir => find.byKey(const Key('drive_otra_cuenta_seguir'));
Finder get _confirmarSeguir => find.byKey(const Key('drive_otra_cuenta_confirmar_seguir'));
Finder get _confirmarVolver => find.byKey(const Key('drive_otra_cuenta_confirmar_volver'));
Finder get _error => find.byKey(const Key('drive_hoja_otra_cuenta_error'));
Finder get _sinConexion => find.byKey(const Key('drive_hoja_otra_cuenta_sin_conexion'));
Finder get _snackVolvio => find.byKey(const Key('configuracion_drive_volvio'));
Finder get _snackConectado => find.byKey(const Key('configuracion_drive_conectado'));

Finder _dentro(Finder hoja, String texto) => find.descendant(of: hoja, matching: find.text(texto));

Future<void> _verFila(WidgetTester tester) async {
  await tester.scrollUntilVisible(_fila, 200, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(_fila), alignment: 0.4);
  await tester.pumpAndSettle();
}

Future<void> _tocarFila(WidgetTester tester) async {
  await _verFila(tester);
  await tester.tap(_fila);
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Ana tenía su respaldo en la cuenta de siempre y Google ya le devolvió otra: queda por confirmar.
Future<void> Function(String) _porConfirmar(RespaldoDriveArmado a) => (u) async {
  await a.repo.conectar(u);
  a.google.cuenta = _otra;
  await a.repo.conectar(u);
};

/// Ana tenía su respaldo en la cuenta de siempre, se le perdió el permiso y va a reconectar con otra.
Future<void> Function(String) _revocadaYOtraCuenta(RespaldoDriveArmado a) => (u) async {
  await a.repo.conectar(u);
  await a.repo.marcarPermisoRevocado(u);
  a.google.cuenta = _otra;
};

void main() {
  late RespaldoDriveArmado drive;
  late PrimerRespaldoFalso primero;

  // El armado se crea dentro del test: el `setUp` corre fuera de la zona del reloj falso.
  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      primero = PrimerRespaldoFalso();
      drive = RespaldoDriveArmado(primerRespaldo: primero);
      await cuerpo(tester);
    });
  }

  group('16E·01 Hoja al terminar de conectar', () {
    prueba('Reconectar con otra cuenta abre la hoja con las dos cuentas y el último respaldo', (
      tester,
    ) async {
      await _montar(
        tester,
        drive,
        antes: _revocadaYOtraCuenta(drive),
        ultimo: () => DateTime(2026, 10, 20, 3, 10),
      );
      primero.llamadas = 0;
      await _tocarFila(tester);
      await _tocar(tester, _conectar);

      expect(_hojaOtra, findsOneWidget);
      expect(_dentro(_hojaOtra, 'Esta no es la cuenta de tu respaldo'), findsOneWidget);
      expect(
        _dentro(
          _hojaOtra,
          'Tu respaldo anterior quedó en $_anterior. Ahora te conectaste con $_nueva.',
        ),
        findsOneWidget,
      );
      expect(_dentro(_hojaOtra, 'Respaldo anterior'), findsOneWidget);
      expect(
        _dentro(_hojaOtra, _anterior),
        findsNWidgets(1),
        reason: 'la fila de la cuenta anterior',
      );
      expect(_dentro(_hojaOtra, 'Último respaldo'), findsOneWidget);
      expect(_dentro(_hojaOtra, '20/10 · 03:10'), findsOneWidget);
      expect(_dentro(_hojaOtra, 'Cuenta de ahora'), findsOneWidget);
      expect(_dentro(_hojaOtra, _nueva), findsOneWidget);
      expect(
        _dentro(_hojaOtra, 'No se borra nada: el respaldo anterior sigue en la otra cuenta.'),
        findsOneWidget,
      );
      expect(_dentro(_hojaOtra, 'Volver a la cuenta anterior'), findsOneWidget);
      expect(_dentro(_hojaOtra, 'Seguir con la cuenta nueva'), findsOneWidget);
      expect(primero.llamadas, 0, reason: 'antes de elegir no se respalda nada en la cuenta nueva');
    });

    prueba(
      'la fila de atrás muestra la cuenta nueva, ámbar, «Todavía sin respaldo en esta cuenta»',
      (tester) async {
        await _montar(tester, drive, antes: _porConfirmar(drive));
        await _verFila(tester);

        expect(find.descendant(of: _fila, matching: find.text(_nueva)), findsOneWidget);
        expect(
          find.descendant(of: _fila, matching: find.text('Todavía sin respaldo en esta cuenta')),
          findsOneWidget,
        );
        expect(find.text('Cuenta Drive'), findsOneWidget);
      },
    );

    prueba('sin último respaldo, la hoja lo dice con el texto de la fila y no inventa una fecha', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);

      expect(_dentro(_hojaOtra, 'Todavía no hubo un respaldo'), findsOneWidget);
    });

    prueba('Con la misma cuenta de siempre NO sale la hoja: es la conexión de siempre', (
      tester,
    ) async {
      await _montar(
        tester,
        drive,
        antes: (u) async {
          await drive.repo.conectar(u);
          await drive.repo.marcarPermisoRevocado(u);
        },
      );
      primero.llamadas = 0;
      await _tocarFila(tester);
      await _tocar(tester, _conectar);

      expect(_hojaOtra, findsNothing);
      expect(_snackConectado, findsOneWidget);
      expect(primero.llamadas, 1);
    });
  });

  group('16E·02 Seguir con la cuenta nueva: qué pasa', () {
    prueba('«Seguir con la cuenta nueva» pide confirmar con lo que va a pasar', (tester) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      await _tocar(tester, _seguir);

      expect(_hojaSeguir, findsOneWidget);
      expect(_dentro(_hojaSeguir, '¿Seguir con la cuenta nueva?'), findsOneWidget);
      expect(
        _dentro(
          _hojaSeguir,
          'Desde esta noche el respaldo se guarda en $_nueva. El anterior queda en $_anterior: no '
          'se borra, pero deja de actualizarse.',
        ),
        findsOneWidget,
      );
      expect(_dentro(_hojaSeguir, 'Seguir con la cuenta nueva'), findsOneWidget);
      expect(_dentro(_hojaSeguir, 'Volver a la anterior'), findsOneWidget);
      expect(primero.llamadas, 1, reason: 'solo el de la primera conexión; aún no se eligió');
    });

    prueba('el atrás del sistema en la confirmación vuelve a la hoja anterior, sin elegir', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      await _tocar(tester, _seguir);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_hojaSeguir, findsNothing);
      expect(_hojaOtra, findsOneWidget);
    });

    prueba('confirmar: la cuenta nueva es la del respaldo, hace el primer respaldo y lo avisa', (
      tester,
    ) async {
      final c = await _montar(tester, drive, antes: _porConfirmar(drive));
      primero.llamadas = 0;
      await _tocarFila(tester);
      await _tocar(tester, _seguir);
      await _tocar(tester, _confirmarSeguir);

      expect(_hojaSeguir, findsNothing);
      expect(_hojaOtra, findsNothing);
      expect(primero.llamadas, 1);
      expect(find.text('Listo. Hicimos el primer respaldo en tu Drive.'), findsOneWidget);
      final estado = c.read(estadoRespaldoDriveProvider).value;
      expect(estado, isA<DriveConectada>());
      expect((estado! as DriveConectada).email, _nueva);
      expect(find.descendant(of: _fila, matching: find.text(_nueva)), findsOneWidget);
      expect(find.text('Todavía sin respaldo en esta cuenta'), findsNothing);
    });

    prueba('si el primer respaldo no salió, el aviso dice la verdad: el de la noche', (
      tester,
    ) async {
      primero.resultado = false;
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      await _tocar(tester, _seguir);
      await _tocar(tester, _confirmarSeguir);

      expect(find.text('Backup configurado. Próximo backup nocturno.'), findsOneWidget);
    });

    prueba(
      '«Volver a la anterior» de la confirmación hace lo mismo que «Volver a la cuenta anterior»',
      (tester) async {
        await _montar(tester, drive, antes: _porConfirmar(drive));
        drive.google.cuenta = cuentaDeAna;
        await _tocarFila(tester);
        await _tocar(tester, _seguir);
        await _tocar(tester, _confirmarVolver);

        expect(_hojaSeguir, findsNothing);
        expect(find.text('Listo. Tu respaldo sigue en $_anterior.'), findsOneWidget);
      },
    );

    prueba('doble toque en «Seguir con la cuenta nueva»: una sola confirmación', (tester) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      primero.llamadas = 0;
      await _tocarFila(tester);
      await _tocar(tester, _seguir);

      await tester.tap(_confirmarSeguir);
      await tester.tap(_confirmarSeguir, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(primero.llamadas, 1);
      expect(_snackConectado, findsOneWidget);
    });

    prueba(
      'falla a mitad (el almacén no deja anotar): avisa, sigue por confirmar y se puede reintentar',
      (tester) async {
        final c = await _montar(tester, drive, antes: _porConfirmar(drive));
        await _tocarFila(tester);
        await _tocar(tester, _seguir);

        drive.almacen.alEscribir = true;
        await _tocar(tester, _confirmarSeguir);

        expect(_hojaSeguir, findsOneWidget, reason: 'queda abierta con el aviso');
        expect(_error, findsOneWidget);
        expect(
          find.descendant(
            of: _error,
            matching: find.text('No pudimos conectar tu Drive. Probá de nuevo.'),
          ),
          findsOneWidget,
          reason: 'se dice lo de siempre, no el aviso del almacén que habla de reinstalar la app',
        );
        expect(
          tester.widget<FilledButton>(_confirmarSeguir).onPressed,
          isNotNull,
          reason: 'no queda trabado',
        );
        expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveCuentaPorConfirmar>());

        drive.almacen.alEscribir = false;
        await _tocar(tester, _confirmarSeguir);
        expect(_hojaSeguir, findsNothing);
        expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveConectada>());
      },
    );
  });

  group('16E·03 Volvió a la anterior (éxito)', () {
    prueba(
      '«Volver a la cuenta anterior» abre Google de nuevo y deja el respaldo en la de siempre',
      (tester) async {
        final c = await _montar(tester, drive, antes: _porConfirmar(drive));
        primero.llamadas = 0;
        final conexiones = drive.google.conexiones;
        drive.google.cuenta = cuentaDeAna;
        await _tocarFila(tester);
        await _tocar(tester, _volver);

        expect(drive.google.conexiones, conexiones + 1);
        expect(_hojaOtra, findsNothing);
        expect(find.text('Listo. Tu respaldo sigue en $_anterior.'), findsOneWidget);
        expect(_snackVolvio, findsOneWidget);
        final estado = c.read(estadoRespaldoDriveProvider).value;
        expect(estado, isA<DriveConectada>());
        expect((estado! as DriveConectada).email, _anterior);
        expect(primero.llamadas, 0, reason: 'su respaldo sigue ahí: no se sube otro');
        expect(find.descendant(of: _fila, matching: find.text(_anterior)), findsOneWidget);
      },
    );

    prueba('desde Reconectar: elige otra, vuelve a la de siempre y todo queda como antes', (
      tester,
    ) async {
      final c = await _montar(tester, drive, antes: _revocadaYOtraCuenta(drive));
      await _tocarFila(tester);
      await _tocar(tester, _conectar);
      expect(_hojaOtra, findsOneWidget);

      drive.google.cuenta = cuentaDeAna;
      await _tocar(tester, _volver);

      expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveConectada>());
      expect(_snackVolvio, findsOneWidget);
    });
  });

  group('16E·04 Sin conexión', () {
    prueba('el aviso lo dice, «Volver» espera a la conexión y «Seguir» sigue disponible', (
      tester,
    ) async {
      await _montar(tester, drive, conexion: TipoConexion.sinConexion, antes: _porConfirmar(drive));
      await _tocarFila(tester);

      expect(_sinConexion, findsOneWidget);
      expect(_dentro(_hojaOtra, 'Necesitás conexión para cambiar de cuenta.'), findsOneWidget);
      expect(tester.widget<FilledButton>(_volver).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(_seguir).onPressed, isNotNull);
    });

    prueba('con la conexión caída en la confirmación, «Volver a la anterior» también espera', (
      tester,
    ) async {
      await _montar(tester, drive, conexion: TipoConexion.sinConexion, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      await _tocar(tester, _seguir);

      expect(tester.widget<OutlinedButton>(_confirmarVolver).onPressed, isNull);
      expect(tester.widget<FilledButton>(_confirmarSeguir).onPressed, isNotNull);
    });

    prueba('se cae la red en pleno intento: el aviso es de sin conexión y se puede reintentar', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      drive.google.errorAlConectar = const SocketException('sin red');
      await _tocar(tester, _volver);

      expect(_sinConexion, findsOneWidget);
      expect(tester.widget<FilledButton>(_volver).onPressed, isNotNull);

      drive.google.errorAlConectar = null;
      drive.google.cuenta = cuentaDeAna;
      await _tocar(tester, _volver);
      expect(_hojaOtra, findsNothing);
      expect(_snackVolvio, findsOneWidget);
    });
  });

  group('Casos límite', () {
    prueba('doble toque en «Volver a la cuenta anterior»: Google se abre una sola vez', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      final conexiones = drive.google.conexiones;
      final compuerta = Completer<void>();
      drive.google.compuertaConectar = compuerta;
      drive.google.cuenta = cuentaDeAna;
      await _tocarFila(tester);

      await tester.tap(_volver);
      await tester.pump();
      expect(tester.widget<FilledButton>(_volver).onPressed, isNull, reason: 'ocupado');
      await tester.tap(_volver, warnIfMissed: false);
      await tester.pump();
      compuerta.complete();
      await tester.pumpAndSettle();

      expect(drive.google.conexiones, conexiones + 1);
      expect(_snackVolvio, findsOneWidget);
    });

    prueba('mientras Google está abierto la hoja no se cierra ni se puede elegir lo otro', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      final compuerta = Completer<void>();
      drive.google.compuertaConectar = compuerta;
      drive.google.cuenta = cuentaDeAna;
      await _tocarFila(tester);
      await tester.tap(_volver);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_hojaOtra, findsOneWidget, reason: 'el atrás no la cierra mientras trabaja');
      expect(tester.widget<OutlinedButton>(_seguir).onPressed, isNull);

      compuerta.complete();
      await tester.pumpAndSettle();
      expect(_hojaOtra, findsNothing);
    });

    prueba('falla a mitad al volver: avisa, el botón se habilita y el respaldo sigue frenado', (
      tester,
    ) async {
      final c = await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      drive.google.errorAlConectar = StateError('Google falló');
      await _tocar(tester, _volver);

      expect(_error, findsOneWidget);
      expect(
        find.descendant(
          of: _error,
          matching: find.text('No pudimos conectar tu Drive. Probá de nuevo.'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_volver).onPressed, isNotNull);
      expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveCuentaPorConfirmar>());
    });

    prueba('cerrar la pantalla de Google: la hoja sigue como estaba, sin aviso de error', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await _tocar(tester, _volver);

      expect(_hojaOtra, findsOneWidget);
      expect(_error, findsNothing);
      expect(_sinConexion, findsNothing);
      expect(tester.widget<FilledButton>(_volver).onPressed, isNotNull);
    });

    prueba(
      'elige una tercera cuenta: la hoja sigue con la que eligió ahora y la anterior no cambia',
      (tester) async {
        await _montar(tester, drive, antes: _porConfirmar(drive));
        await _tocarFila(tester);
        drive.google.cuenta = _tercera;
        await _tocar(tester, _volver);

        expect(_hojaOtra, findsOneWidget);
        expect(_dentro(_hojaOtra, 'ana.trabajo@gmail.com'), findsOneWidget);
        expect(_dentro(_hojaOtra, _anterior), findsOneWidget);
        expect(
          _dentro(
            _hojaOtra,
            'Tu respaldo anterior quedó en $_anterior. Ahora te conectaste con ana.trabajo@gmail.com.',
          ),
          findsOneWidget,
        );
      },
    );

    prueba('cerrar sin elegir y volver a entrar: la fila sigue pendiente y reabre la hoja', (
      tester,
    ) async {
      final c = await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_hojaOtra, findsNothing);
      expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveCuentaPorConfirmar>());
      expect(find.text('Todavía sin respaldo en esta cuenta'), findsOneWidget);

      await _tocarFila(tester);
      expect(_hojaOtra, findsOneWidget);

      // Sale de Configuración y vuelve a entrar: sigue igual.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inicio_configuracion')));
      await tester.pumpAndSettle();
      await _tocarFila(tester);
      expect(_hojaOtra, findsOneWidget);
    });

    prueba('doble toque en la fila pendiente: una sola hoja', (tester) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _verFila(tester);

      await tester.tap(_fila);
      await tester.tap(_fila, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_hojaOtra, findsOneWidget);
    });

    prueba('con otra cuenta por confirmar, la fila avisa al lector de pantalla qué abre', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _verFila(tester);

      final pista = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.hint == 'Abre las opciones para elegir con qué cuenta seguir',
      );
      expect(pista, findsOneWidget);
    });

    for (final pantalla in [const Size(360, 640), const Size(412, 915)]) {
      prueba(
        'letra al 200 % en ${pantalla.width.toInt()}×${pantalla.height.toInt()}: la hoja se desplaza, '
        'correos largos enteros y los dos botones a mano',
        (tester) async {
          await _montar(
            tester,
            drive,
            pantalla: pantalla,
            escalaTexto: 2,
            antes: (u) async {
              await drive.repo.conectar(u);
              drive.google.cuenta = const CuentaGoogle(
                id: 'g-999',
                email: 'una.cuenta.con.un.correo.bastante.largo.de.verdad@gmail.com',
              );
              await drive.repo.conectar(u);
            },
          );
          await _tocarFila(tester);

          expect(tester.takeException(), isNull, reason: 'overflow o error de render');
          expect(_hojaOtra, findsOneWidget);
          await tester.ensureVisible(_volver);
          await tester.ensureVisible(_seguir);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(
            find.text('una.cuenta.con.un.correo.bastante.largo.de.verdad@gmail.com'),
            findsWidgets,
            reason: 'el correo se lee entero, sin «…»',
          );
          for (final b in [_volver, _seguir]) {
            expect(tester.getSize(b).height, greaterThanOrEqualTo(48));
          }
          await tester.tap(_seguir);
          await tester.pumpAndSettle();
          expect(_hojaSeguir, findsOneWidget);
          await tester.ensureVisible(_confirmarSeguir);
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    prueba('accesibilidad de la hoja: objetivos de toque y etiquetas', (tester) async {
      await _montar(tester, drive, antes: _porConfirmar(drive));
      await _tocarFila(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
