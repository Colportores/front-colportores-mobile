// HU-NOT-002 / issue #453 — el fake que usan los casos de uso de la agenda en sus tests se comporta
// como el real: reemplaza por agenda, cancela, avisa sin permiso y entrega los toques una vez.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:test/test.dart';

void main() {
  RecordatorioDeVisita visita(String id, {int hora = 14}) => RecordatorioDeVisita(
    agendaId: id,
    tipo: TipoAgenda.entrevista,
    direccion: 'Av. Italia 1234',
    fechaProgramada: DateTime(2026, 10, 27, hora),
  );

  test('dado una visita, cuando se programa de nuevo con otra hora, queda la última', () async {
    final r = RecordatoriosEnMemoria();

    expect(await r.programar(visita('ag-1')), ResultadoRecordatorio.programado);
    await r.programar(visita('ag-1', hora: 15));

    expect(r.programados, hasLength(1));
    expect(r.programados['ag-1'], visita('ag-1', hora: 15));
    expect(r.llamadas, ['programar:ag-1', 'programar:ag-1']);
  });

  test(
    'dado un recordatorio, cuando se cancela, desaparece; si no puede, devuelve false',
    () async {
      final r = RecordatoriosEnMemoria();
      await r.programar(visita('ag-1'));

      expect(await r.cancelar('ag-1'), isTrue);
      expect(r.programados, isEmpty);

      await r.programar(visita('ag-2'));
      r.puedeCancelar = false;
      expect(await r.cancelar('ag-2'), isFalse);
      expect(r.programados, hasLength(1));
    },
  );

  test(
    'dado el permiso negado, cuando se programa, avisa sinPermiso y puedeAvisar es false',
    () async {
      final r = RecordatoriosEnMemoria(permisoConcedido: false);

      expect(await r.programar(visita('ag-1')), ResultadoRecordatorio.sinPermiso);
      expect(await r.puedeAvisar(), isFalse);
      expect(r.programados, hasLength(1));
    },
  );

  test('dado un resultado forzado, cuando se programa, devuelve ese y no guarda nada', () async {
    final r = RecordatoriosEnMemoria()..resultadoForzado = ResultadoRecordatorio.yaPaso;

    expect(await r.programar(visita('ag-1')), ResultadoRecordatorio.yaPaso);
    expect(r.programados, isEmpty);
  });

  test('dado una programación que tarda, cuando se completa, recién ahí devuelve', () async {
    final r = RecordatoriosEnMemoria()..programacionDemorada = Completer<void>();
    var termino = false;

    final futuro = r.programar(visita('ag-1')).then((_) => termino = true);
    await Future<void>.delayed(Duration.zero);
    expect(termino, isFalse);
    r.programacionDemorada!.complete();
    await futuro;

    expect(termino, isTrue);
  });

  test(
    'dado un toque sin oyente, cuando se toma, se entrega una vez; con oyente llega al stream',
    () async {
      final r = RecordatoriosEnMemoria()..tocar('ag-1');

      expect(await r.tomarAgendaPendiente(), 'ag-1');
      expect(await r.tomarAgendaPendiente(), isNull);

      final recibidos = <String>[];
      final suscripcion = r.agendasTocadas.listen(recibidos.add);
      r.tocar('ag-2');
      await Future<void>.delayed(Duration.zero);
      expect(recibidos, ['ag-2']);
      expect(await r.tomarAgendaPendiente(), isNull);
      await suscripcion.cancel();
    },
  );
}
