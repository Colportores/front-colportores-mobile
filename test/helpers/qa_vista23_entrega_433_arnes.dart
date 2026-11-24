// Arnés del QA de la cita de ENTREGA en la Agenda (HU-VEN-003, #433): la lista, el detalle, «Modificar»
// y la hoja de cancelar de la Agenda real, con una agenda de tipo ENTREGA. Reusa el montaje de #455.
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/modificar_agenda_page.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'detalle_agenda_arnes.dart';
import 'qa_vista23_455_arnes.dart';

export 'qa_vista23_455_arnes.dart';

const tituloEntrega433 = '¿Cancelar la entrega?';
const cuerpoEntrega433 =
    'Queda como cancelada (la ves con el filtro «Canceladas») y se borra el recordatorio. Lo que '
    'falta entregar sigue pendiente.';

/// Los estados de la cita de entrega que una persona puede alcanzar en la Agenda.
enum Estado433 {
  lista('Agenda: la fila de la entrega'),
  detalle('23C·01 detalle de la entrega'),
  modificar('23C·02 modificar la entrega'),
  hoja('23C·04 hoja «¿Cancelar la entrega?»'),
  hojaCancelando('23C·04 cancelando'),
  hojaError('23C·05 error al cancelar'),
  cancelada('23C·04 cancelada (aviso)');

  const Estado433(this.rotulo);
  final String rotulo;
}

final guardar433 = find.byKey(ClavesModificarAgenda.guardar);

Future<Montaje455> llegarA433(
  WidgetTester tester,
  Estado433 estado, {
  Size tamano = chico455,
  double escala = 1,
}) async {
  Future<Montaje455> montar({bool entrar = true}) =>
      montar455(tester, tipo: TipoAgenda.entrega, entrar: entrar, tamano: tamano, escala: escala);

  switch (estado) {
    case Estado433.lista:
      return montar(entrar: false);
    case Estado433.detalle:
      return montar();
    case Estado433.modificar:
      final m = await montar();
      await tester.ensureVisible(find.byKey(ClavesDetalleAgenda.modificar));
      await tester.pump();
      await tester.tap(find.byKey(ClavesDetalleAgenda.modificar));
      await asentarDetalle(tester);
      return m;
    case Estado433.hoja:
      final m = await montar();
      await abrirHoja455(tester);
      return m;
    case Estado433.hojaCancelando:
      final m = await montar();
      m.repo.compuertaAlCancelar = Completer<void>();
      await abrirHoja455(tester);
      await tester.ensureVisible(confirmar455);
      await tester.pump();
      await tester.tap(confirmar455);
      await tester.pump(const Duration(milliseconds: 60));
      return m;
    case Estado433.hojaError:
      final m = await montar();
      m.repo.fallasAlCancelar.add(const FailureInesperado());
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      return m;
    case Estado433.cancelada:
      final m = await montar();
      await abrirHoja455(tester);
      await confirmar455Tocar(tester);
      return m;
  }
}

/// La pantalla completa como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar433(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/433_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
