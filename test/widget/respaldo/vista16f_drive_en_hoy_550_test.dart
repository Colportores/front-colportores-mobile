// #550 (HU-SYNC-004) — Vista 16, 16F·01 a 16F·04: la franja del Drive en Hoy. Ana revoca el permiso sin
// querer o se le llena el Drive, y la copia nocturna deja de hacerse: Hoy se lo dice y la lleva a
// Configuración mientras el problema siga; puede ocultarla hasta mañana. Un test por artboard con el
// texto literal del canvas, más los casos límite: doble toque, falla a mitad, volver y reentrar,
// teclado abierto, otros avisos, medianoche y letra al 200 %.
import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart'
    show CuentaGoogle;
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/db_local_repository_en_memoria.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono, volverALaApp;
import '../../helpers/respaldo_drive_falsos.dart';

const _textoRevocado =
    'Google ya no nos deja guardar tu respaldo. Lo que cargues desde ahora no tiene copia.';
const _textoLleno = 'Tu Drive está lleno. El respaldo de anoche no se guardó.';

Finder get _franjaRevocada => find.byKey(const Key('aviso_drive_en_hoy_permisoRevocado'));
Finder get _franjaLlena => find.byKey(const Key('aviso_drive_en_hoy_sinEspacio'));
Finder get _ocultar => find.byKey(const Key('aviso_drive_accion_secundaria'));
Finder get _accion => find.byKey(const Key('aviso_drive_accion'));
Finder get _engranaje => find.byKey(const Key('inicio_configuracion'));
Finder get _marca => find.byKey(const Key('inicio_configuracion_marca'));
Finder get _snackOculto => find.byKey(const Key('aviso_drive_oculto'));
Finder get _snackNoOculto => find.byKey(const Key('aviso_drive_no_oculto'));
Finder get _franja => find.byKey(const Key('inicio_franja_avisos'));
Finder get _filaDrive => find.byKey(const Key('configuracion_drive_fila'));

Future<void> _revocado(RespaldoDriveArmado a, String u) async {
  await a.repo.conectar(u);
  await a.repo.marcarPermisoRevocado(u);
}

Future<void> _lleno(RespaldoDriveArmado a, String u) async {
  await a.repo.conectar(u);
  await a.repo.marcarSinEspacio(u);
}

void main() {
  late RespaldoDriveArmado drive;
  var ahora = DateTime(2026, 11, 20, 22, 30);

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    Future<void> Function(RespaldoDriveArmado, String)? problema,
    Size pantalla = const Size(390, 844),
    double? escalaTexto,
    Telefono? telefono,
  }) async {
    tester.view.physicalSize = pantalla;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => tester.view.resetViewInsets());
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
        relojRespaldoDriveProvider.overrideWithValue(() => ahora),
        if (telefono != null) ...telefono.overrides,
      ],
    );
    addTearDown(container.dispose);
    await container.read(sesionProvider.future);
    await container
        .read(sesionProvider.notifier)
        .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
    final usuarioId = container.read(sesionProvider).value!.usuarioId;
    if (problema != null) await problema(drive, usuarioId);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const ColportoresApp()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  void prueba(String nombre, Future<void> Function(WidgetTester tester) cuerpo) {
    testWidgets(nombre, (tester) async {
      ahora = DateTime(2026, 11, 20, 22, 30);
      drive = RespaldoDriveArmado(ahora: () => ahora);
      await cuerpo(tester);
    });
  }

  group('16F·01 Hoy: permiso revocado', () {
    prueba('la franja dice que lo que cargues no tiene copia y lleva a Configuración', (
      tester,
    ) async {
      await montar(tester, problema: _revocado);

      expect(_franjaRevocada, findsOneWidget);
      expect(find.text(_textoRevocado), findsOneWidget);
      expect(
        find.descendant(of: _franjaRevocada, matching: find.text('Reconectar en Configuración')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _franjaRevocada, matching: find.text('Ocultar hasta mañana')),
        findsOneWidget,
      );
      expect(_marca, findsNothing, reason: 'con la franja a la vista el engranaje va sin marca');
    });

    prueba(
      '«Reconectar en Configuración» abre Configuración, donde está la fila en rojo (16D·06)',
      (tester) async {
        await montar(tester, problema: _revocado);
        await tester.tap(_accion);
        await tester.pumpAndSettle();

        expect(_filaDrive, findsOneWidget);
        expect(find.text('Sin permiso · los respaldos están frenados'), findsOneWidget);
        expect(find.byKey(const Key('configuracion_drive_aviso_revocado')), findsOneWidget);
      },
    );

    prueba('doble toque en la franja: una sola Configuración', (tester) async {
      await montar(tester, problema: _revocado);

      await tester.tap(_accion);
      await tester.tap(_accion, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('configuracion_drive_fila')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('inicio_principal')),
        findsOneWidget,
        reason: 'no quedó otra encima',
      );
    });

    prueba('volver de Configuración sin resolver: la franja sigue ahí', (tester) async {
      await montar(tester, problema: _revocado);
      await tester.tap(_accion);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsOneWidget);
    });

    prueba('reconectar desde Configuración la saca de Hoy (se resolvió)', (tester) async {
      await montar(tester, problema: _revocado);
      await tester.tap(_accion);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_filaDrive);
      await tester.pump();
      await tester.tap(_filaDrive);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drive_conectar')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsNothing);
      expect(_franjaLlena, findsNothing);
      expect(_marca, findsNothing);
    });
  });

  group('16F·02 Hoy: Drive lleno', () {
    prueba('la franja ámbar dice que el respaldo de anoche no se guardó y lleva a Configuración', (
      tester,
    ) async {
      await montar(tester, problema: _lleno);

      expect(_franjaLlena, findsOneWidget);
      expect(find.text(_textoLleno), findsOneWidget);
      expect(
        find.descendant(of: _franjaLlena, matching: find.text('Ver en Configuración')),
        findsOneWidget,
      );
      expect(_franjaRevocada, findsNothing);

      await tester.tap(_accion);
      await tester.pumpAndSettle();
      expect(find.text('Tu Drive está lleno · el respaldo no se guardó'), findsOneWidget);
    });
  });

  group('Otra cuenta de Google por confirmar (decisión R7 del 23/11)', () {
    Future<void> porConfirmar(RespaldoDriveArmado a, String u) async {
      await a.repo.conectar(u);
      a.google.cuenta = const CuentaGoogle(id: 'g-200', email: 'ana.casa@gmail.com');
      await a.repo.conectar(u);
    }

    final franja = find.byKey(const Key('aviso_drive_en_hoy_cuentaPorConfirmar'));
    final hojaOtra = find.byKey(const Key('drive_hoja_otra_cuenta'));

    prueba('el respaldo frenado se avisa también en Hoy, con «Elegir cuenta»', (tester) async {
      await montar(tester, problema: porConfirmar);

      expect(franja, findsOneWidget);
      expect(
        find.text('Tu respaldo está frenado: elegí con qué cuenta de Google seguir.'),
        findsOneWidget,
      );
      expect(find.descendant(of: franja, matching: find.text('Elegir cuenta')), findsOneWidget);
      expect(
        find.descendant(of: franja, matching: find.text('Ocultar hasta mañana')),
        findsOneWidget,
      );
      expect(_marca, findsNothing);
    });

    prueba('«Elegir cuenta» abre la misma hoja de otra cuenta; doble toque, una sola', (
      tester,
    ) async {
      await montar(tester, problema: porConfirmar);

      await tester.tap(_accion);
      await tester.tap(_accion, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(hojaOtra, findsOneWidget);
      expect(find.text('Esta no es la cuenta de tu respaldo'), findsOneWidget);
    });

    prueba('cerrar la hoja sin elegir deja la franja; volver a la anterior la saca de Hoy', (
      tester,
    ) async {
      await montar(tester, problema: porConfirmar);
      await tester.tap(_accion);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(hojaOtra, findsNothing);
      expect(franja, findsOneWidget);

      drive.google.cuenta = cuentaDeAna;
      await tester.tap(_accion);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drive_otra_cuenta_volver')));
      await tester.pumpAndSettle();

      expect(franja, findsNothing);
      expect(find.text('Listo. Tu respaldo sigue en ana.gomez@gmail.com.'), findsOneWidget);
    });

    prueba('seguir con la cuenta nueva la saca de Hoy', (tester) async {
      await montar(tester, problema: porConfirmar);
      await tester.tap(_accion);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drive_otra_cuenta_seguir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drive_otra_cuenta_confirmar_seguir')));
      await tester.pumpAndSettle();

      expect(franja, findsNothing);
    });

    prueba('desconectar el Drive desde la hoja la saca de Hoy', (tester) async {
      await montar(tester, problema: porConfirmar);
      await tester.tap(_accion);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drive_otra_cuenta_desconectar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drive_desconectar')));
      await tester.pumpAndSettle();

      expect(franja, findsNothing);
      expect(hojaOtra, findsNothing);
    });

    prueba('«Ocultar hasta mañana»: se va, el engranaje lleva la marca y sale mañana', (
      tester,
    ) async {
      await montar(tester, problema: porConfirmar);
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();

      expect(franja, findsNothing);
      expect(_marca, findsOneWidget);

      ahora = DateTime(2026, 11, 21, 7, 5);
      volverALaApp(tester);
      await tester.pumpAndSettle();
      expect(franja, findsOneWidget);
    });

    prueba('con la letra al 200 % en 360×640 los botones se alcanzan', (tester) async {
      await montar(tester, problema: porConfirmar, pantalla: const Size(360, 640), escalaTexto: 2);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_accion);
      await tester.pump();
      expect(tester.getSize(_accion).height, greaterThanOrEqualTo(48));
    });
  });

  group('Sin problema no hay franja', () {
    prueba('sin Drive conectado, Hoy no avisa del respaldo', (tester) async {
      await montar(tester);
      expect(find.byKey(const Key('aviso_drive_accion')), findsNothing);
      expect(_marca, findsNothing);
    });

    prueba('conectado y al día: nada', (tester) async {
      await montar(tester, problema: (a, u) async => a.repo.conectar(u).then((_) {}));
      expect(find.byKey(const Key('aviso_drive_accion')), findsNothing);
      expect(_marca, findsNothing);
    });

    prueba('la franja es de Hoy: en las demás pestañas no está', (tester) async {
      await montar(tester, problema: _revocado);
      expect(_franjaRevocada, findsOneWidget);

      await tester.tap(find.text('Lista'));
      await tester.pumpAndSettle();
      expect(_franjaRevocada, findsNothing);

      await tester.tap(find.text('Hoy'));
      await tester.pumpAndSettle();
      expect(_franjaRevocada, findsOneWidget);
    });
  });

  group('16F·03 Con otros avisos de Hoy', () {
    prueba('va primera: arriba del aviso de las notificaciones apagadas', (tester) async {
      final telefono = Telefono()..recuerdo.pedido = PedidoNotificaciones.ahoraNo;
      await montar(tester, problema: _revocado, telefono: telefono);

      final otro = find.byKey(const Key('aviso_notificaciones_texto'));
      expect(otro, findsOneWidget);
      expect(
        tester.getTopLeft(_franjaRevocada).dy,
        lessThan(tester.getTopLeft(otro).dy),
        reason: 'la del Drive avisa de datos sin copia: va primera',
      );
    });

    prueba('con el texto al 200 % cada aviso crece y la franja se desplaza (tope de 40 %)', (
      tester,
    ) async {
      final telefono = Telefono()..recuerdo.pedido = PedidoNotificaciones.ahoraNo;
      await montar(
        tester,
        problema: _revocado,
        telefono: telefono,
        pantalla: const Size(360, 640),
        escalaTexto: 2,
      );

      expect(tester.takeException(), isNull, reason: 'overflow o error de render');
      expect(tester.getSize(_franja).height, lessThanOrEqualTo(640 * 0.4 + 0.5));
      // «Ocultar hasta mañana» y «Reconectar en Configuración» se alcanzan desplazando la franja.
      await tester.ensureVisible(_ocultar);
      await tester.ensureVisible(_accion);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_ocultar).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(_accion).height, greaterThanOrEqualTo(48));
    });
  });

  group('16F·04 Oculta hasta mañana', () {
    prueba(
      '«Ocultar hasta mañana»: la franja se va, el aviso lo dice y el engranaje lleva la marca',
      (tester) async {
        await montar(tester, problema: _revocado);
        await tester.tap(_ocultar);
        await tester.pumpAndSettle();

        expect(_franjaRevocada, findsNothing);
        expect(_snackOculto, findsOneWidget);
        expect(find.text('Te lo recordamos mañana. Lo ves en Configuración.'), findsOneWidget);
        expect(_marca, findsOneWidget);
        expect(
          tester.widget<IconButton>(_engranaje).tooltip,
          'Configuración: hay un aviso del respaldo',
        );
      },
    );

    prueba('con la franja oculta, la fila «Cuenta Drive» sigue en rojo en Configuración', (
      tester,
    ) async {
      await montar(tester, problema: _revocado);
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();
      await tester.tap(_engranaje);
      await tester.pumpAndSettle();

      expect(find.text('Sin permiso · los respaldos están frenados'), findsOneWidget);
    });

    prueba('queda oculta al salir y volver a entrar a Hoy y a Configuración (se guardó)', (
      tester,
    ) async {
      await montar(tester, problema: _revocado);
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();
      await tester.tap(_engranaje);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsNothing);
      expect(_marca, findsOneWidget);
    });

    prueba(
      'cerrar la app y abrirla el mismo día: sigue oculta (el día vive en el almacén seguro)',
      (tester) async {
        await montar(tester, problema: _revocado);
        await tester.tap(_ocultar);
        await tester.pumpAndSettle();

        await tester.pumpWidget(const SizedBox.shrink());
        await montar(tester);

        expect(_franjaRevocada, findsNothing);
        expect(_marca, findsOneWidget);
      },
    );

    prueba('al día siguiente, apenas la app vuelve al frente, la franja sale de nuevo', (
      tester,
    ) async {
      await montar(tester, problema: _revocado);
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();
      expect(_franjaRevocada, findsNothing);

      ahora = DateTime(2026, 11, 21, 7, 5);
      volverALaApp(tester);
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsOneWidget);
      expect(_marca, findsNothing);
    });

    prueba('el mismo día, volver al frente no la trae de vuelta', (tester) async {
      await montar(tester, problema: _revocado);
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();

      ahora = DateTime(2026, 11, 20, 23, 40);
      volverALaApp(tester);
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsNothing);
    });

    prueba('doble toque en «Ocultar hasta mañana»: se anota una vez y un solo aviso', (
      tester,
    ) async {
      await montar(tester, problema: _revocado);

      await tester.tap(_ocultar);
      await tester.tap(_ocultar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsNothing);
      expect(_snackOculto, findsOneWidget);
    });

    prueba('si no se pudo anotar: la franja sigue, lo dice y el botón no queda trabado', (
      tester,
    ) async {
      await montar(tester, problema: _revocado);
      drive.almacen.alEscribir = true;
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsOneWidget);
      expect(_snackNoOculto, findsOneWidget);
      expect(find.text('No pudimos ocultar el aviso. Probá de nuevo.'), findsOneWidget);
      expect(_marca, findsNothing);
      expect(tester.widget<TextButton>(_ocultar).onPressed, isNotNull);

      drive.almacen.alEscribir = false;
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();
      expect(_franjaRevocada, findsNothing);
      expect(_marca, findsOneWidget);
    });

    prueba('«Ocultar» no esconde un problema NUEVO: de «sin espacio» a «permiso revocado» vuelve', (
      tester,
    ) async {
      final c = await montar(tester, problema: _lleno);
      await tester.tap(_ocultar);
      await tester.pumpAndSettle();
      expect(_franjaLlena, findsNothing);

      final u = c.read(sesionProvider).value!.usuarioId;
      await drive.repo.marcarPermisoRevocado(u);
      await c.read(estadoRespaldoDriveProvider.notifier).recargar();
      await tester.pumpAndSettle();

      expect(_franjaRevocada, findsOneWidget);
      expect(_marca, findsNothing);
    });
  });

  group('Teclado abierto y accesibilidad', () {
    prueba('con el teclado abierto gana el campo: la franja se oculta y vuelve al cerrarlo', (
      tester,
    ) async {
      await montar(tester, problema: _revocado);
      expect(_franjaRevocada, findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(_franjaRevocada, findsNothing);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(_franjaRevocada, findsOneWidget);
    });

    prueba('objetivos de toque y etiquetas de la franja', (tester) async {
      await montar(tester, problema: _revocado);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    prueba('las dos franjas a 360×640 con letra normal entran sin desborde', (tester) async {
      await montar(tester, problema: _lleno, pantalla: const Size(360, 640));
      expect(tester.takeException(), isNull);
      expect(_franjaLlena, findsOneWidget);
    });
  });
}
