// HU-SYNC-004 — Autorizar Google Drive, desde la fila «Cuenta Drive» de Configuración (vista 16,
// artboards 16D·01 a 16D·10). Un test por artboard y por escenario de la HU, con el texto literal,
// más los casos límite: doble toque, falla a mitad, volver y reentrar, texto grande.
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
import 'package:colportores_mobile/features/respaldo/presentation/textos_respaldo_drive.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/respaldo_drive_falsos.dart';

/// Monta la app con sesión iniciada y abre Configuración. [antes] corre con la sesión ya iniciada y
/// antes de abrir la pantalla (para dejar Drive en el estado que pide el test).
Future<ProviderContainer> _montar(
  WidgetTester tester,
  RespaldoDriveArmado drive, {
  TipoConexion? conexion,
  Future<void> Function(String usuarioId)? antes,
  Size pantalla = const Size(2400, 3000),
  double? escalaTexto,
  bool asentar = true,
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
  if (asentar) {
    await tester.pumpAndSettle();
  } else {
    // Hay un indicador de progreso girando: `pumpAndSettle` no terminaría.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return container;
}

Finder get _fila => find.byKey(const Key('configuracion_drive_fila'));
Finder get _hojaConectar => find.byKey(const Key('drive_hoja_conectar'));
Finder get _hojaDesconectar => find.byKey(const Key('drive_hoja_desconectar'));
Finder get _conectar => find.byKey(const Key('drive_conectar'));
Finder get _ahoraNo => find.byKey(const Key('drive_ahora_no'));
Finder get _desconectar => find.byKey(const Key('drive_desconectar'));
Finder get _avisoRevocado => find.byKey(const Key('configuracion_drive_aviso_revocado'));
Finder get _avisoCancelado => find.byKey(const Key('configuracion_drive_aviso_cancelado'));

Future<void> _verFila(WidgetTester tester) async {
  await tester.scrollUntilVisible(_fila, 200, scrollable: find.byType(Scrollable).first);
  // Al borde de la pantalla la barra de abajo tapa la fila: se la lleva hacia el medio.
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

Finder _dentro(Finder hoja, String texto) => find.descendant(of: hoja, matching: find.text(texto));

Future<void> Function(String) _conectado(RespaldoDriveArmado a) =>
    (u) async => a.repo.conectar(u).then((_) {});

void main() {
  late RespaldoDriveArmado drive;

  // El armado se crea dentro del test: el `setUp` corre fuera de la zona del reloj falso y las
  // operaciones encoladas del repositorio no avanzarían con `pump`.
  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      drive = RespaldoDriveArmado();
      await cuerpo(tester);
    });
  }

  group('16D·01 Sin conectar', () {
    prueba('la sección «Respaldo» con «Cuenta Drive» y el aviso de que no hay respaldo', (
      tester,
    ) async {
      await _montar(tester, drive);
      await _verFila(tester);

      expect(find.text('Respaldo'), findsOneWidget);
      expect(find.text('Cuenta Drive'), findsOneWidget);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
      expect(find.descendant(of: _fila, matching: find.text('Conectar')), findsOneWidget);
      expect(_avisoRevocado, findsNothing);
      expect(_avisoCancelado, findsNothing);
    });

    prueba('queda entre Mapas y Privacidad y datos', (tester) async {
      await _montar(tester, drive);
      await _verFila(tester);
      final respaldo = tester.getTopLeft(find.text('Respaldo')).dy;
      final privacidad = tester.getTopLeft(find.text('Privacidad y datos')).dy;
      expect(respaldo, lessThan(privacidad));
    });
  });

  group('16D·02 Antes de conectar', () {
    prueba('Escenario: la UI muestra, antes del consentimiento, que los archivos van cifrados', (
      tester,
    ) async {
      await _montar(tester, drive);
      await _tocarFila(tester);

      expect(_hojaConectar, findsOneWidget);
      expect(_dentro(_hojaConectar, 'Respaldo en tu Google Drive'), findsOneWidget);
      expect(
        _dentro(
          _hojaConectar,
          'Guardamos una copia de tus datos en una carpeta oculta de tu Drive. Los archivos van '
          'cifrados, Google no los puede leer, y solo esta app los puede acceder.',
        ),
        findsOneWidget,
      );
      expect(
        _dentro(_hojaConectar, 'Se respalda cada noche. Podés desconectarlo cuando quieras.'),
        findsOneWidget,
      );
      expect(_dentro(_hojaConectar, 'Conectar con Google'), findsOneWidget);
      expect(_dentro(_hojaConectar, 'Ahora no'), findsOneWidget);
      expect(drive.google.conexiones, 0, reason: 'Google no se abre hasta que la persona lo pide');
    });

    prueba('«Ahora no» cierra la hoja sin conectar ni avisar', (tester) async {
      await _montar(tester, drive);
      await _tocarFila(tester);
      await _tocar(tester, _ahoraNo);

      expect(_hojaConectar, findsNothing);
      expect(drive.google.conexiones, 0);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
      expect(_avisoCancelado, findsNothing);
    });
  });

  group('16D·03 Conectando y 16D·04 Conectada', () {
    prueba('Escenario: autorización exitosa — «Conectando…», después la fila con la cuenta y '
        'el aviso de la HU', (tester) async {
      final compuerta = Completer<void>();
      drive.google.compuertaConectar = compuerta;
      await _montar(tester, drive);
      await _tocarFila(tester);

      await tester.tap(_conectar);
      await tester.pump();
      expect(_dentro(_hojaConectar, 'Conectando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(_conectar).onPressed, isNull, reason: 'ocupado');
      expect(_ahoraNo, findsNothing, reason: 'mientras conecta no hay salida a medias');

      compuerta.complete();
      await tester.pumpAndSettle();

      expect(_hojaConectar, findsNothing);
      expect(find.text('Backup configurado. Próximo backup nocturno.'), findsOneWidget);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
      expect(find.text('Todavía no hubo un respaldo'), findsOneWidget);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsNothing);
    });

    prueba('con el primer respaldo hecho, el aviso es el del canvas', (tester) async {
      final primero = PrimerRespaldoFalso();
      final conPrimero = RespaldoDriveArmado(primerRespaldo: primero);
      await _montar(tester, conPrimero);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();

      expect(find.text('Listo. Hicimos el primer respaldo en tu Drive.'), findsOneWidget);
      expect(primero.llamadas, 1);
    });

    prueba('doble toque en «Conectar con Google»: Google se abre una sola vez', (tester) async {
      final compuerta = Completer<void>();
      drive.google.compuertaConectar = compuerta;
      await _montar(tester, drive);
      await _tocarFila(tester);

      await tester.tap(_conectar);
      await tester.tap(_conectar, warnIfMissed: false);
      await tester.pump();
      compuerta.complete();
      await tester.pumpAndSettle();

      expect(drive.google.conexiones, 1);
    });

    prueba('el botón atrás no cierra la hoja mientras está en la pantalla de Google', (
      tester,
    ) async {
      final compuerta = Completer<void>();
      drive.google.compuertaConectar = compuerta;
      await _montar(tester, drive);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_hojaConectar, findsOneWidget);

      compuerta.complete();
      await tester.pumpAndSettle();
    });

    prueba('«Último respaldo» dice hoy, ayer o la fecha', (tester) async {
      await _montar(tester, drive, antes: _conectado(drive));
      await _verFila(tester);
      // La fecha viene del motor de sync, que en este armado no hay: el texto de «todavía no».
      expect(find.byKey(const Key('configuracion_drive_ultimo')), findsOneWidget);

      final ahora = DateTime(2026, 10, 28, 12);
      expect(
        TextosRespaldoDrive.ultimoRespaldo(DateTime(2026, 10, 28, 3, 10), ahora),
        'Último respaldo: hoy 03:10',
      );
      expect(
        TextosRespaldoDrive.ultimoRespaldo(DateTime(2026, 10, 27, 23, 5), ahora),
        'Último respaldo: ayer 23:05',
      );
      expect(
        TextosRespaldoDrive.ultimoRespaldo(DateTime(2026, 10, 3, 3, 10), ahora),
        'Último respaldo: el 03/10 03:10',
      );
    });
  });

  group('16D·07 Canceló en Google', () {
    prueba('Escenario: la persona cierra la pantalla de Google — «No conectamos tu Drive»', (
      tester,
    ) async {
      drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await _montar(tester, drive);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();

      expect(_hojaConectar, findsNothing);
      expect(find.text('No conectamos tu Drive. Podés hacerlo cuando quieras.'), findsOneWidget);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
      expect(drive.guardado, isNull);
    });

    prueba('volver a intentar saca el aviso y, si sale bien, conecta', (tester) async {
      drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await _montar(tester, drive);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();
      expect(_avisoCancelado, findsOneWidget);

      drive.google.errorAlConectar = null;
      await _tocarFila(tester);
      expect(_avisoCancelado, findsNothing, reason: 'un intento nuevo borra el aviso viejo');
      await tester.tap(_conectar);
      await tester.pumpAndSettle();

      expect(_avisoCancelado, findsNothing);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
    });
  });

  group('16D·08 Sin conexión', () {
    prueba('la hoja avisa que hace falta conexión y el botón espera', (tester) async {
      await _montar(tester, drive, conexion: TipoConexion.sinConexion);
      await _tocarFila(tester);

      expect(
        _dentro(_hojaConectar, 'Necesitás conexión para conectar Google Drive.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_conectar).onPressed, isNull);
      expect(_ahoraNo, findsOneWidget);
      expect(drive.google.conexiones, 0);
    });

    prueba('si la red falla en pleno intento, lo dice y se puede reintentar', (tester) async {
      // Con red según el teléfono, pero la conexión se cae durante el intento.
      await _montar(tester, drive);
      await _tocarFila(tester);
      drive.google.errorAlConectar = const SocketException('sin red');
      await tester.tap(_conectar);
      await tester.pumpAndSettle();

      expect(
        _dentro(_hojaConectar, 'Necesitás conexión para conectar Google Drive.'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(_conectar).onPressed, isNotNull);
    });
  });

  group('16D·09 Error', () {
    prueba('«No pudimos conectar tu Drive» con «Reintentar», que ya no queda ocupado', (
      tester,
    ) async {
      drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);
      await _montar(tester, drive);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();

      expect(_hojaConectar, findsOneWidget);
      expect(
        _dentro(_hojaConectar, 'No pudimos conectar tu Drive. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(_dentro(_hojaConectar, 'Reintentar'), findsOneWidget);
      expect(_ahoraNo, findsOneWidget);
      expect(
        tester.widget<FilledButton>(_conectar).onPressed,
        isNotNull,
        reason: 'no queda trabado',
      );

      drive.google.errorAlConectar = null;
      await tester.tap(_conectar);
      await tester.pumpAndSettle();
      expect(_hojaConectar, findsNothing);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
      expect(drive.google.conexiones, 2);
    });

    prueba('si la persona no dejó marcado el permiso de Drive, se lo dice', (tester) async {
      drive.google.errorAlConectar = const PermisoDriveNoConcedido();
      await _montar(tester, drive);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();

      expect(
        _dentro(
          _hojaConectar,
          'Para guardar tu respaldo necesitamos el permiso de Drive. Probá de nuevo y dejá '
          'marcado el permiso de Drive.',
        ),
        findsOneWidget,
      );
      expect(drive.guardado, isNull);
    });

    prueba('sin las credenciales de Google en la compilación: error, nunca una conexión falsa', (
      tester,
    ) async {
      // El caso de la demo y de CI: el repositorio por defecto corre con Google sin configurar.
      final container = await _montarSinDrive(tester);
      addTearDown(container.dispose);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();
      expect(
        _dentro(_hojaConectar, 'No pudimos conectar tu Drive. Probá de nuevo.'),
        findsOneWidget,
      );
    });
  });

  group('16D·05 Desconectar', () {
    prueba('Escenario: revocar desde Configuración — dice que las copias no se borran', (
      tester,
    ) async {
      await _montar(tester, drive, antes: _conectado(drive));
      await _tocarFila(tester);

      expect(_dentro(_hojaDesconectar, '¿Desconectar Google Drive?'), findsOneWidget);
      expect(
        _dentro(
          _hojaDesconectar,
          'Los respaldos dejan de hacerse. Las copias que ya están en tu Drive no se borran: si '
          'querés, las borrás desde Drive.',
        ),
        findsOneWidget,
      );

      await tester.tap(_desconectar);
      await tester.pumpAndSettle();

      expect(_hojaDesconectar, findsNothing);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
      expect(drive.google.desconexiones, 1);
      expect(drive.guardado, isNull);
    });

    prueba('«Cancelar» no desconecta', (tester) async {
      await _montar(tester, drive, antes: _conectado(drive));
      await _tocarFila(tester);
      await _tocar(tester, find.byKey(const Key('drive_desconectar_cancelar')));

      expect(_hojaDesconectar, findsNothing);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
      expect(drive.google.desconexiones, 0);
    });

    prueba('falla a mitad: avisa, la cuenta sigue y el botón vuelve a habilitarse', (tester) async {
      await _montar(tester, drive, antes: _conectado(drive));
      await _tocarFila(tester);
      drive.almacen.alBorrar = true;
      await tester.tap(_desconectar);
      await tester.pumpAndSettle();

      expect(_hojaDesconectar, findsOneWidget);
      expect(
        find.byKey(const Key('drive_hoja_error_desconectar')),
        findsOneWidget,
        reason: 'no pudimos desconectar tu Drive',
      );
      expect(tester.widget<FilledButton>(_desconectar).onPressed, isNotNull);

      drive.almacen.alBorrar = false;
      await tester.tap(_desconectar);
      await tester.pumpAndSettle();
      expect(_hojaDesconectar, findsNothing);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
    });

    prueba('doble toque en «Desconectar»: se desconecta una sola vez', (tester) async {
      await _montar(tester, drive, antes: _conectado(drive));
      await _tocarFila(tester);
      await tester.tap(_desconectar);
      await tester.tap(_desconectar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(drive.google.desconexiones, 1);
    });

    prueba('después de desconectar se puede volver a conectar', (tester) async {
      await _montar(tester, drive, antes: _conectado(drive));
      await _tocarFila(tester);
      await tester.tap(_desconectar);
      await tester.pumpAndSettle();

      await _tocarFila(tester);
      expect(
        _hojaConectar,
        findsOneWidget,
        reason: 'dos acciones seguidas: la fila ya es «Conectar»',
      );
      await tester.tap(_conectar);
      await tester.pumpAndSettle();
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
    });
  });

  group('16D·06 Permiso revocado', () {
    prueba('Escenario Edge: revocado desde Google — banner «Reconectar» y la fila en rojo', (
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

      expect(
        find.text(
          'Google ya no nos deja guardar tu respaldo. Volvé a conectar tu Drive para no perder datos.',
        ),
        findsOneWidget,
      );
      await _verFila(tester);
      expect(find.text('Sin permiso · los respaldos están frenados'), findsOneWidget);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
      expect(find.descendant(of: _fila, matching: find.text('Reconectar')), findsOneWidget);
    });

    prueba('«Reconectar» del banner abre la hoja y deja la cuenta conectada', (tester) async {
      await _montar(
        tester,
        drive,
        antes: (u) async {
          await drive.repo.conectar(u);
          await drive.repo.marcarPermisoRevocado(u);
        },
      );
      await _tocar(tester, find.byKey(const Key('aviso_drive_accion')));
      expect(_hojaConectar, findsOneWidget);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();

      expect(_avisoRevocado, findsNothing, reason: 'el banner se va cuando ya no es verdad');
      await _verFila(tester);
      expect(find.text('Sin permiso · los respaldos están frenados'), findsNothing);
    });

    prueba('si Google ya no tiene el permiso, la fila lo dice al abrir Configuración', (
      tester,
    ) async {
      drive.google.token = null;
      await _montar(tester, drive, antes: _conectado(drive));
      await tester.pumpAndSettle();

      expect(_avisoRevocado, findsOneWidget);
    });
  });

  group('16D·10 Drive sin espacio', () {
    prueba('«Tu Drive está lleno · el respaldo no se guardó», y se puede abrir', (tester) async {
      await _montar(
        tester,
        drive,
        antes: (u) async {
          await drive.repo.conectar(u);
          await drive.repo.marcarSinEspacio(u);
        },
      );
      await _verFila(tester);

      expect(find.text('Tu Drive está lleno · el respaldo no se guardó'), findsOneWidget);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
      expect(_avisoRevocado, findsNothing, reason: 'el permiso sigue vigente: nada que reconectar');

      await _tocarFila(tester);
      expect(_hojaDesconectar, findsOneWidget);
    });
  });

  group('Estados de carga y de error', () {
    prueba('cargando: «Revisando tu respaldo…» y la fila no responde', (tester) async {
      final compuerta = Completer<void>();
      drive.almacen.compuertaLeer = compuerta;
      await _montar(tester, drive, asentar: false);
      await tester.scrollUntilVisible(
        find.text('Revisando tu respaldo…'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Revisando tu respaldo…'), findsOneWidget);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsNothing);
      await tester.tap(_fila, warnIfMissed: false);
      await tester.pump();
      expect(_hojaConectar, findsNothing, reason: 'mientras revisa, la fila no responde');

      compuerta.complete();
      await tester.pumpAndSettle();
      expect(find.text('Revisando tu respaldo…'), findsNothing);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
    });

    prueba('no se pudo leer: lo dice y «Reintentar» lo vuelve a leer', (tester) async {
      drive.almacen.alLeer = true;
      await _montar(tester, drive);
      await _verFila(tester);
      expect(find.text('No pudimos ver el estado de tu respaldo.'), findsOneWidget);
      expect(find.descendant(of: _fila, matching: find.text('Reintentar')), findsOneWidget);

      drive.almacen.alLeer = false;
      await tester.tap(_fila);
      await tester.pumpAndSettle();

      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
    });
  });

  group('Casos límite', () {
    prueba('volver atrás y entrar de nuevo a Configuración conserva el estado', (tester) async {
      await _montar(tester, drive, antes: _conectado(drive));
      await _verFila(tester);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inicio_configuracion')));
      await tester.pumpAndSettle();
      await _verFila(tester);

      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
    });

    prueba('el aviso «No conectamos tu Drive» no sobrevive a salir de Configuración', (
      tester,
    ) async {
      drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await _montar(tester, drive);
      await _tocarFila(tester);
      await tester.tap(_conectar);
      await tester.pumpAndSettle();
      expect(_avisoCancelado, findsOneWidget);

      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inicio_configuracion')));
      await tester.pumpAndSettle();
      expect(_avisoCancelado, findsNothing);
    });

    prueba('un correo larguísimo se lee entero a 360 px y texto 2.0, sin desbordar', (
      tester,
    ) async {
      drive.google.cuenta = const CuentaGoogle(
        id: 'g-1',
        email:
            'maria.de.los.angeles.fernandez.de.la.vega.y.rodriguez.silva@correo-institucional-muy-largo.edu.uy',
      );
      await _montar(
        tester,
        drive,
        pantalla: const Size(360, 740),
        escalaTexto: 2.0,
        antes: _conectado(drive),
      );
      await _verFila(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('configuracion_drive_correo')), findsOneWidget);
    });

    prueba('a 360 px y texto 2.0 las hojas no desbordan y los botones miden al menos 48', (
      tester,
    ) async {
      await _montar(tester, drive, pantalla: const Size(360, 740), escalaTexto: 2.0);
      await _tocarFila(tester);
      expect(tester.takeException(), isNull);
      for (final k in ['drive_conectar', 'drive_ahora_no']) {
        await tester.ensureVisible(find.byKey(Key(k)));
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(48));
      }

      drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);
      await _tocar(tester, _conectar);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('drive_hoja_error')), findsOneWidget);
    });

    prueba('la hoja de desconectar a 360 px y texto 2.0 no desborda', (tester) async {
      await _montar(
        tester,
        drive,
        pantalla: const Size(360, 740),
        escalaTexto: 2.0,
        antes: _conectado(drive),
      );
      await _tocarFila(tester);
      expect(tester.takeException(), isNull);
      expect(_hojaDesconectar, findsOneWidget);
    });
  });

  group('Accesibilidad', () {
    prueba('la sección y las hojas cumplen las guías de tamaño y de rótulos', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, drive, antes: _conectado(drive));
      await _verFila(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await _tocarFila(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    prueba('el banner de permiso revocado tiene la acción «Reconectar» de al menos 48', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        drive,
        antes: (u) async {
          await drive.repo.conectar(u);
          await drive.repo.marcarPermisoRevocado(u);
        },
      );
      expect(
        tester.getSize(find.byKey(const Key('aviso_drive_accion'))).height,
        greaterThanOrEqualTo(48),
      );
      handle.dispose();
    });
  });

  test('el estado «sin permiso» y «sin espacio» no cuentan como respaldando', () {
    expect(const DriveConectada(email: 'a', cuentaId: 'b').respaldaAhora, isTrue);
    expect(const DrivePermisoRevocado(email: 'a', cuentaId: 'b').respaldaAhora, isFalse);
    expect(const DriveSinEspacio(email: 'a', cuentaId: 'b').respaldaAhora, isFalse);
    expect(const DriveSinConectar().respaldaAhora, isFalse);
  });
}

/// La app con el repositorio por defecto (Google sin configurar), sin el armado de pruebas.
Future<ProviderContainer> _montarSinDrive(WidgetTester tester) async {
  tester.view.physicalSize = const Size(2400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
  );
  await container.read(sesionProvider.future);
  await container
      .read(sesionProvider.notifier)
      .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('inicio_configuracion')));
  await tester.pumpAndSettle();
  return container;
}
