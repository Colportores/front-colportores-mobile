// Arnés del QA del PR #678 (HU-VEN-003, #433): los estados de la cita de ENTREGA en la Agenda que
// `qa_vista23_entrega_433_arnes.dart` no alcanzaba (23C·06 cumplida, 23C·07 error al guardar el
// cambio, 23B·02 con la hora vencida). Las capturas van a `.dart_tool/qa_capturas/` con
// `--dart-define=QA_CAPTURAS=true`.
import 'dart:ui' show Size;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/modificar_agenda_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agenda_items_falsos.dart';
import 'detalle_agenda_arnes.dart';
import 'qa_vista23_409_arnes.dart' show modificar409, subirHora409, tocar409;
import 'qa_vista23_entrega_433_arnes.dart';

/// Los estados nuevos que una persona alcanza con una cita de entrega.
enum Estado678 {
  cumplida('23C·06 entrega cumplida: no se modifica'),
  errorAlGuardar('23C·07 error al guardar el cambio'),
  vencida('23B·02 entrega con la hora vencida'),
  detalleConRegistrar('23C·01 detalle de la entrega con «Registrar resultado» enganchado');

  const Estado678(this.rotulo);
  final String rotulo;
}

DetalleDeAgenda entrega678({EstadoAgenda estado = EstadoAgenda.programada}) => DetalleDeAgenda(
  agenda: agendaDelDetalle(tipo: TipoAgenda.entrega, estado: estado, ventaId: 'ven-1'),
);

Future<void> llegarA678(
  WidgetTester tester,
  Estado678 estado, {
  Size tamano = chico455,
  double escala = 1,
}) async {
  switch (estado) {
    case Estado678.cumplida:
      await montarDetalle(
        tester,
        detalle: entrega678(estado: EstadoAgenda.cumplida),
        conRegistrar: true,
        tamano: tamano,
        escala: escala,
        abrir: false,
      );
      await abrirDetalle(tester);
    case Estado678.errorAlGuardar:
      final a = await montarDetalle(
        tester,
        detalle: entrega678(),
        tamano: tamano,
        escala: escala,
        abrir: false,
      );
      await abrirDetalle(tester);
      a.repo.fallas.add(const FailureInesperado());
      await tocar409(tester, modificar409);
      await subirHora409(tester, 6);
      await tocar409(tester, find.byKey(ClavesModificarAgenda.guardar));
    case Estado678.detalleConRegistrar:
      await montarDetalle(
        tester,
        detalle: entrega678(),
        conRegistrar: true,
        tamano: tamano,
        escala: escala,
        abrir: false,
      );
      await abrirDetalle(tester);
    case Estado678.vencida:
      final m = await llegarA433(tester, Estado433.lista, tamano: tamano, escala: escala);
      m.consulta.emitir([
        itemAgenda(
          'ag-1',
          DateTime(2026, 10, 23, 11),
          tipo: TipoAgenda.entrega,
          nombre: 'María',
          apellido: 'Fernández',
          calle: 'Mataojo',
          numero: '2044',
          espacioId: 'esp-1',
        ),
      ]);
      await asentarDetalle(tester);
  }
}
