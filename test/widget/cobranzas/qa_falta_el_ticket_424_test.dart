// QA de #424 («Falta el ticket» en el detalle del cobro, vista 30 B): la marca en cada estado y
// tamaño (360×640 y 412×915, letra 1,0 y 2,0), el texto literal de las decisiones P1 a P3, las
// salidas del flujo de la foto (cámara cerrada, ticket guardado, cobro anulado o borrado mientras
// tanto) y los toques superpuestos. Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`
// y van a `.dart_tool/qa_capturas/` (fuera de git).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/detalle_del_cobro.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/textos_medio_de_cobro.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/anular_cobro_arnes.dart';
import '../../helpers/qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408;
import '../../helpers/ticket_tarjeta_arnes.dart';

const _chico = Size(360, 640);
const _grande = Size(412, 915);
const _textoMarca =
    'Falta el ticket. Guardá el ticket de la tarjeta: tu coordinador te lo va a pedir.';

final _marca = find.byKey(const Key('detalle_cobro_falta_ticket'));
final _accion = find.descendant(of: _marca, matching: find.byKey(const Key('venta_aviso_accion')));
final _atrasDelTicket = find.descendant(
  of: paginaTicket,
  matching: find.byKey(const Key('venta_atras')),
);

DetalleDelCobro _tarjeta({String? ticketId, DateTime? anuladoAt, DateTime? fecha}) =>
    detalleDeEjemplo(
      medio: MedioCobranza.tarjeta,
      ticketId: ticketId,
      numeroAprobacion: '004512',
      anuladoAt: anuladoAt,
      motivo: anuladoAt == null ? null : MotivoDeAnulacion.montoEquivocado,
      fecha: fecha,
    );

Future<({ArnesAnular detalle, ArnesTicket ticket})> _montar(
  WidgetTester tester, {
  AnulacionesEnMemoria? repo,
  bool conCamara = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
  DateTime? ahora,
}) async {
  await cargarFuentes408(tester);
  final ticket = nuevoArnesTicket();
  final detalle = await montarDetalleDelCobro(
    tester,
    repo: repo ?? AnulacionesEnMemoria(cobros: [_tarjeta()]),
    overrides: overridesDeTicket(ticket, conCamara: conCamara),
    escala: escala,
    tamano: tamano,
    ahora: ahora,
  );
  return (detalle: detalle, ticket: ticket);
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/424_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void _sinTextoCortado(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

enum _Estado {
  conCamara('marca con camara'),
  sinCamara('marca sin camara'),
  fueraDePlazo('marca pasadas las 72 h'),
  ayer('marca cobro de ayer');

  const _Estado(this.rotulo);
  final String rotulo;
}

Future<void> _llegarA(WidgetTester tester, _Estado e, Size tamano, double escala) => _montar(
  tester,
  repo: AnulacionesEnMemoria(
    cobros: [_tarjeta(fecha: e == _Estado.ayer ? DateTime.utc(2026, 10, 22, 12, 30) : null)],
  ),
  conCamara: e != _Estado.sinCamara,
  escala: escala,
  tamano: tamano,
  ahora: e == _Estado.fueraDePlazo ? DateTime.utc(2026, 10, 27) : null,
);

void main() {
  group('Falta el ticket · cada estado, tamaño y escala', () {
    for (final tamano in const [_chico, _grande]) {
      for (final escala in const [1.0, 2.0]) {
        for (final estado in _Estado.values) {
          final nombre =
              '${estado.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} x$escala';

          testWidgets('$nombre · se alcanza, sin desborde ni texto cortado', (tester) async {
            await _llegarA(tester, estado, tamano, escala);

            await traerAlAlcance(tester, _marca);
            expect(tester.takeException(), isNull);
            expect(
              find.textContaining('Falta el ticket. Guardá el ticket', findRichText: true),
              findsOneWidget,
            );
            _sinTextoCortado(tester);
            await _capturar(
              tester,
              '${estado.rotulo.replaceAll(' ', '_')}_${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala',
            );

            if (estado == _Estado.sinCamara) {
              expect(_accion, findsNothing);
            } else {
              await traerAlAlcance(tester, _accion);
              final t = tester.getSize(_accion);
              expect(t.height, greaterThanOrEqualTo(48), reason: 'alto de «Sacar foto del ticket»');
              expect(t.width, greaterThanOrEqualTo(48), reason: 'ancho de «Sacar foto del ticket»');
              // Y se puede tocar de verdad: abre la foto del ticket.
              await tester.tap(_accion);
              await asentarAgendar(tester);
              expect(paginaTicket, findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          });

          if (estado == _Estado.conCamara || estado == _Estado.ayer) {
            testWidgets('$nombre · «Anular cobro» sigue al alcance con la marca', (tester) async {
              await _llegarA(tester, estado, tamano, escala);

              expect(botonAnularDelDetalle, findsOneWidget);
              await tester.tap(botonAnularDelDetalle);
              await asentarAgendar(tester);
              expect(paginaAnular, findsOneWidget);
            });
          }
        }
      }
    }
  });

  group('Falta el ticket · lo que dice y lo que oye el lector', () {
    testWidgets('el texto es el de la decisión P1 y repite el aviso de 29A·02', (tester) async {
      await _montar(tester);

      expect(find.text(_textoMarca), findsOneWidget);
      // Mismo texto para el mismo caso: la segunda frase es la de 29A·02.
      expect(_textoMarca, endsWith(TextosMedioDeCobro.guardaElTicket));
      expect(find.text('Sacar foto del ticket'), findsOneWidget);
    });

    testWidgets('la marca se anuncia (región viva) y la acción tiene nombre y acción de toque', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await _montar(tester);

      final nodoMarca = tester.getSemantics(_marca);
      expect(nodoMarca.flagsCollection.isLiveRegion, isTrue);
      expect(
        tester.getSemantics(_accion),
        isSemantics(label: 'Sacar foto del ticket', isButton: true, hasTapAction: true),
      );
      h.dispose();
    });

    testWidgets('con la marca, el orden de lectura es marca, datos del cobro y «Anular cobro»', (
      tester,
    ) async {
      await _montar(tester);

      final yMarca = tester.getTopLeft(_marca).dy;
      final yFecha = tester.getTopLeft(find.byKey(const Key('detalle_cobro_fecha'))).dy;
      final yAnular = tester.getTopLeft(botonAnularDelDetalle).dy;
      expect(yMarca, lessThan(yFecha));
      expect(yFecha, lessThan(yAnular));
    });
  });

  group('Falta el ticket · salidas del flujo de la foto', () {
    testWidgets(
      'mientras estaba en la foto el cobro se anuló desde otro lado: al volver no hay marca',
      (tester) async {
        final a = await _montar(tester);

        await tocar(tester, find.text('Sacar foto del ticket'));
        expect(paginaTicket, findsOneWidget);
        a.detalle.repo.detalles['c-1'] = _tarjeta(anuladoAt: DateTime.utc(2026, 10, 23, 17, 30));
        await tocar(tester, _atrasDelTicket);
        for (var i = 0; i < 5 && paginaTicket.evaluate().isNotEmpty; i++) {
          await tocar(tester, _atrasDelTicket);
        }

        expect(paginaTicket, findsNothing);
        expect(_marca, findsNothing);
        expect(textoDe('detalle_cobro_estado'), 'Anulado · Monto equivocado');
        expect(botonAnularDelDetalle, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'mientras estaba en la foto el cobro desapareció: al volver dice que ya no está y sale',
      (tester) async {
        final a = await _montar(tester);

        await tocar(tester, find.text('Sacar foto del ticket'));
        a.detalle.repo.detalles.clear();
        for (var i = 0; i < 6 && paginaTicket.evaluate().isNotEmpty; i++) {
          await tocar(tester, _atrasDelTicket);
        }

        expect(find.byKey(const Key('detalle_cobro_ausente')), findsOneWidget);
        expect(_marca, findsNothing);
        await tocar(tester, find.text('Volver'));
        expect(paginaDetalle, findsNothing);
        expect(a.detalle.resultados, [false]);
      },
    );

    testWidgets(
      'falla dos veces seguidas al leer el cobro al volver: el error sale y «Reintentar» recupera',
      (tester) async {
        final a = await _montar(tester);

        await tocar(tester, find.text('Sacar foto del ticket'));
        a.detalle.repo.fallaDeLectura = const FailureCobroNoAnulado(causa: 'lectura');
        for (var i = 0; i < 6 && paginaTicket.evaluate().isNotEmpty; i++) {
          await tocar(tester, _atrasDelTicket);
        }
        expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsOneWidget);
        // Reintenta y vuelve a fallar: sigue el aviso con la acción, sin quedar «cargando».
        await tocar(tester, find.byKey(const Key('venta_aviso_accion')));
        expect(find.byKey(const Key('detalle_cobro_error_lectura')), findsOneWidget);
        // Ahora anda.
        a.detalle.repo.fallaDeLectura = null;
        await tocar(tester, find.byKey(const Key('venta_aviso_accion')));

        expect(_marca, findsOneWidget);
        expect(botonAnularDelDetalle, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('«Sacar foto» y «Anular cobro» en el mismo cuadro: se abre una sola pantalla', (
      tester,
    ) async {
      await _montar(tester);
      await traerAlAlcance(tester, _accion);

      await tester.tap(_accion);
      await tester.tap(botonAnularDelDetalle, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(paginaTicket, findsOneWidget);
      expect(paginaAnular, findsNothing);
      // Al volver queda el detalle, no la pantalla de anular debajo.
      for (var i = 0; i < 6 && paginaTicket.evaluate().isNotEmpty; i++) {
        await tocar(tester, _atrasDelTicket);
      }
      expect(paginaAnular, findsNothing);
      expect(paginaDetalle, findsOneWidget);
    });

    testWidgets(
      'volver a «Sacar foto» tras cerrar la cámara tres veces: siempre abre una sola y sigue la marca',
      (tester) async {
        final a = await _montar(tester);

        for (var i = 0; i < 3; i++) {
          await tocar(tester, find.text('Sacar foto del ticket'));
          expect(paginaTicket, findsOneWidget);
          for (var j = 0; j < 6 && paginaTicket.evaluate().isNotEmpty; j++) {
            await tocar(tester, _atrasDelTicket);
          }
          expect(paginaTicket, findsNothing);
          expect(_marca, findsOneWidget);
        }
        expect(a.ticket.repo.recibidos, isEmpty);
        expect(a.detalle.repo.lecturas, 4);
      },
    );

    testWidgets(
      'con el ticket guardado y volviendo con «atrás» (sin «Listo») la marca también se va',
      (tester) async {
        final a = await _montar(tester);

        await tocar(tester, find.text('Sacar foto del ticket'));
        await enviarElTicket(tester);
        a.detalle.repo.detalles['c-1'] = _tarjeta(
          ticketId: a.ticket.repo.recibidos.single.ticket.id,
        );
        // El «atrás» del sistema desde «Ticket guardado» cierra con «cargado».
        await tester.binding.handlePopRoute();
        await asentarAgendar(tester);

        expect(paginaTicket, findsNothing);
        expect(paginaDetalle, findsOneWidget);
        expect(_marca, findsNothing);
      },
    );

    testWidgets(
      'sin conexión al enviar el ticket: queda en cola, el cobro lo liga y la marca se va',
      (tester) async {
        final a = await _montar(tester);
        a.ticket.conexion.tipo = TipoConexion.sinConexion;

        await tocar(tester, find.text('Sacar foto del ticket'));
        await enviarElTicket(tester);

        expect(a.ticket.repo.recibidos, hasLength(1));
        a.detalle.repo.detalles['c-1'] = _tarjeta(
          ticketId: a.ticket.repo.recibidos.single.ticket.id,
        );
        await tocarTicket(tester, find.byKey(const Key('ticket_listo')));
        expect(_marca, findsNothing);
      },
    );
  });
}
