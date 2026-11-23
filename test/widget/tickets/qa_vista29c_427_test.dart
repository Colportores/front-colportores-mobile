// QA de «Foto del ticket de tarjeta» (vista 29 C, HU-COB-007, #427, PR #601): cada artboard del canvas
// (29C-01 a 29C-08 y 29A-03) y los estados que el canvas no dibuja, a 360x640 y 412x915 con texto 1,0
// y 2,0: sin desbordes y con las guías de toque (Android, iOS y rótulo); los casos límite de las
// entradas y de volver atrás. Los que documentan un hallazgo llevan `skip` con su motivo (el contraste
// va en `qa_vista29c_427_contraste_test.dart`; las capturas, en `..._capturas_test.dart`).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tickets/presentation/pages/ticket_de_tarjeta_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/qa_vista29c_427_arnes.dart';
import '../../helpers/ticket_tarjeta_arnes.dart';
import '../../helpers/tickets_falsos.dart';

/// Con `QA_HALLAZGOS=true` se corren también los tests de los hallazgos (los que llevan `skip`).
const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

void main() {
  group('Estados del canvas · tamaños, escalas y guías de toque', () {
    for (final estado in Estado427.values) {
      for (final tam in tamanos) {
        for (final escala in escalas) {
          testWidgets(
            '${estado.artboard} ${estado.rotulo} · ${tam.nombre} · texto ${escala.toStringAsFixed(1)}',
            (tester) async {
              final semantica = tester.ensureSemantics();
              await llevarAlEstado427(tester, estado, tamano: tam, escala: escala);
              await tester.pump(const Duration(milliseconds: 400));
              expect(tester.takeException(), isNull, reason: 'sin desbordes');
              await _guias(tester);

              // Lo de abajo de una lista perezosa no está armado hasta bajar.
              await irAlFinal427(tester);
              expect(tester.takeException(), isNull, reason: 'sin desbordes al final');
              await _guias(tester);
              semantica.dispose();
            },
          );
        }
      }
    }
  });

  group('29A-03 · Tarjeta registrada con foto · tamaños, escalas y guías', () {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets('${tam.nombre} · texto ${escala.toStringAsFixed(1)}', (tester) async {
          final semantica = tester.ensureSemantics();
          await llevarA29A03(tester, tamano: tam, escala: escala);
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Cobro registrado'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _guias(tester);
          await irAlFinal427(tester);
          expect(tester.takeException(), isNull);
          await _guias(tester);
          semantica.dispose();
        });
      }
    }
  });

  group('Entradas de «Datos del ticket»', () {
    testWidgets('una autorización de solo espacios no habilita el envío y dice qué falta', (
      tester,
    ) async {
      await llevarAlEstado427(tester, Estado427.datos);
      await escribir427(tester, campoAutorizacion, '      ');

      expect(elBotonPrincipal(tester).onPressed, isNull);
      expect(find.text('Falta el número de autorización.'), findsWidgets);
    });

    testWidgets('un monto de solo espacios se trata como vacío', (tester) async {
      await llevarAlEstado427(tester, Estado427.datos);
      await escribir427(tester, campoMontoTicket, '   ');

      expect(elBotonPrincipal(tester).onPressed, isNull);
      expect(find.text('Ingresá el monto del ticket.'), findsWidgets);
    });

    testWidgets('un monto en cero o negativo no habilita el envío', (tester) async {
      await llevarAlEstado427(tester, Estado427.datos);
      for (final texto in ['0', '0,00', '-5']) {
        await escribir427(tester, campoMontoTicket, texto);
        expect(elBotonPrincipal(tester).onPressed, isNull, reason: 'monto «$texto»');
      }
    });

    testWidgets('un monto con letras o símbolos no habilita el envío', (tester) async {
      await llevarAlEstado427(tester, Estado427.datos);
      for (final texto in ['abc', '12a', r'$$', '1.2.3,4,5']) {
        await escribir427(tester, campoMontoTicket, texto);
        expect(elBotonPrincipal(tester).onPressed, isNull, reason: 'monto «$texto»');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('un texto muy largo pegado en el monto y en la autorización se corta', (
      tester,
    ) async {
      await llevarAlEstado427(tester, Estado427.datos);
      await escribir427(tester, campoMontoTicket, '1' * 300);
      await escribir427(tester, campoAutorizacion, 'A' * 500);

      expect(
        tester.widget<TextField>(campoMontoTicket).controller!.text.length,
        lessThanOrEqualTo(14),
      );
      expect(
        tester.widget<TextField>(campoAutorizacion).controller!.text.length,
        lessThanOrEqualTo(40),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('caracteres especiales y emoji en la autorización se guardan tal cual', (
      tester,
    ) async {
      final a = await llevarAlEstado427(tester, Estado427.datos);
      await escribir427(tester, campoAutorizacion, 'Ñ-ü/9 😀');
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

      expect(a.repo.recibidos.single.ticket.numeroAutorizacion, 'Ñ-ü/9 😀');
    });

    testWidgets('la autorización se guarda sin los espacios de los bordes', (tester) async {
      final a = await llevarAlEstado427(tester, Estado427.datos);
      await escribir427(tester, campoAutorizacion, '   004512  ');
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

      expect(a.repo.recibidos.single.ticket.numeroAutorizacion, '004512');
    });

    testWidgets('el monto con coma decimal y con punto de miles se interpreta bien', (
      tester,
    ) async {
      final a = await llevarAlEstado427(tester, Estado427.datos);
      await escribir427(tester, campoMontoTicket, '1.234,50');
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

      expect(a.repo.recibidos.single.ticket.montoCentavos, 123450);
    });

    testWidgets('«Otra» marca con solo espacios se guarda como «Otra», no vacía', (tester) async {
      final a = await llevarAlEstado427(tester, Estado427.datosMarcaOtra);
      final otra = find.descendant(
        of: find.byKey(const Key('ticket_marca_otra')),
        matching: find.byType(TextField),
      );
      await escribir427(tester, otra, '     ');
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

      expect(a.repo.recibidos.single.ticket.tarjetaMarca, 'Otra');
    });

    testWidgets('después de una falla al guardar lo tipeado no se pierde', (tester) async {
      final a = await llevarAlEstado427(tester, Estado427.datos);
      a.repo.fallas.add(const FailureTicketNoGuardado(causa: 'prueba'));
      await escribir427(tester, campoMontoTicket, '1350');
      await escribir427(tester, campoAutorizacion, 'XJ-7781');
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

      expect(find.byKey(const Key('ticket_error')), findsOneWidget);
      expect(tester.widget<TextField>(campoMontoTicket).controller!.text, '1350');
      expect(tester.widget<TextField>(campoAutorizacion).controller!.text, 'XJ-7781');
      expect(elBotonPrincipal(tester).onPressed, isNotNull);

      // Y el reintento manda lo mismo, con el mismo id.
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));
      expect(a.repo.recibidos, hasLength(2));
      expect(a.repo.recibidos.last.ticket.id, a.repo.recibidos.first.ticket.id);
      expect(a.repo.recibidos.last.ticket.numeroAutorizacion, 'XJ-7781');
    });

    testWidgets(
      'QA #427 hallazgo H2: una autorización de 21 emoji (42 unidades UTF-16 > 40) entra en el campo '
      'pero el caso de uso la rechaza y la pantalla queda sin salida',
      (tester) async {
        final a = await llevarAlEstado427(tester, Estado427.datos);
        await escribir427(tester, campoAutorizacion, '😀' * 21);
        await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

        // El campo la acepta (21 < 40 puntos de código); si el caso de uso la rechaza por contar
        // unidades UTF-16 (42 > 40), la pantalla muestra un error sin salida: «probá de nuevo» no
        // alcanza, el reintento falla igual.
        expect(a.repo.recibidos, hasLength(1), reason: 'el caso de uso la dejó pasar');
        expect(find.byKey(const Key('ticket_error')), findsNothing);
      },
      skip: !_conHallazgos,
    );
  });

  group('Foto rechazada · texto literal de la decisión del 04/11', () {
    testWidgets(
      'dice que avise a la coordinadora y que cuando lo rechace lo carga de nuevo, sin «Reintentar»',
      (tester) async {
        await llevarAlEstado427(tester, Estado427.rechazada);

        expect(
          find.text(
            'No pudimos subir la foto de este ticket. Avisale a tu coordinadora: cuando lo '
            'rechace, lo cargás de nuevo.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Reintentar'), findsNothing);
      },
    );
  });

  group('Volver atrás en cada paso (botón del sistema)', () {
    testWidgets('en la cámara cierra el flujo como cancelado', (tester) async {
      final a = await llevarAlEstado427(tester, Estado427.camara);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(a.resultados, [ResultadoDelFlujoDeTicket.cancelado]);
    });

    testWidgets('en la vista previa vuelve a la cámara y descarta la foto', (tester) async {
      await llevarAlEstado427(tester, Estado427.vistaPrevia);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(find.byKey(const Key('ticket_sacar_foto')), findsOneWidget);
      expect(find.byKey(const Key('ticket_foto')), findsNothing);
    });

    testWidgets('en los datos vuelve a la vista previa y conserva lo escrito al seguir', (
      tester,
    ) async {
      await llevarAlEstado427(tester, Estado427.datos);
      await escribir427(tester, campoAutorizacion, 'ZZ-99');
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);

      await tocarTicket(tester, find.byKey(const Key('ticket_se_lee_bien')));
      expect(tester.widget<TextField>(campoAutorizacion).controller!.text, 'ZZ-99');
    });

    testWidgets('mientras se prepara la foto no hace nada y no la pierde', (tester) async {
      final a = await llevarAlEstado427(tester, Estado427.preparando);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(a.resultados, isEmpty);
      expect(find.text('Preparando la foto…'), findsWidgets);
    });

    testWidgets('mientras sube cierra con el ticket cargado y la cola sigue', (tester) async {
      final a = await llevarAlEstado427(tester, Estado427.subiendo);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(a.resultados, [ResultadoDelFlujoDeTicket.cargado]);
      expect(a.repo.actual, isNotNull, reason: 'el ticket quedó guardado en el teléfono');
    });

    testWidgets('en el permiso denegado cierra el flujo como cancelado', (tester) async {
      final a = await llevarAlEstado427(tester, Estado427.sinPermiso);
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(a.resultados, [ResultadoDelFlujoDeTicket.cancelado]);
    });
  });

  group('Acciones superpuestas y reentrada', () {
    testWidgets('con la cámara en curso, la galería no responde y no abre otra captura', (
      tester,
    ) async {
      final a = await llevarAlEstado427(tester, Estado427.camara);
      a.capturador.compuerta = Completer<void>();
      await tester.tap(find.byKey(const Key('ticket_sacar_foto')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ticket_galeria')));
      await tester.pump();

      expect(a.capturador.vecesCamara, 1);
      expect(a.capturador.vecesGaleria, 0);

      a.capturador.compuerta!.complete();
      await asentarAgendar(tester);
      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);
    });

    testWidgets('«Sacar otra» y volver a sacar deja una sola foto y un solo ticket al enviar', (
      tester,
    ) async {
      final a = await llevarAlEstado427(tester, Estado427.vistaPrevia);
      await tocarTicket(tester, find.byKey(const Key('ticket_sacar_otra')));
      await tocarTicket(tester, find.byKey(const Key('ticket_sacar_foto')));
      await tocarTicket(tester, find.byKey(const Key('ticket_se_lee_bien')));
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));

      expect(a.repo.recibidos, hasLength(1));
      expect(a.idsGenerados, hasLength(1));
    });

    testWidgets('la captura que falla a mitad deja «Sacar foto» habilitado para reintentar', (
      tester,
    ) async {
      final a = await llevarAlEstado427(tester, Estado427.camara);
      a.capturador.camara
        ..clear()
        ..addAll([const CapturaFallida(), FotoCapturada(fotoDePrueba(4000))]);
      await tocarTicket(tester, find.byKey(const Key('ticket_sacar_foto')));
      expect(find.byKey(const Key('ticket_aviso_captura')), findsOneWidget);

      await tocarTicket(tester, find.byKey(const Key('ticket_sacar_foto')));
      expect(find.text('¿Se lee bien el ticket?'), findsOneWidget);
      expect(find.byKey(const Key('ticket_aviso_captura')), findsNothing);
    });

    testWidgets('el aviso de error al subir se anuncia como región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await llevarAlEstado427(tester, Estado427.errorAlSubir);

      final datos = tester.getSemantics(find.byKey(const Key('ticket_error_subida')));
      expect(datos, isSemantics(isLiveRegion: true));
      semantica.dispose();
    });

    testWidgets('el aviso de la falla al guardar se anuncia y trae «Reintentar» a mano', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await llevarAlEstado427(tester, Estado427.datosFallaAlGuardar);

      final datos = tester.getSemantics(find.byKey(const Key('ticket_error')));
      expect(datos, isSemantics(isLiveRegion: true));
      expect(find.text('Reintentar'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('Privacidad', () {
    test('el toString de lo que guarda el ticket no imprime la autorización ni el monto', () {
      final r = ticketDePrueba('tk-pii', autorizacion: 'SECRETO-8841', monto: 987654);
      expect(r.toString(), isNot(contains('SECRETO-8841')));
      expect(r.toString(), isNot(contains('987654')));
    });
  });

  group('Estados sin conexión', () {
    testWidgets('sin red desde el principio, el envío lleva a la cola con el aviso del canvas', (
      tester,
    ) async {
      final a = await llevarAlEstado427(tester, Estado427.datos);
      a.conexion.cambiarA(TipoConexion.sinConexion);
      await tocarTicket(tester, find.byKey(const Key('ticket_enviar')));
      await asentarAgendar(tester);

      expect(find.text('Ticket guardado'), findsOneWidget);
      expect(find.text('En cola'), findsOneWidget);
    });
  });
}
