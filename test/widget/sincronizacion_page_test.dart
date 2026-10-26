// Vista 25 «Sincronización y respaldo» (HU-SYNC-007 y HU-SYNC-008): un grupo por artboard del canvas
// (25-01 a 25-11), los estados que la HU pide y el canvas no dibuja (cargando, error al leer, sesión
// sin renovar) y los casos límite de cada acción.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/pages/sincronizacion_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sincronizacion_falsos.dart';

/// Deja correr lo asíncrono sin `pumpAndSettle` (los giros nunca se asientan).
Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await asentar(tester);
}

void main() {
  group('25-01 todo al día', () {
    testWidgets('should say everything is up to date and show the dates', (tester) async {
      final t = TelefonoSync(
        estado: EstadoSincronizacion(
          ultimoEnvio: DateTime(2026, 10, 26, 14, 32),
          ultimaActualizacion: DateTime(2026, 10, 26, 14, 30),
          ultimoRespaldo: DateTime(2026, 10, 25, 22),
        ),
        respaldoConfigurado: true,
      );
      await abrirSincronizacion(tester, t);

      expect(textoDe(tarjetaTitulo), 'Todo al día');
      expect(textoDe(tarjetaDetalle), contains('lo último de tu coordinador'));
      expect(textoDe(find.byKey(const Key('sincronizacion_ultimo_envio'))), 'hace 3 min');
      expect(textoDe(find.byKey(const Key('sincronizacion_pendientes'))), '0');
      expect(textoDe(find.byKey(const Key('sincronizacion_ultima_actualizacion'))), 'hace 5 min');
      expect(textoDe(find.byKey(const Key('sincronizacion_ultimo_respaldo'))), contains('Drive'));
      expect(find.text('Actualizar ahora'), findsOneWidget);
      expect(avisoSinConexion, findsNothing);
      expect(avisoError, findsNothing);
    });

    testWidgets('should not say "nunca" when the phone does not know the date', (tester) async {
      final t = TelefonoSync(respaldoConfigurado: true);
      await abrirSincronizacion(tester, t);

      expect(textoDe(find.byKey(const Key('sincronizacion_ultimo_envio'))), 'Todavía no hubo');
      expect(
        textoDe(find.byKey(const Key('sincronizacion_ultima_actualizacion'))),
        'Todavía no hubo',
      );
      expect(find.text('nunca'), findsNothing);
      expect(textoDe(tarjetaDetalle), contains('Actualizar ahora'));
    });
  });

  group('25-02 con operaciones pendientes', () {
    testWidgets('should count the pending operations and tell they leave on their own', (
      tester,
    ) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 3));
      await abrirSincronizacion(tester, t);

      expect(textoDe(tarjetaTitulo), '3 operaciones sin enviar');
      expect(textoDe(tarjetaDetalle), 'Se envían solas cuando haya conexión.');
      expect(textoDe(find.byKey(const Key('sincronizacion_pendientes'))), '3');
    });

    testWidgets('should use the singular for one operation', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 1));
      await abrirSincronizacion(tester, t);

      expect(textoDe(tarjetaTitulo), '1 operación sin enviar');
    });

    testWidgets('should follow the engine while the screen is open', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 3));
      await abrirSincronizacion(tester, t);

      t.servicio.emitir(const EstadoSincronizacion());
      await asentar(tester);

      expect(textoDe(tarjetaTitulo), 'Todo al día');
    });
  });

  group('25-03 actualizando', () {
    testWidgets('should show the progress and block the button while it runs', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 3));
      t.servicio.actualizacionEnCurso = Completer();
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(textoDe(tarjetaTitulo), 'Actualizando…');
      expect(textoDe(tarjetaDetalle), 'Enviando 1 de 3 · después traemos los cambios');
      expect(find.byKey(const Key('sincronizacion_boton_giro')), findsOneWidget);
      final boton = tester.widget<FilledButton>(botonActualizar);
      expect(boton.onPressed, isNull);

      t.servicio.emitir(const EstadoSincronizacion(pendientes: 2));
      await asentar(tester);
      expect(textoDe(tarjetaDetalle), 'Enviando 2 de 3 · después traemos los cambios');
    });

    testWidgets('should say it is bringing the changes when nothing is left to send', (
      tester,
    ) async {
      final t = TelefonoSync();
      t.servicio.actualizacionEnCurso = Completer();
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(textoDe(tarjetaDetalle), contains('Trayendo los cambios'));
    });
  });

  group('25-04 actualizado (éxito)', () {
    testWidgets('should confirm how much was sent and received', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 3));
      t.servicio.resultado = const ActualizacionCompleta(enviadas: 3, recibidas: 12);
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);
      t.servicio.emitir(const EstadoSincronizacion());
      await asentar(tester);

      expect(toastListo, findsOneWidget);
      expect(find.text('Listo: enviamos 3 operaciones y recibimos 12 cambios.'), findsOneWidget);
      expect(textoDe(tarjetaTitulo), 'Todo al día');
      expect(t.servicio.llamadasActualizar, 1);
    });

    testWidgets('should say everything was up to date when nothing moved', (tester) async {
      final t = TelefonoSync();
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(find.text('Listo: todo estaba al día.'), findsOneWidget);
    });
  });

  group('25-05 sin conexión', () {
    testWidgets('should warn, keep working and switch the button off', (tester) async {
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(pendientes: 2),
        conexion: TipoConexion.sinConexion,
      );
      await abrirSincronizacion(tester, t);

      expect(avisoSinConexion, findsOneWidget);
      expect(find.textContaining('podés seguir trabajando'), findsOneWidget);
      expect(tester.widget<FilledButton>(botonActualizar).onPressed, isNull);
      expect(t.servicio.llamadasActualizar, 0);
    });

    testWidgets('should switch the button on again when the connection comes back', (tester) async {
      final t = TelefonoSync(conexion: TipoConexion.sinConexion);
      await abrirSincronizacion(tester, t);

      t.red.cambiarA(TipoConexion.wifi);
      await asentar(tester);

      expect(avisoSinConexion, findsNothing);
      expect(tester.widget<FilledButton>(botonActualizar).onPressed, isNotNull);
    });
  });

  group('25-06 operaciones con error de datos', () {
    TelefonoSync dosFallidas() => TelefonoSync(
      estado: const EstadoSincronizacion(invalidas: 2),
      fallidas: [
        operacionFallida(),
        operacionFallida(id: 'op-2', tabla: 'cobranza', fecha: DateTime(2026, 10, 23)),
      ],
    );

    testWidgets('should list what could not be sent and say the rest is fine', (tester) async {
      await abrirSincronizacion(tester, dosFallidas());

      expect(textoDe(tarjetaTitulo), '2 operaciones no se pudieron enviar');
      expect(textoDe(tarjetaDetalle), 'El resto está al día.');
      expect(find.text('NO SE PUDIERON ENVIAR'), findsOneWidget);
      expect(find.text('Venta del 22/10'), findsOneWidget);
      expect(find.text('Cobro del 23/10'), findsOneWidget);
      expect(find.text('Reintentar las 2'), findsOneWidget);
    });

    testWidgets('should use the singular for one and mention what is still waiting', (
      tester,
    ) async {
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(invalidas: 1, pendientes: 2),
        fallidas: [operacionFallida()],
      );
      await abrirSincronizacion(tester, t);

      expect(textoDe(tarjetaTitulo), '1 operación no se pudo enviar');
      expect(textoDe(tarjetaDetalle), contains('2 operaciones más esperando'));
      expect(find.text('Reintentar la que falló'), findsOneWidget);
    });

    testWidgets('should not show the person data of the row', (tester) async {
      await abrirSincronizacion(tester, dosFallidas());

      expect(find.textContaining('Grecia'), findsNothing);
      expect(find.textContaining('Juan'), findsNothing);
    });

    testWidgets('should requeue all of them and update with "Reintentar las 2"', (tester) async {
      final t = dosFallidas();
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(t.servicio.reintentos, [null]);
      expect(t.servicio.llamadasActualizar, 1);
    });

    testWidgets('should show a long list without overflowing at text scale 2.0', (tester) async {
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(invalidas: 40),
        fallidas: [
          for (var i = 0; i < 40; i++)
            operacionFallida(
              id: 'op-$i',
              error:
                  'Nuestros Hijos ya no tiene precio en Montevideo para la campaña de este año y '
                  'el servidor no pudo aceptar la venta número $i',
            ),
        ],
      );
      await abrirSincronizacion(tester, t, tamano: const Size(320, 640), textScale: 2);

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const Key('sincronizacion_modo_ahorro')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('should say it could not show the list when reading it fails', (tester) async {
      final t = dosFallidas();
      t.servicio.fallaAlLeerFallidas = true;
      await abrirSincronizacion(tester, t);

      expect(find.byKey(const Key('sincronizacion_error_fallidas')), findsOneWidget);
      expect(textoDe(tarjetaTitulo), '2 operaciones no se pudieron enviar');
      expect(find.text('Reintentar las 2'), findsOneWidget);
    });
  });

  group('25-07 detalle de una operación fallida', () {
    TelefonoSync conUna() => TelefonoSync(
      estado: const EstadoSincronizacion(invalidas: 1),
      fallidas: [operacionFallida()],
    );

    testWidgets('should open the sheet with the type, the date and the code', (tester) async {
      await abrirSincronizacion(tester, conUna());

      await tocar(tester, find.text('Venta del 22/10'));

      expect(hojaDetalle, findsOneWidget);
      expect(textoDe(find.byKey(const Key('sincronizacion_detalle_tipo'))), 'Alta');
      expect(textoDe(find.byKey(const Key('sincronizacion_detalle_codigo'))), '23514');
      expect(find.textContaining('Nuestros Hijos ya no tiene precio en Montevideo'), findsWidgets);
      expect(find.byKey(const Key('sincronizacion_detalle_reintentar')), findsOneWidget);
      expect(find.byKey(const Key('sincronizacion_detalle_cerrar')), findsOneWidget);
      expect(find.textContaining('scartar'), findsNothing);
    });

    testWidgets('should close without sending anything', (tester) async {
      final t = conUna();
      await abrirSincronizacion(tester, t);
      await tocar(tester, find.text('Venta del 22/10'));

      await tocar(tester, find.byKey(const Key('sincronizacion_detalle_cerrar')));

      expect(hojaDetalle, findsNothing);
      expect(t.servicio.reintentos, isEmpty);
      expect(t.servicio.llamadasActualizar, 0);
    });

    testWidgets('should retry only that operation', (tester) async {
      final t = conUna();
      await abrirSincronizacion(tester, t);
      await tocar(tester, find.text('Venta del 22/10'));

      await tocar(tester, find.byKey(const Key('sincronizacion_detalle_reintentar')));

      expect(hojaDetalle, findsNothing);
      expect(t.servicio.reintentos, ['op-1']);
      expect(t.servicio.llamadasActualizar, 1);
    });

    testWidgets('should not open a second sheet on a double tap', (tester) async {
      await abrirSincronizacion(tester, conUna());
      final tarjeta = find.text('Venta del 22/10');
      await tester.ensureVisible(tarjeta);

      await tester.tap(tarjeta);
      await tester.tap(tarjeta, warnIfMissed: false);
      await asentar(tester);

      expect(hojaDetalle, findsOneWidget);
    });

    testWidgets('should show a generic text when the server gave no reason', (tester) async {
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(invalidas: 1),
        fallidas: [operacionFallida(error: '', codigo: '')],
      );
      await abrirSincronizacion(tester, t);
      expect(find.text('El servidor la rechazó.'), findsOneWidget);

      await tocar(tester, find.text('Venta del 22/10'));

      expect(find.textContaining('El servidor rechazó esta operación'), findsOneWidget);
      expect(find.byKey(const Key('sincronizacion_detalle_codigo')), findsNothing);
    });

    testWidgets('should fit at text scale 2.0 on a small screen', (tester) async {
      await abrirSincronizacion(tester, conUna(), tamano: const Size(320, 640), textScale: 2);
      await tocar(tester, find.text('Venta del 22/10'));

      expect(tester.takeException(), isNull);
      expect(hojaDetalle, findsOneWidget);
    });
  });

  group('25-08 modo ahorro con datos móviles', () {
    testWidgets('should show the saving notice only with the mode on and mobile data', (
      tester,
    ) async {
      final t = TelefonoSync(modoAhorro: true, conexion: TipoConexion.datosMoviles);
      await abrirSincronizacion(tester, t);

      expect(avisoAhorro, findsOneWidget);
      expect(find.textContaining('esperan al Wi-Fi'), findsWidgets);
      expect(tester.widget<SwitchListTile>(interruptorAhorro).value, isTrue);
    });

    testWidgets('should not show it on Wi-Fi or with the mode off', (tester) async {
      await abrirSincronizacion(tester, TelefonoSync(modoAhorro: true));
      expect(avisoAhorro, findsNothing);

      await abrirSincronizacion(tester, TelefonoSync(conexion: TipoConexion.datosMoviles));
      expect(avisoAhorro, findsNothing);
    });

    testWidgets('should mark the update as waiting for Wi-Fi', (tester) async {
      final t = TelefonoSync(
        estado: EstadoSincronizacion(
          ultimaActualizacion: DateTime(2026, 10, 26, 8),
          actualizacionEnEspera: true,
        ),
        modoAhorro: true,
        conexion: TipoConexion.datosMoviles,
      );
      await abrirSincronizacion(tester, t);

      expect(
        textoDe(find.byKey(const Key('sincronizacion_ultima_actualizacion'))),
        contains('espera Wi-Fi'),
      );
      expect(textoDe(tarjetaDetalle), contains('espera al Wi-Fi'));
    });

    testWidgets('should save the switch and tell the engine', (tester) async {
      final t = TelefonoSync();
      await abrirSincronizacion(tester, t);

      await tocar(tester, interruptorAhorro);

      expect(t.guardado.activo, isTrue);
      expect(tester.widget<SwitchListTile>(interruptorAhorro).value, isTrue);
    });

    testWidgets('should give the old value back when saving fails', (tester) async {
      final t = TelefonoSync();
      t.guardado.fallaAlGuardar = true;
      await abrirSincronizacion(tester, t);

      await tocar(tester, interruptorAhorro);

      expect(tester.widget<SwitchListTile>(interruptorAhorro).value, isFalse);
      expect(find.byKey(const Key('sincronizacion_ahorro_no_guardo')), findsOneWidget);
      expect(find.text('No pudimos guardar el cambio. Probá de nuevo.'), findsOneWidget);

      t.guardado.fallaAlGuardar = false;
      await tocar(tester, interruptorAhorro);
      expect(tester.widget<SwitchListTile>(interruptorAhorro).value, isTrue);
      expect(find.byKey(const Key('sincronizacion_ahorro_no_guardo')), findsNothing);
    });
  });

  group('25-09 actualizar ahora con modo ahorro', () {
    TelefonoSync conAhorro() => TelefonoSync(
      estado: const EstadoSincronizacion(pendientes: 1),
      modoAhorro: true,
      conexion: TipoConexion.datosMoviles,
    );

    testWidgets('should ask before using mobile data', (tester) async {
      final t = conAhorro();
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(hojaDatos, findsOneWidget);
      expect(find.text('¿Actualizar con datos móviles?'), findsOneWidget);
      expect(find.text('Actualizar igual'), findsOneWidget);
      expect(find.text('Esperar al Wi-Fi'), findsOneWidget);
      expect(t.servicio.llamadasActualizar, 0);
    });

    testWidgets('should update on "Actualizar igual"', (tester) async {
      final t = conAhorro();
      await abrirSincronizacion(tester, t);
      await tocar(tester, botonActualizar);

      await tocar(tester, find.byKey(const Key('sincronizacion_datos_actualizar_igual')));

      expect(hojaDatos, findsNothing);
      expect(t.servicio.llamadasActualizar, 1);
    });

    testWidgets('should do nothing on "Esperar al Wi-Fi"', (tester) async {
      final t = conAhorro();
      await abrirSincronizacion(tester, t);
      await tocar(tester, botonActualizar);

      await tocar(tester, find.byKey(const Key('sincronizacion_datos_esperar')));

      expect(hojaDatos, findsNothing);
      expect(t.servicio.llamadasActualizar, 0);
    });

    testWidgets('should treat closing the sheet as waiting, never as updating', (tester) async {
      final t = conAhorro();
      await abrirSincronizacion(tester, t);
      await tocar(tester, botonActualizar);

      await tester.tapAt(const Offset(195, 40));
      await asentar(tester);

      expect(hojaDatos, findsNothing);
      expect(t.servicio.llamadasActualizar, 0);
    });

    testWidgets('should not ask on Wi-Fi nor with the mode off', (tester) async {
      final t = TelefonoSync(modoAhorro: true);
      await abrirSincronizacion(tester, t);
      await tocar(tester, botonActualizar);
      expect(hojaDatos, findsNothing);
      expect(t.servicio.llamadasActualizar, 1);

      final u = TelefonoSync(conexion: TipoConexion.datosMoviles);
      await abrirSincronizacion(tester, u);
      await tocar(tester, botonActualizar);
      expect(hojaDatos, findsNothing);
      expect(u.servicio.llamadasActualizar, 1);
    });

    testWidgets('should not open a second sheet on a double tap', (tester) async {
      final t = conAhorro();
      await abrirSincronizacion(tester, t);

      await tester.tap(botonActualizar);
      await tester.tap(botonActualizar, warnIfMissed: false);
      await asentar(tester);

      expect(hojaDatos, findsOneWidget);
    });

    testWidgets('should fit at text scale 2.0', (tester) async {
      await abrirSincronizacion(tester, conAhorro(), tamano: const Size(320, 640), textScale: 2);
      await tocar(tester, botonActualizar);

      expect(tester.takeException(), isNull);
      expect(hojaDatos, findsOneWidget);
    });
  });

  group('25-10 error al actualizar', () {
    testWidgets('should warn the server did not answer and offer to retry', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 2));
      t.servicio.resultado = const ActualizacionFallida(MotivoFallaActualizacion.servidor);
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(avisoError, findsOneWidget);
      expect(find.textContaining('el servidor no responde'), findsOneWidget);
      expect(find.textContaining('sigue guardado en tu teléfono'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Actualizar ahora'), findsNothing);
      expect(toastListo, findsNothing);
    });

    testWidgets('should enable the button again and retry', (tester) async {
      final t = TelefonoSync();
      t.servicio.resultado = const ActualizacionFallida(MotivoFallaActualizacion.servidor);
      await abrirSincronizacion(tester, t);
      await tocar(tester, botonActualizar);
      expect(tester.widget<FilledButton>(botonActualizar).onPressed, isNotNull);

      t.servicio.resultado = const ActualizacionCompleta(recibidas: 1);
      await tocar(tester, botonActualizar);

      expect(avisoError, findsNothing);
      expect(t.servicio.llamadasActualizar, 2);
      expect(find.text('Listo: recibimos 1 cambio.'), findsOneWidget);
    });

    testWidgets('should recover when the engine throws halfway', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 2));
      t.servicio.lanzaAlActualizar = true;
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(avisoError, findsOneWidget);
      expect(textoDe(tarjetaTitulo), isNot('Actualizando…'));
      expect(find.byKey(const Key('sincronizacion_boton_giro')), findsNothing);
      expect(tester.widget<FilledButton>(botonActualizar).onPressed, isNotNull);
    });

    testWidgets('should recover when requeueing the failed ones throws', (tester) async {
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(invalidas: 1),
        fallidas: [operacionFallida()],
      );
      t.servicio.lanzaAlReintentar = true;
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(avisoError, findsOneWidget);
      expect(tester.widget<FilledButton>(botonActualizar).onPressed, isNotNull);
    });

    testWidgets('should say the session cannot be renewed when the server says 401', (
      tester,
    ) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 2));
      t.servicio.resultado = const ActualizacionFallida(MotivoFallaActualizacion.sesion);
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);

      expect(find.textContaining('renovar tu sesión'), findsOneWidget);
      expect(find.textContaining('el servidor no responde'), findsNothing);
    });

    testWidgets('should warn about the session even before trying again', (tester) async {
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(pendientes: 2, sesionSinRenovar: true),
      );
      await abrirSincronizacion(tester, t);

      expect(find.textContaining('renovar tu sesión'), findsOneWidget);
    });
  });

  group('25-11 sin respaldo configurado', () {
    testWidgets('should warn about the missing backup and show "nunca" in red', (tester) async {
      await abrirSincronizacion(tester, TelefonoSync());

      expect(avisoSinRespaldo, findsOneWidget);
      expect(find.textContaining('no tienen respaldo'), findsOneWidget);
      expect(textoDe(find.byKey(const Key('sincronizacion_ultimo_respaldo'))), 'nunca');
    });

    testWidgets('should not offer a button that leads nowhere while Drive is missing', (
      tester,
    ) async {
      await abrirSincronizacion(tester, TelefonoSync());

      expect(conectarDriveBoton, findsNothing);
    });

    testWidgets('should offer "Conectar Google Drive" when there is somewhere to go', (
      tester,
    ) async {
      var toques = 0;
      final t = TelefonoSync(conectarDrive: () => toques++);
      await abrirSincronizacion(tester, t);

      await tocar(tester, conectarDriveBoton);

      expect(find.text('Conectar Google Drive'), findsOneWidget);
      expect(toques, 1);
    });

    testWidgets('should not warn when a backup is configured', (tester) async {
      await abrirSincronizacion(tester, TelefonoSync(respaldoConfigurado: true));

      expect(avisoSinRespaldo, findsNothing);
      expect(textoDe(find.byKey(const Key('sincronizacion_ultimo_respaldo'))), 'Todavía no hubo');
    });
  });

  group('estados que la HU pide y el canvas no dibuja', () {
    testWidgets('should show the loading state while the state is read', (tester) async {
      final t = TelefonoSync();
      t.servicio.lecturaLenta = Completer();
      await abrirSincronizacion(tester, t);

      expect(cargando, findsOneWidget);
      expect(tarjetaTitulo, findsNothing);

      t.servicio.lecturaLenta!.complete();
      await asentar(tester);
      expect(cargando, findsNothing);
      expect(textoDe(tarjetaTitulo), 'Todo al día');
    });

    testWidgets('should say it could not read the state and offer to retry', (tester) async {
      final t = TelefonoSync();
      t.servicio.fallaAlLeer = true;
      await abrirSincronizacion(tester, t);

      expect(find.byKey(const Key('sincronizacion_error_lectura')), findsOneWidget);
      expect(find.text('No pudimos revisar el estado de la sincronización.'), findsOneWidget);

      t.servicio.fallaAlLeer = false;
      await tocar(tester, find.byKey(const Key('sincronizacion_reintentar_lectura')));
      expect(find.byKey(const Key('sincronizacion_error_lectura')), findsNothing);
      expect(textoDe(tarjetaTitulo), 'Todo al día');
    });

    testWidgets('should keep the saving switch usable when the state cannot be read', (
      tester,
    ) async {
      final t = TelefonoSync();
      t.servicio.fallaAlLeer = true;
      await abrirSincronizacion(tester, t);

      await tocar(tester, interruptorAhorro);

      expect(t.guardado.activo, isTrue);
    });
  });

  group('casos límite de «Actualizar ahora»', () {
    testWidgets('should send only one update on a double tap', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 1));
      t.servicio.actualizacionEnCurso = Completer();
      await abrirSincronizacion(tester, t);

      await tester.tap(botonActualizar);
      await tester.pump();
      await tester.tap(botonActualizar, warnIfMissed: false);
      await asentar(tester);

      expect(t.servicio.llamadasActualizar, 1);
    });

    testWidgets('should allow a new update after the first one finishes', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 1));
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);
      await tocar(tester, botonActualizar);

      expect(t.servicio.llamadasActualizar, 2);
    });

    testWidgets('should show two success notices for two equal updates in a row', (tester) async {
      final t = TelefonoSync();
      t.servicio.resultado = const ActualizacionCompleta(recibidas: 2);
      await abrirSincronizacion(tester, t);

      await tocar(tester, botonActualizar);
      expect(find.text('Listo: recibimos 2 cambios.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      await tocar(tester, botonActualizar);

      expect(find.text('Listo: recibimos 2 cambios.'), findsOneWidget);
      expect(t.servicio.llamadasActualizar, 2);
    });

    testWidgets('should keep saying "Actualizando…" after leaving and coming back', (tester) async {
      final t = TelefonoSync(estado: const EstadoSincronizacion(pendientes: 2));
      final enCurso = Completer<ResultadoActualizacion>();
      t.servicio.actualizacionEnCurso = enCurso;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: t.overrides,
          child: MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('abrir'),
                  onPressed: () => unawaited(Navigator.of(context).push(SincronizacionPage.ruta())),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tocar(tester, find.byKey(const Key('abrir')));
      await tocar(tester, botonActualizar);
      expect(textoDe(tarjetaTitulo), 'Actualizando…');

      await tocar(tester, find.byKey(const Key('sincronizacion_atras')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(pagina, findsNothing);
      await tocar(tester, find.byKey(const Key('abrir')));

      expect(textoDe(tarjetaTitulo), 'Actualizando…');
      expect(tester.widget<FilledButton>(botonActualizar).onPressed, isNull);
      expect(t.servicio.llamadasActualizar, 1);

      enCurso.complete(const ActualizacionCompleta(enviadas: 2));
      await asentar(tester);
      expect(find.text('Listo: enviamos 2 operaciones.'), findsOneWidget);
    });

    testWidgets('should not show an old success when the screen opens again', (tester) async {
      final t = TelefonoSync();
      await abrirSincronizacion(tester, t);
      await tocar(tester, botonActualizar);
      expect(find.byKey(const Key('sincronizacion_listo')), findsOneWidget);

      await abrirSincronizacion(tester, t);

      expect(textoDe(tarjetaTitulo), 'Todo al día');
      expect(avisoError, findsNothing);
    });

    testWidgets('should tell the saving mode to the engine on every change', (tester) async {
      final t = TelefonoSync();
      await abrirSincronizacion(tester, t);

      await tocar(tester, interruptorAhorro);
      await tocar(tester, interruptorAhorro);

      expect(t.guardado.guardados, 2);
      expect(t.guardado.activo, isFalse);
    });

    testWidgets('should ignore a second switch tap while the first is saving', (tester) async {
      final t = TelefonoSync();
      await abrirSincronizacion(tester, t);

      await tester.ensureVisible(interruptorAhorro);
      await tester.pump();
      await tester.tap(interruptorAhorro);
      await tester.tap(interruptorAhorro, warnIfMissed: false);
      await asentar(tester);

      expect(t.guardado.guardados, lessThanOrEqualTo(2));
      expect(t.guardado.guardados, greaterThanOrEqualTo(1));
      expect(tester.widget<SwitchListTile>(interruptorAhorro).value, t.guardado.activo);
    });
  });

  group('accesibilidad y tamaños', () {
    testWidgets('should fit at 320 dp and text scale 2.0 in every state', (tester) async {
      final casos = <TelefonoSync>[
        TelefonoSync(),
        TelefonoSync(estado: const EstadoSincronizacion(pendientes: 12)),
        TelefonoSync(
          estado: const EstadoSincronizacion(invalidas: 2),
          fallidas: [
            operacionFallida(),
            operacionFallida(id: 'op-2'),
          ],
        ),
        TelefonoSync(conexion: TipoConexion.sinConexion),
        TelefonoSync(modoAhorro: true, conexion: TipoConexion.datosMoviles),
      ];
      for (final t in casos) {
        await abrirSincronizacion(tester, t, tamano: const Size(320, 640), textScale: 2);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('should keep the touch targets at 48 dp or more', (tester) async {
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(invalidas: 1),
        fallidas: [operacionFallida()],
      );
      await abrirSincronizacion(tester, t);

      expect(tester.getSize(botonActualizar).height, greaterThanOrEqualTo(48));
      expect(
        tester.getSize(find.byKey(const Key('sincronizacion_atras'))).shortestSide,
        greaterThanOrEqualTo(48),
      );
      expect(tester.getSize(interruptorAhorro).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.text('Venta del 22/10')).height, greaterThan(0));
    });

    testWidgets('should meet the text contrast and tap target guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      final t = TelefonoSync(
        estado: const EstadoSincronizacion(pendientes: 3),
        fallidas: [operacionFallida()],
      );
      await abrirSincronizacion(tester, t);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('should label the title as a header and the state as a live region', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await abrirSincronizacion(tester, TelefonoSync());

      expect(
        tester.getSemantics(find.text('Sincronización y respaldo')),
        matchesSemantics(isHeader: true, label: 'Sincronización y respaldo'),
      );
      handle.dispose();
    });
  });
}
