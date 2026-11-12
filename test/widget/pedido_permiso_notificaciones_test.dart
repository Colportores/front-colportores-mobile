// El pedido del permiso de notificaciones en el primer ingreso (HU-NOT-001, vista 24, grupo A):
// 24A·01 (el pedido), 24A·02 (el diálogo del sistema, que dibuja Android: acá se prueba el orden),
// 24A·03 (rechazo: aviso sutil en Hoy), 24A·04 (activadas), 24A·05 (activadas sin conexión). Se prueba
// con la app entera: el pedido sale después de preparar el espacio seguro y antes de la pantalla
// principal. 24A·06 (bloqueadas) está en `notificaciones_page_test.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/pedido_permiso_notificaciones_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';

/// Deja pasar las animaciones del toast sin llegar a sus 4 s: `pumpAndSettle` lo vería desaparecer.
Future<void> _verElToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('24A·01 · el pedido del permiso (primer ingreso)', () {
    testWidgets(
      'dado que es mi primer ingreso con las notificaciones apagadas, después de preparar '
      'la base veo el pedido y no la pantalla principal',
      (tester) async {
        final telefono = Telefono();
        await abrirApp(tester, telefono);

        expect(pedidoPagina, findsOneWidget);
        expect(principal, findsNothing);
        expect(
          find.text('Activá notificaciones para no perderte avisos importantes'),
          findsOneWidget,
        );
        expect(find.text('Recordatorios de tus visitas'), findsOneWidget);
        expect(find.text('Con la dirección y el tipo, sin el nombre del cliente'), findsOneWidget);
        expect(find.text('Pedidos y tickets revisados'), findsOneWidget);
        expect(find.text('Cambios de zona y de campaña'), findsOneWidget);
        expect(find.text('Activar notificaciones'), findsOneWidget);
        expect(find.text('Ahora no'), findsOneWidget);
      },
    );

    testWidgets('mientras no contesto no se muestra nada de más: el sistema todavía no preguntó', (
      tester,
    ) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);

      expect(telefono.sistema.pedidos, 0);
      expect(telefono.recuerdo.pedido, isNull);
    });

    testWidgets('el título es un encabezado para el lector de pantalla', (tester) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);

      final semantica = tester.getSemantics(find.byKey(const Key('permiso_notificaciones_titulo')));
      expect(semantica.flagsCollection.isHeader, isTrue);
    });

    testWidgets('dado que ya están activadas en el teléfono, no se pide nada y entro directo', (
      tester,
    ) async {
      final telefono = Telefono(estado: EstadoSistemaNotificaciones.activadas);
      await abrirApp(tester, telefono);

      expect(pedidoPagina, findsNothing);
      expect(principal, findsOneWidget);
      expect(avisoApagadas, findsNothing);
      expect(telefono.sistema.pedidos, 0);
    });

    testWidgets('si el sistema no contesta por las notificaciones, no me atrapa en el pedido', (
      tester,
    ) async {
      final telefono = Telefono()..sistema.fallaAlLeer = true;
      await abrirApp(tester, telefono);

      expect(pedidoPagina, findsNothing);
      expect(principal, findsOneWidget);
    });

    testWidgets('si el almacén no se deja leer, tampoco me atrapa en el pedido', (tester) async {
      final telefono = Telefono();
      telefono.recuerdo.fallaAlLeer = true;
      await abrirApp(tester, telefono);

      expect(pedidoPagina, findsNothing);
      expect(principal, findsOneWidget);
    });

    testWidgets('el pedido no vuelve: contestado una vez, al reabrir la app no aparece', (
      tester,
    ) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);
      await tester.tap(pedidoAhoraNo);
      await tester.pumpAndSettle();
      expect(principal, findsOneWidget);

      await abrirApp(tester, telefono, iniciarSesion: false);

      expect(pedidoPagina, findsNothing);
      expect(principal, findsOneWidget);
    });

    testWidgets('si cierro la app con el diálogo abierto (sin contestar), al volver se pide de '
        'nuevo', (tester) async {
      final telefono = Telefono();
      telefono.sistema.dialogoAbierto = Completer<void>();
      await abrirApp(tester, telefono);
      await tester.tap(pedidoActivar);
      await tester.pump();
      expect(telefono.sistema.pedidos, 1);

      await abrirApp(tester, telefono, iniciarSesion: false);

      expect(pedidoPagina, findsOneWidget);
      expect(telefono.recuerdo.pedido, isNull);
    });
  });

  group('24A·02 · el diálogo del sistema', () {
    testWidgets('«Activar notificaciones» lo muestra una sola vez, aunque toque dos veces', (
      tester,
    ) async {
      final telefono = Telefono();
      final abierto = telefono.sistema.dialogoAbierto = Completer<void>();
      await abrirApp(tester, telefono);

      await tester.tap(pedidoActivar);
      await tester.pump();
      await tester.tap(pedidoActivar, warnIfMissed: false);
      await tester.pump();

      expect(telefono.sistema.pedidos, 1);
      abierto.complete();
      await _verElToast(tester);
    });

    testWidgets('mientras el diálogo está abierto los dos botones quedan apagados y el de activar '
        'muestra que espera', (tester) async {
      final telefono = Telefono();
      final abierto = telefono.sistema.dialogoAbierto = Completer<void>();
      await abrirApp(tester, telefono);

      await tester.tap(pedidoActivar);
      await tester.pump();

      expect(pedidoPidiendo, findsOneWidget);
      expect(tester.widget<FilledButton>(pedidoActivar).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(pedidoAhoraNo).onPressed, isNull);
      abierto.complete();
      await _verElToast(tester);
    });

    testWidgets('dos acciones seguidas: «Ahora no» mientras el diálogo está abierto no pisa lo que '
        'conteste', (tester) async {
      final telefono = Telefono();
      final abierto = telefono.sistema.dialogoAbierto = Completer<void>();
      await abrirApp(tester, telefono);

      await tester.tap(pedidoActivar);
      await tester.pump();
      await tester.tap(pedidoAhoraNo, warnIfMissed: false);
      await tester.pump();
      abierto.complete();
      await _verElToast(tester);

      expect(telefono.recuerdo.pedido, PedidoNotificaciones.sistema);
      expect(principal, findsOneWidget);
      expect(avisoApagadas, findsNothing);
    });

    testWidgets('si falla a mitad (el sistema no mostró el diálogo) lo dice, los botones vuelven a '
        'estar disponibles y puedo reintentar', (tester) async {
      final telefono = Telefono();
      telefono.sistema.fallaAlPedir = true;
      await abrirApp(tester, telefono);

      await tester.tap(pedidoActivar);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(pedidoFallo, findsOneWidget);
      expect(pedidoPidiendo, findsNothing);
      expect(pedidoPagina, findsOneWidget);
      expect(tester.widget<FilledButton>(pedidoActivar).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(pedidoAhoraNo).onPressed, isNotNull);
      expect(telefono.recuerdo.pedido, isNull);

      telefono.sistema.fallaAlPedir = false;
      await tester.tap(pedidoActivar);
      await _verElToast(tester);

      expect(principal, findsOneWidget);
      expect(pedidoFallo, findsNothing);
    });

    testWidgets('si falla puedo seguir con «Ahora no» y no queda nada trabado', (tester) async {
      final telefono = Telefono();
      telefono.sistema.fallaAlPedir = true;
      await abrirApp(tester, telefono);
      await tester.tap(pedidoActivar);
      await tester.pump();
      await tester.pumpAndSettle();

      // Los botones quedaron a la vista aunque el aviso los empujó hacia abajo.
      expect(tester.getRect(pedidoAhoraNo).bottom, lessThanOrEqualTo(844));
      await tester.tap(pedidoAhoraNo);
      await tester.pumpAndSettle();

      expect(principal, findsOneWidget);
      expect(avisoApagadas, findsOneWidget);
    });
  });

  group('24A·03 · dijo que no: aviso sutil en Hoy', () {
    testWidgets('«Ahora no»: sigo normalmente, con el aviso de la HU y sin haber molestado al '
        'sistema', (tester) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);

      await tester.tap(pedidoAhoraNo);
      await tester.pumpAndSettle();

      expect(principal, findsOneWidget);
      expect(avisoApagadas, findsOneWidget);
      expect(find.text(textoAviso), findsOneWidget);
      expect(find.text('Ir a configuración'), findsOneWidget);
      expect(telefono.sistema.pedidos, 0);
      expect(telefono.recuerdo.pedido, PedidoNotificaciones.ahoraNo);
    });

    testWidgets(
      '«No permitir» en el diálogo del sistema: sigo normalmente, con el aviso y sin toast '
      'de activadas',
      (tester) async {
        final telefono = Telefono();
        telefono.sistema.respuestaAlPedir = false;
        await abrirApp(tester, telefono);

        await tester.tap(pedidoActivar);
        await _verElToast(tester);

        expect(principal, findsOneWidget);
        expect(avisoApagadas, findsOneWidget);
        expect(toastActivadas, findsNothing);
        expect(telefono.recuerdo.pedido, PedidoNotificaciones.sistema);
      },
    );

    testWidgets(
      'el aviso se cierra con la ✕ y no vuelve en esta instalación, ni al reabrir la app',
      (tester) async {
        final telefono = Telefono();
        await abrirApp(tester, telefono);
        await tester.tap(pedidoAhoraNo);
        await tester.pumpAndSettle();

        await tester.tap(avisoCerrar);
        await tester.pumpAndSettle();

        expect(avisoApagadas, findsNothing);
        expect(telefono.recuerdo.avisoCerrado, isTrue);

        await abrirApp(tester, telefono, iniciarSesion: false);
        expect(principal, findsOneWidget);
        expect(avisoApagadas, findsNothing);
      },
    );

    testWidgets('«Ir a configuración» lleva a Configuración › Notificaciones, una sola vez aunque '
        'toque dos veces', (tester) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);
      await tester.tap(pedidoAhoraNo);
      await tester.pumpAndSettle();

      await tester.tap(avisoIr);
      await tester.tap(avisoIr, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(paginaNotificaciones, findsOneWidget);
      await tester.tap(find.byKey(const Key('notificaciones_atras')));
      await tester.pumpAndSettle();
      expect(paginaNotificaciones, findsNothing);
      expect(principal, findsOneWidget);
    });

    testWidgets('si después las activo en los ajustes del teléfono, al volver a la app el aviso '
        'se va solo', (tester) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);
      await tester.tap(pedidoAhoraNo);
      await tester.pumpAndSettle();
      expect(avisoApagadas, findsOneWidget);

      telefono.sistema.estado = EstadoSistemaNotificaciones.activadas;
      volverALaApp(tester);
      await tester.pumpAndSettle();

      expect(avisoApagadas, findsNothing);
    });
  });

  group('24A·04 · activadas (éxito)', () {
    testWidgets('«Activar notificaciones» y «Permitir»: «Notificaciones activadas.» y sigo a la '
        'pantalla principal sin aviso', (tester) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);

      await tester.tap(pedidoActivar);
      await _verElToast(tester);

      expect(telefono.sistema.pedidos, 1);
      expect(principal, findsOneWidget);
      expect(pedidoPagina, findsNothing);
      expect(find.text(textoToast), findsOneWidget);
      expect(find.text(textoToastSinConexion), findsNothing);
      expect(avisoApagadas, findsNothing);
      expect(telefono.recuerdo.pedido, PedidoNotificaciones.sistema);
    });

    testWidgets('el toast se anuncia al lector de pantalla y desaparece solo', (tester) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);
      await tester.tap(pedidoActivar);
      await _verElToast(tester);

      final semantica = tester.getSemantics(find.text(textoToast));
      expect(semantica.label, contains(textoToast));

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(toastActivadas, findsNothing);
    });

    testWidgets('el pedido no vuelve al reabrir la app, y la pantalla principal queda sin aviso', (
      tester,
    ) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);
      await tester.tap(pedidoActivar);
      await _verElToast(tester);

      await abrirApp(tester, telefono, iniciarSesion: false);

      expect(pedidoPagina, findsNothing);
      expect(principal, findsOneWidget);
      expect(avisoApagadas, findsNothing);
    });
  });

  group('24A·05 · activadas sin conexión', () {
    testWidgets('sin conexión el toast dice que los recordatorios ya funcionan y que los avisos '
        'llegan cuando haya conexión', (tester) async {
      final telefono = Telefono();
      telefono.conexion.tipo = TipoConexion.sinConexion;
      await abrirApp(tester, telefono);

      await tester.tap(pedidoActivar);
      await _verElToast(tester);

      expect(principal, findsOneWidget);
      expect(find.text(textoToastSinConexion), findsOneWidget);
      expect(find.text(textoToast), findsNothing);
    });

    testWidgets('con datos móviles es el toast común', (tester) async {
      final telefono = Telefono();
      telefono.conexion.tipo = TipoConexion.datosMoviles;
      await abrirApp(tester, telefono);

      await tester.tap(pedidoActivar);
      await _verElToast(tester);

      expect(find.text(textoToast), findsOneWidget);
    });
  });

  group('casos límite del pedido', () {
    for (final (nombre, tamano, texto) in [
      ('texto al 200 % en 390 × 844', const Size(390, 844), 2.0),
      ('texto al 200 % en un teléfono chico (320 × 568)', const Size(320, 568), 2.0),
      ('texto al 300 % en un teléfono chico (320 × 568)', const Size(320, 568), 3.0),
    ]) {
      testWidgets('con $nombre no se corta nada y llego a los dos botones', (tester) async {
        fijarTamano(tester, tamano: tamano, texto: texto);
        final telefono = Telefono();
        await abrirPantalla(tester, telefono, const PedidoPermisoNotificacionesPage());

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(pedidoAhoraNo);
        await tester.pump();
        expect(tester.getRect(pedidoAhoraNo).bottom, lessThanOrEqualTo(tamano.height));
        await tester.ensureVisible(pedidoActivar);
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.tap(pedidoActivar);
        await _verElToast(tester);
        expect(telefono.sistema.pedidos, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('los dos botones miden al menos 48 puntos de alto', (tester) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);

      expect(tester.getSize(pedidoActivar).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(pedidoAhoraNo).height, greaterThanOrEqualTo(48));
    });

    testWidgets('cumple las guías de accesibilidad de Flutter (tamaño y nombre de los toques)', (
      tester,
    ) async {
      final telefono = Telefono();
      await abrirApp(tester, telefono);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
