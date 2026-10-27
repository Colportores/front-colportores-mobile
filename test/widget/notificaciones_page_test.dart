// Configuración › Notificaciones (HU-NOT-001, vista 24): 24A·06 (bloqueadas en el teléfono) y los demás
// estados del permiso: cargando, activadas, apagadas sin pedir («Activar»), error al leer. Las
// opciones de los recordatorios (HU-NOT-004, grupo B) tienen su propio archivo.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/configuracion/presentation/pages/configuracion_page.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';

final _cargando = find.byKey(const Key('notificaciones_cargando'));
final _interruptor = find.byKey(const Key('pref_recordatorios_interruptor'));
final _apagadas = find.byKey(const Key('notificaciones_apagadas'));
final _bloqueadas = find.byKey(const Key('notificaciones_bloqueadas'));
final _activar = find.byKey(const Key('notificaciones_activar'));
final _abrirAjustes = find.byKey(const Key('notificaciones_abrir_ajustes'));
final _ajustesNoAbren = find.byKey(const Key('notificaciones_ajustes_no_abren'));
final _fallo = find.byKey(const Key('notificaciones_fallo'));
final _error = find.byKey(const Key('notificaciones_error'));
final _reintentar = find.byKey(const Key('notificaciones_reintentar'));

/// El teléfono tal como queda después de dar el permiso y apagarlo (o de que el sistema lo negara).
Telefono _bloqueado() {
  final telefono = Telefono();
  telefono.recuerdo.pedido = PedidoNotificaciones.sistema;
  return telefono;
}

Future<void> _abrir(WidgetTester tester, Telefono telefono) =>
    abrirPantalla(tester, telefono, const NotificacionesPage());

void main() {
  group('24A·06 · bloqueadas en el teléfono', () {
    testWidgets('dice que están bloqueadas en los ajustes del teléfono y ofrece abrirlos', (
      tester,
    ) async {
      await _abrir(tester, _bloqueado());

      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('Notificaciones'), findsOneWidget);
      expect(find.text(textoBloqueadas), findsOneWidget);
      expect(find.text('Abrir ajustes del teléfono'), findsOneWidget);
      expect(_activar, findsNothing);
    });

    testWidgets(
      '«Abrir ajustes del teléfono» abre los ajustes, una sola vez aunque toque dos veces',
      (tester) async {
        final telefono = _bloqueado();
        final demora = telefono.sistema.ajustesDemorados = Completer<void>();
        await _abrir(tester, telefono);

        await tester.tap(_abrirAjustes);
        await tester.pump();
        await tester.tap(_abrirAjustes, warnIfMissed: false);
        await tester.pump();
        demora.complete();
        await tester.pumpAndSettle();

        expect(telefono.sistema.ajustesAbiertos, 1);
        expect(_ajustesNoAbren, findsNothing);
      },
    );

    testWidgets('si el teléfono no puede abrir los ajustes, le dice dónde buscarlos a mano', (
      tester,
    ) async {
      final telefono = _bloqueado();
      telefono.sistema.puedeAbrirAjustes = false;
      await _abrir(tester, telefono);

      await tester.tap(_abrirAjustes);
      await tester.pumpAndSettle();

      expect(_ajustesNoAbren, findsOneWidget);
      expect(find.textContaining('Buscá «Colportaje» en los ajustes del teléfono'), findsOneWidget);
      // Puede volver a intentarlo.
      expect(tester.widget<TextButton>(_abrirAjustes).onPressed, isNotNull);
    });

    testWidgets('el aviso es una región viva y el botón se puede tocar con el pulgar', (
      tester,
    ) async {
      await _abrir(tester, _bloqueado());

      expect(tester.getSemantics(_bloqueadas), isSemantics(isLiveRegion: true));
      expect(tester.getSize(_abrirAjustes).height, greaterThanOrEqualTo(48));
    });

    testWidgets(
      'al volver de los ajustes con las notificaciones activadas, la pantalla lo refleja',
      (tester) async {
        final telefono = _bloqueado();
        await _abrir(tester, telefono);
        expect(_bloqueadas, findsOneWidget);

        telefono.sistema.estado = EstadoSistemaNotificaciones.activadas;
        await tester.tap(_abrirAjustes);
        await tester.pumpAndSettle();
        await contenedorDe(tester).read(notificacionesProvider.notifier).refrescar();
        await tester.pumpAndSettle();

        expect(_interruptor, findsOneWidget);
        expect(_bloqueadas, findsNothing);
      },
    );
  });

  group('cargando', () {
    testWidgets('mientras el sistema no contesta se ve que está cargando y no se ofrece nada', (
      tester,
    ) async {
      final telefono = Telefono();
      final demora = telefono.sistema.lecturaDemorada = Completer<void>();
      await abrirPantallaSinEsperar(tester, telefono, const NotificacionesPage());

      expect(_cargando, findsOneWidget);
      expect(_activar, findsNothing);
      expect(_abrirAjustes, findsNothing);

      demora.complete();
      await tester.pumpAndSettle();
      expect(_cargando, findsNothing);
      expect(_apagadas, findsOneWidget);
    });
  });

  group('activadas', () {
    testWidgets('no hay nada que decir del permiso: se ven las preferencias', (tester) async {
      await _abrir(tester, Telefono(estado: EstadoSistemaNotificaciones.activadas));

      expect(_interruptor, findsOneWidget);
      expect(_apagadas, findsNothing);
      expect(_bloqueadas, findsNothing);
      expect(_activar, findsNothing);
      expect(_abrirAjustes, findsNothing);
    });
  });

  group('apagadas, el sistema todavía puede preguntar', () {
    testWidgets('dijo «Ahora no»: ofrece «Activar»', (tester) async {
      final telefono = Telefono();
      telefono.recuerdo.pedido = PedidoNotificaciones.ahoraNo;
      await _abrir(tester, telefono);

      expect(find.text(textoApagadas), findsOneWidget);
      expect(find.text('Activar'), findsOneWidget);
      expect(_abrirAjustes, findsNothing);
    });

    testWidgets('«Activar» y «Permitir»: quedan activadas y lo dice con el toast', (tester) async {
      final telefono = Telefono();
      await _abrir(tester, telefono);

      await tester.tap(_activar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(telefono.sistema.pedidos, 1);
      expect(_interruptor, findsOneWidget);
      expect(_apagadas, findsNothing);
      expect(find.text(textoToast), findsOneWidget);
      expect(telefono.recuerdo.pedido, PedidoNotificaciones.sistema);
    });

    testWidgets(
      '«Activar» sin conexión: el toast avisa que los avisos llegan cuando haya conexión',
      (tester) async {
        final telefono = Telefono();
        telefono.conexion.tipo = TipoConexion.sinConexion;
        await abrirPantalla(tester, telefono, const NotificacionesPage());
        // La conexión se lee en el arranque de la app; acá la pantalla va sola: se lee al activar.
        await tester.tap(_activar);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text(textoToast), findsOneWidget);
      },
    );

    testWidgets('«Activar» y «No permitir»: pasa a bloqueadas con «Abrir ajustes del teléfono»', (
      tester,
    ) async {
      final telefono = Telefono();
      telefono.sistema.respuestaAlPedir = false;
      await _abrir(tester, telefono);

      await tester.tap(_activar);
      await tester.pumpAndSettle();

      expect(_bloqueadas, findsOneWidget);
      expect(_abrirAjustes, findsOneWidget);
      expect(toastActivadas, findsNothing);
    });

    testWidgets('dos toques seguidos en «Activar» muestran el diálogo una sola vez', (
      tester,
    ) async {
      final telefono = Telefono();
      final abierto = telefono.sistema.dialogoAbierto = Completer<void>();
      await _abrir(tester, telefono);

      await tester.tap(_activar);
      await tester.pump();
      expect(tester.widget<TextButton>(_activar).onPressed, isNull);
      await tester.tap(_activar, warnIfMissed: false);
      await tester.pump();

      expect(telefono.sistema.pedidos, 1);
      abierto.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('si falla a mitad lo dice, «Activar» vuelve a estar disponible y reintenta', (
      tester,
    ) async {
      final telefono = Telefono();
      telefono.sistema.fallaAlPedir = true;
      await _abrir(tester, telefono);

      await tester.tap(_activar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(_fallo, findsOneWidget);
      expect(find.text('No pudimos pedir el permiso. Probá de nuevo.'), findsOneWidget);
      expect(tester.widget<TextButton>(_activar).onPressed, isNotNull);

      telefono.sistema.fallaAlPedir = false;
      await tester.tap(_activar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(_fallo, findsNothing);
      expect(_interruptor, findsOneWidget);
    });
  });

  group('error al leer', () {
    testWidgets(
      'si el sistema no contesta lo dice y ofrece «Reintentar»; reintentar vuelve a leer',
      (tester) async {
        final telefono = Telefono();
        telefono.sistema.fallaAlLeer = true;
        await _abrir(tester, telefono);

        expect(_error, findsOneWidget);
        expect(find.text('No pudimos revisar las notificaciones.'), findsOneWidget);
        expect(_activar, findsNothing);

        telefono.sistema.fallaAlLeer = false;
        await tester.tap(_reintentar);
        await tester.pumpAndSettle();

        expect(_error, findsNothing);
        expect(_apagadas, findsOneWidget);
      },
    );

    testWidgets('si sigue fallando, «Reintentar» sigue ahí y no queda cargando para siempre', (
      tester,
    ) async {
      final telefono = Telefono();
      telefono.sistema.fallaAlLeer = true;
      await _abrir(tester, telefono);

      await tester.tap(_reintentar);
      await tester.pumpAndSettle();

      expect(_error, findsOneWidget);
      expect(_cargando, findsNothing);
    });
  });

  group('la entrada desde Configuración', () {
    testWidgets(
      'la fila «Notificaciones» de Configuración abre esta pantalla y se vuelve con «Volver»',
      (tester) async {
        final telefono = Telefono(estado: EstadoSistemaNotificaciones.activadas);
        await abrirPantalla(tester, telefono, const ConfiguracionPage());

        await tester.tap(find.byKey(const Key('configuracion_notificaciones')));
        await tester.pumpAndSettle();
        expect(paginaNotificaciones, findsOneWidget);

        await tester.tap(find.byKey(const Key('notificaciones_atras')));
        await tester.pumpAndSettle();
        expect(paginaNotificaciones, findsNothing);
        expect(find.byKey(const Key('configuracion_pagina')), findsOneWidget);
      },
    );
  });

  group('casos límite', () {
    for (final (nombre, tamano, texto) in [
      ('texto al 200 %', const Size(390, 844), 2.0),
      ('texto al 300 % en un teléfono chico', const Size(320, 568), 3.0),
    ]) {
      for (final (estado, telefono) in [
        ('bloqueadas', _bloqueado()),
        ('apagadas', Telefono()),
        ('error', Telefono()..sistema.fallaAlLeer = true),
      ]) {
        testWidgets('$estado con $nombre: no se corta nada y el botón se alcanza', (tester) async {
          fijarTamano(tester, tamano: tamano, texto: texto);
          await _abrir(tester, telefono);

          expect(tester.takeException(), isNull);
          final boton = switch (estado) {
            'bloqueadas' => _abrirAjustes,
            'apagadas' => _activar,
            _ => _reintentar,
          };
          await tester.ensureVisible(boton);
          await tester.pump();
          expect(tester.getRect(boton).bottom, lessThanOrEqualTo(tamano.height));
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('cumple las guías de accesibilidad de Flutter con las notificaciones bloqueadas', (
      tester,
    ) async {
      await _abrir(tester, _bloqueado());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
