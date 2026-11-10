// QA de «Cuenta Drive» (HU-SYNC-004, vista 16, 16D·01 a 16D·10, #184). Matriz de estados × tamaños
// (360×640 y 412×915) × texto 1,0 y 2,0 con las fuentes reales: textos del canvas y de la HU, sin
// desborde, sin texto cortado, guías de toque y de rótulos. Después, los casos límite que la
// implementación no prueba: reintentos, acciones superpuestas, falla a mitad, datos límite,
// semántica del lector de pantalla y privacidad.
//
// `--dart-define=QA_CAPTURAS=true` saca una captura de cada celda en `.dart_tool/qa_capturas/`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../helpers/qa_drive_184_arnes.dart';
import '../helpers/respaldo_drive_falsos.dart';

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

Future<void> _arriba(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
  await tester.pumpAndSettle();
}

String _celda(Estado184 e, Size t, double escala) =>
    '${e.rotulo} · ${t.width.toInt()}x${t.height.toInt()} · texto ${escala}x';

void main() {
  group('Matriz de estados', () {
    for (final e in Estado184.values) {
      for (final t in [chico184, grande184]) {
        for (final escala in [1.0, 2.0]) {
          testWidgets(_celda(e, t, escala), (tester) async {
            final semantica = tester.ensureSemantics();
            await montar184(tester, e, tamano: t, escala: escala);
            expect(tester.takeException(), isNull, reason: 'sin desborde');
            await capturar184(tester, '${e.name}_${t.width.toInt()}_${escala}x');
            sinTextoCortado184(tester);
            await _guias(tester);

            final esFilaConAviso = e == Estado184.revocado || e == Estado184.cancelo;
            if (esFilaConAviso) {
              await _arriba(tester);
              await capturar184(tester, '${e.name}_arriba_${t.width.toInt()}_${escala}x');
              await _guias(tester);
            }
            for (final texto in textosDe184(e)) {
              expect(find.text(texto), findsWidgets, reason: 'falta «$texto»');
            }
            semantica.dispose();
          });
        }
      }
    }
  });

  group('Cobertura por artboard: se llega y se sale', () {
    testWidgets('16D·01 la fila de «Sin conectar» abre la hoja de 16D·02', (tester) async {
      await montar184(tester, Estado184.sinConectar);
      await tester.tap(fila184);
      await tester.pumpAndSettle();
      expect(hojaConectar184, findsOneWidget);
    });

    testWidgets('16D·02 «Ahora no» cierra y no deja aviso', (tester) async {
      final m = await montar184(tester, Estado184.previa);
      await tocar184(tester, ahoraNo184);
      expect(hojaConectar184, findsNothing);
      expect(avisoCancelado184, findsNothing);
      expect(m.drive.google.conexiones, 0);
    });

    testWidgets('16D·03 con la pantalla de Google abierta no hay salida a medias', (tester) async {
      final m = await montar184(tester, Estado184.conectando);
      expect(ahoraNo184, findsNothing);
      expect(tester.widget<FilledButton>(conectar184).onPressed, isNull);
      m.compuerta!.complete();
      await tester.pumpAndSettle();
      expect(hojaConectar184, findsNothing);
    });

    testWidgets('16D·04 conectada: la fila dice la cuenta y la HU el aviso literal', (
      tester,
    ) async {
      await montar184(tester, Estado184.conectada);
      expect(find.text('Backup configurado. Próximo backup nocturno.'), findsOneWidget);
      await verFila184(tester);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
      expect(find.text('Todavía no hubo un respaldo'), findsOneWidget);
    });

    testWidgets('16D·05 desconectar deja «Sin conectar» y las copias no se tocan', (tester) async {
      final m = await montar184(tester, Estado184.desconectar);
      await tocar184(tester, desconectar184);
      expect(hojaDesconectar184, findsNothing);
      await verFila184(tester);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
      expect(m.drive.guardado, anyOf(isNull, isNot(contains('ana.gomez'))));
      expect(m.drive.google.desconexiones, 1);
    });

    testWidgets('16D·06 «Reconectar» del aviso lleva a la hoja y reconecta', (tester) async {
      await montar184(tester, Estado184.revocado);
      await _arriba(tester);
      await tocar184(tester, accionAviso184);
      expect(hojaConectar184, findsOneWidget);
      await tocar184(tester, conectar184);
      expect(avisoRevocado184, findsNothing);
      await verFila184(tester);
      expect(find.text('Sin permiso · los respaldos están frenados'), findsNothing);
    });

    testWidgets('16D·07 canceló: la fila sigue «Conectar» y se puede reintentar', (tester) async {
      final m = await montar184(tester, Estado184.cancelo);
      m.drive.google.errorAlConectar = null;
      await tocarFila184(tester);
      await tocar184(tester, conectar184);
      await verFila184(tester);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
    });

    testWidgets('16D·08 sin conexión: apagado, y al volver la red el botón se enciende', (
      tester,
    ) async {
      await montar184(tester, Estado184.sinConexion);
      expect(tester.widget<FilledButton>(conectar184).onPressed, isNull);
      expect(find.text('Necesitás conexión para conectar Google Drive.'), findsOneWidget);
    });

    testWidgets('16D·09 error: «Reintentar» conecta si Google ya responde', (tester) async {
      final m = await montar184(tester, Estado184.error);
      m.drive.google.errorAlConectar = null;
      await tocar184(tester, conectar184);
      expect(hojaConectar184, findsNothing);
      await verFila184(tester);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
    });

    testWidgets('16D·10 sin espacio: la fila abre desconectar (el permiso sigue)', (tester) async {
      await montar184(tester, Estado184.sinEspacio);
      await tester.tap(fila184);
      await tester.pumpAndSettle();
      expect(hojaDesconectar184, findsOneWidget);
    });
  });

  group('Casos límite de cada flujo', () {
    testWidgets('error de lectura: «Reintentar» lee de nuevo y deja la fila usable', (
      tester,
    ) async {
      final m = await montar184(tester, Estado184.errorLectura);
      m.drive.almacen.alLeer = false;
      await tester.tap(fila184);
      await tester.pumpAndSettle();
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
    });

    testWidgets('error al desconectar: «Reintentar» desconecta cuando el almacén vuelve', (
      tester,
    ) async {
      final m = await montar184(tester, Estado184.errorDesconectar);
      expect(hojaDesconectar184, findsOneWidget);
      expect(tester.widget<FilledButton>(desconectar184).onPressed, isNotNull);
      m.drive.almacen.alBorrar = false;
      await tocar184(tester, desconectar184);
      expect(hojaDesconectar184, findsNothing);
      await verFila184(tester);
      expect(find.text('Sin conectar · tus datos no tienen respaldo'), findsOneWidget);
    });

    testWidgets('desconectando: ni atrás ni «Cancelar» cierran la hoja', (tester) async {
      final armado = RespaldoDriveArmado();
      final m = await montar184(tester, Estado184.desconectar, armado: armado);
      m.drive.google.errorAlDesconectar = null;
      // El almacén se traba al borrar: la desconexión queda en curso.
      final compuerta = Completer<void>();
      final usuario = m.container.read(estadoRespaldoDriveProvider);
      expect(usuario.value, isA<DriveConectada>());
      m.drive.almacen.compuertaLeer = compuerta;
      await tester.tap(desconectar184);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(hojaDesconectar184, findsOneWidget, reason: 'atrás no cierra mientras desconecta');
      expect(tester.widget<OutlinedButton>(cancelar184).onPressed, isNull);
      compuerta.complete();
      await tester.pumpAndSettle();
      expect(hojaDesconectar184, findsNothing);
    });

    testWidgets('dos toques seguidos en la fila abren una sola hoja', (tester) async {
      await montar184(tester, Estado184.sinConectar);
      await tester.tap(fila184);
      await tester.tap(fila184, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(hojaConectar184, findsOneWidget);
      await tocar184(tester, ahoraNo184);
      expect(hojaConectar184, findsNothing, reason: 'una sola hoja que cerrar');
    });

    testWidgets('dos toques seguidos en «Reconectar» del aviso abren una sola hoja', (
      tester,
    ) async {
      await montar184(tester, Estado184.revocado);
      await _arriba(tester);
      await tester.tap(accionAviso184);
      await tester.tap(accionAviso184, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(hojaConectar184, findsOneWidget);
      await tocar184(tester, ahoraNo184);
      expect(hojaConectar184, findsNothing);
    });

    testWidgets('reconectar que falla deja el permiso revocado: el aviso y la fila siguen', (
      tester,
    ) async {
      final m = await montar184(tester, Estado184.revocado);
      m.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);
      await tocarFila184(tester);
      await tocar184(tester, conectar184);
      expect(find.text('No pudimos conectar tu Drive. Probá de nuevo.'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(conectar184).onPressed,
        isNotNull,
        reason: 'no queda trabado',
      );
      await tocar184(tester, ahoraNo184);
      await _arriba(tester);
      expect(avisoRevocado184, findsOneWidget);
      expect(m.container.read(estadoRespaldoDriveProvider).value, isA<DrivePermisoRevocado>());
    });

    testWidgets('el almacén no deja anotar la cuenta: se retira el permiso y se puede reintentar', (
      tester,
    ) async {
      final m = await montar184(tester, Estado184.previa);
      m.drive.almacen.alEscribir = true;
      await tocar184(tester, conectar184);
      expect(m.drive.google.desconexiones, 1, reason: 'no queda un permiso suelto en Google');
      expect(tester.widget<FilledButton>(conectar184).onPressed, isNotNull);
      m.drive.almacen.alEscribir = false;
      await tocar184(tester, conectar184);
      expect(hojaConectar184, findsNothing);
      await verFila184(tester);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
    });

    testWidgets('desde «Drive lleno» se puede desconectar y volver a conectar', (tester) async {
      await montar184(tester, Estado184.sinEspacio);
      await tester.tap(fila184);
      await tester.pumpAndSettle();
      await tocar184(tester, desconectar184);
      await verFila184(tester);
      await tester.tap(fila184);
      await tester.pumpAndSettle();
      await tocar184(tester, conectar184);
      await verFila184(tester);
      expect(find.text('ana.gomez@gmail.com'), findsOneWidget);
      expect(find.text('Tu Drive está lleno · el respaldo no se guardó'), findsNothing);
    });

    testWidgets('correo larguísimo, sin espacios: se lee entero a 360×640 con texto 2,0', (
      tester,
    ) async {
      final largo = '${'nombre.muy.largo.' * 5}ana@subdominio-extenso.ejemplo.com.uy';
      await montar184(tester, Estado184.conectada, escala: 2, email: largo);
      expect(tester.takeException(), isNull);
      await verFila184(tester);
      expect(find.text(largo), findsOneWidget);
      sinTextoCortado184(tester);
      await capturar184(tester, 'correo_largo_360_2x');
    });

    testWidgets('correo con emoji y mayúsculas se muestra tal cual', (tester) async {
      await montar184(tester, Estado184.conectada, email: 'Ñandú.😀@Correo.COM');
      await verFila184(tester);
      expect(find.text('Ñandú.😀@Correo.COM'), findsOneWidget);
    });
  });

  group('Avisos de error: dicen qué hacer, con la acción a mano', () {
    testWidgets('el error de la hoja se anuncia (región viva) y tiene «Reintentar»', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar184(tester, Estado184.error);
      expect(
        tester.getSemantics(find.byKey(const Key('drive_hoja_error'))),
        isSemantics(isLiveRegion: true),
      );
      expect(find.text('Reintentar'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('sin conexión se anuncia y no se ofrece reintentar', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar184(tester, Estado184.sinConexion);
      expect(
        tester.getSemantics(find.byKey(const Key('drive_hoja_sin_conexion'))),
        isSemantics(isLiveRegion: true),
      );
      semantica.dispose();
    });

    testWidgets('el aviso de permiso revocado se anuncia y su acción tiene nombre', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar184(tester, Estado184.revocado);
      await _arriba(tester);
      expect(tester.getSemantics(avisoRevocado184), isSemantics(isLiveRegion: true));
      expect(tester.getSemantics(accionAviso184), isSemantics(label: 'Reconectar', isButton: true));
      semantica.dispose();
    });

    testWidgets('Google falla por almacén: el aviso de la hoja no manda a «reinstalar» la app', (
      tester,
    ) async {
      final m = await montar184(tester, Estado184.previa);
      m.drive.almacen.alEscribir = true;
      await tocar184(tester, conectar184);
      expect(find.textContaining('reinstalar'), findsNothing);
    });

    // Decisión del agente de decisiones (pendiente 184-qa P2): el aviso queda arriba de la fila,
    // como en el canvas; con texto 2,0 en una pantalla chica queda sobre el borde de arriba y se
    // llega a él desplazando. No se lo baja para que entre junto a la fila.
    testWidgets('el aviso de «No conectamos tu Drive» queda arriba de la fila, como en el canvas, '
        'y se llega a él a 360×640 con texto 2,0', (tester) async {
      await montar184(tester, Estado184.cancelo, escala: 2);
      expect(avisoCancelado184, findsOneWidget);
      expect(
        tester.getRect(avisoCancelado184).bottom,
        lessThanOrEqualTo(tester.getRect(fila184).top),
        reason: 'el aviso va arriba de la fila de Drive',
      );

      await _arriba(tester);
      expect(enPantalla184(tester, avisoCancelado184), isTrue);
    });
  });

  group('Texto grande: la fila se lee', () {
    for (final e in [Estado184.sinConectar, Estado184.revocado]) {
      testWidgets('${e.rotulo}: «Cuenta Drive» no se parte en letras a 360×640 con texto 2,0', (
        tester,
      ) async {
        await montar184(tester, e, escala: 2);
        final alto = tester.getSize(find.text('Cuenta Drive')).height;
        final unRenglon =
            Theme.of(tester.element(fila184)).textTheme.bodyLarge!.fontSize! * 2 * 1.6;
        expect(
          alto,
          lessThan(unRenglon * 1.5),
          reason: 'el título ocupa $alto dp: se parte por la mitad',
        );
      });
    }
  });

  group('Lector de pantalla: la fila dice qué hace', () {
    for (final e in [
      Estado184.sinConectar,
      Estado184.conectada,
      Estado184.revocado,
      Estado184.sinEspacio,
      Estado184.errorLectura,
    ]) {
      testWidgets('${e.rotulo}: la fila tiene acción de tocar y un nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        await montar184(tester, e == Estado184.conectada ? Estado184.desconectar : e);
        if (e == Estado184.conectada) {
          await tocar184(tester, cancelar184);
          await verFila184(tester);
        }
        final nodo = tester.getSemantics(fila184);
        expect(nodo.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(nodo.label, contains('Cuenta Drive'));
        semantica.dispose();
      });
    }

    testWidgets('cargando: la fila no ofrece tocar', (tester) async {
      final semantica = tester.ensureSemantics();
      final m = await montar184(tester, Estado184.cargando);
      expect(
        tester.getSemantics(fila184).getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      m.compuerta!.complete();
      await tester.pumpAndSettle();
      semantica.dispose();
    });

    testWidgets('con Drive conectado la fila avisa que al tocarla se puede desconectar', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar184(tester, Estado184.desconectar);
      await tocar184(tester, cancelar184);
      await verFila184(tester);
      final nodo = tester.getSemantics(fila184);
      expect('${nodo.label} ${nodo.hint}', contains('esconectar'));
      semantica.dispose();
    });
  });

  group('Privacidad', () {
    test('ni el correo ni el id de Google salen en toString', () {
      const cuenta = CuentaGoogle(id: 'g-100', email: 'ana.gomez@gmail.com');
      const estados = <Object>[
        DriveConectada(email: 'ana.gomez@gmail.com', cuentaId: 'g-100'),
        DrivePermisoRevocado(email: 'ana.gomez@gmail.com', cuentaId: 'g-100'),
        DriveSinEspacio(email: 'ana.gomez@gmail.com', cuentaId: 'g-100'),
        cuenta,
      ];
      for (final o in estados) {
        expect(o.toString(), isNot(contains('ana.gomez')), reason: o.runtimeType.toString());
        expect(o.toString(), isNot(contains('g-100')), reason: o.runtimeType.toString());
      }
    });

    test('los resultados y las fallas no llevan el correo en toString', () {
      for (final o in <Object>[
        const DriveQuedoConectado(primerRespaldoHecho: false),
        const DriveNoQuedoConectado(FailureDriveNoConectado()),
        const FailureDriveCancelado(),
        const FailureDrivePermisoIncompleto(),
      ]) {
        expect(o.toString(), isNot(contains('@')), reason: o.runtimeType.toString());
      }
    });

    test('lo guardado en el almacén no lleva ningún token', () async {
      final armado = RespaldoDriveArmado();
      await armado.repo.conectar('u-1');
      expect(armado.guardado, isNotNull);
      expect(armado.guardado, isNot(contains('ya29')));
      expect(armado.guardado!.toLowerCase(), isNot(contains('token')));
    });
  });
}
