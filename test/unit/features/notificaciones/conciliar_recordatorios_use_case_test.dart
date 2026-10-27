// HU-NOT-005 / issue #416 — «cada recordatorio local se guarda al dispararse»: el caso de uso que, al
// abrir la app o volver a ella, guarda en el historial los recordatorios de visitas cuya hora de
// aviso ya pasó. Con falsos en memoria: lo que pide a la agenda, lo que guarda y la marca.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/marca_conciliacion_recordatorios_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/conciliar_recordatorios_use_case.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/conciliacion_recordatorios_falsos.dart';
import '../../../helpers/historial_notificaciones_falsos.dart';
import '../../../helpers/logger_mudo.dart';

void main() {
  late AgendasConAvisoVencidoEnMemoria agendas;
  late PreferenciasRecordatoriosRepositoryEnMemoria preferencias;
  late MarcaConciliacionRecordatoriosEnMemoria marca;
  late HistorialEnMemoria historial;
  late DateTime ahora;
  late ConciliarRecordatoriosUseCase conciliar;

  // La visita es a las 15:00; con 30 minutos el aviso suena a las 14:30.
  final visita = DateTime.utc(2026, 10, 27, 15);
  final aviso = DateTime.utc(2026, 10, 27, 14, 30);

  setUp(() {
    agendas = AgendasConAvisoVencidoEnMemoria();
    preferencias = PreferenciasRecordatoriosRepositoryEnMemoria();
    historial = HistorialEnMemoria();
    // La app ya se abrió a las 12:00 (la marca) y vuelve a abrirse a las 15:10.
    marca = MarcaConciliacionRecordatoriosEnMemoria(DateTime.utc(2026, 10, 27, 12));
    ahora = DateTime.utc(2026, 10, 27, 15, 10);
    conciliar = ConciliarRecordatoriosUseCase(
      agendas,
      preferencias,
      marca,
      RegistrarNotificacionUseCase(historial, ahora: () => ahora),
      ahora: () => ahora,
      logger: loggerMudo(),
    );
  });

  test('dado un recordatorio que sonó con la app cerrada, cuando se abre la app, queda en el '
      'historial con la hora del aviso, sin leer y con el enlace a la agenda', () async {
    agendas.visitas.add(visitaParaAviso('age-1', visita, tipo: TipoAgenda.cobranza));

    final r = await conciliar('col-1');

    expect(r, const Right<Failure, int>(1));
    final fila = historial.filas.single;
    expect(fila.id, 'recordatorio-age-1-${aviso.millisecondsSinceEpoch}');
    expect(fila.tipo, TipoNotificacion.recordatorioVisita);
    expect(fila.titulo, 'Recordatorio de visita');
    expect(fila.detalle, 'Cobranza en Av. Italia 1234 a las ${_hhmm(visita)}');
    expect(fila.destino, const DestinoAgenda('age-1'));
    expect(fila.recibidaEn, aviso);
    expect(fila.leida, isFalse);
    expect(marca.marca, ahora);
  });

  test('dado que el aviso todavía no sonó, no se guarda', () async {
    ahora = DateTime.utc(2026, 10, 27, 14, 29);
    agendas.visitas.add(visitaParaAviso('age-1', visita));

    final r = await conciliar('col-1');

    expect(r, const Right<Failure, int>(0));
    expect(historial.filas, isEmpty);
  });

  test('dado la primera revisión del teléfono (sin marca), solo fija la marca: no inventa avisos '
      'anteriores ni pregunta a la agenda', () async {
    marca.marca = null;
    agendas.visitas.add(visitaParaAviso('age-1', visita));

    final r = await conciliar('col-1');

    expect(r, const Right<Failure, int>(0));
    expect(historial.filas, isEmpty);
    expect(agendas.pedidos, isEmpty);
    expect(marca.marca, ahora);
  });

  test('dado que la revisión corre dos veces, cuando la marca no avanzó entre una y otra, el aviso '
      'queda una sola vez', () async {
    agendas.visitas.add(visitaParaAviso('age-1', visita));

    expect(await conciliar('col-1'), const Right<Failure, int>(1));
    marca.marca = DateTime.utc(2026, 10, 27, 12);
    expect(await conciliar('col-1'), const Right<Failure, int>(0));

    expect(historial.filas, hasLength(1));
  });

  test('dado que la revisión corre dos veces seguidas, la segunda no vuelve a pedir lo ya '
      'revisado', () async {
    agendas.visitas.add(visitaParaAviso('age-1', visita));

    await conciliar('col-1');
    ahora = ahora.add(const Duration(minutes: 5));
    await conciliar('col-1');

    expect(historial.filas, hasLength(1));
    expect(agendas.pedidos, [
      '2026-10-27T12:00:00.000Z|2026-10-27T15:10:00.000Z|30',
      '2026-10-27T15:10:00.000Z|2026-10-27T15:15:00.000Z|30',
    ]);
  });

  test('dado que la persona borró todo el historial, cuando se vuelve a abrir la app, el aviso '
      'borrado no vuelve aunque la visita siga pendiente', () async {
    agendas.visitas.add(visitaParaAviso('age-1', visita));
    await conciliar('col-1');
    await BorrarTodasLasNotificacionesUseCase(historial)();
    expect(historial.filas, isEmpty);

    ahora = ahora.add(const Duration(minutes: 20));
    await conciliar('col-1');

    expect(historial.filas, isEmpty);
  });

  test('dado varios avisos vencidos, los guarda todos, cada uno con su hora', () async {
    agendas.visitas
      ..add(visitaParaAviso('age-1', visita))
      ..add(visitaParaAviso('age-2', DateTime.utc(2026, 10, 27, 13)))
      ..add(visitaParaAviso('age-3', DateTime.utc(2026, 10, 27, 15, 30)));

    final r = await conciliar('col-1');

    // age-3 suena a las 15:00, antes de las 15:10; todos entran.
    expect(r, const Right<Failure, int>(3));
    expect(historial.filas.map((f) => f.recibidaEn).toSet(), {
      DateTime.utc(2026, 10, 27, 12, 30),
      aviso,
      DateTime.utc(2026, 10, 27, 15),
    });
  });

  group('preferencias', () {
    test(
      'dado otra anticipación, pide la ventana con esos minutos y el aviso lleva esa hora',
      () async {
        preferencias.preferencias = const PreferenciasRecordatorios(anticipacionMinutos: 60);
        agendas.visitas.add(visitaParaAviso('age-1', visita));

        await conciliar('col-1');

        expect(agendas.pedidos.single.endsWith('|60'), isTrue);
        expect(historial.filas.single.recibidaEn, DateTime.utc(2026, 10, 27, 14));
      },
    );

    test('dado «Recordatorios de agenda» apagado, no sonó nada: no guarda y avanza la marca, así '
        'que al prenderlos no aparecen los de antes', () async {
      preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      agendas.visitas.add(visitaParaAviso('age-1', visita));

      expect(await conciliar('col-1'), const Right<Failure, int>(0));
      expect(historial.filas, isEmpty);
      expect(agendas.pedidos, isEmpty);
      expect(marca.marca, ahora);

      preferencias.preferencias = const PreferenciasRecordatorios();
      ahora = ahora.add(const Duration(minutes: 1));
      await conciliar('col-1');
      expect(historial.filas, isEmpty);
    });

    test('dado que no se pueden leer las preferencias, usa las de siempre (30 minutos)', () async {
      preferencias.fallaAlLeer = true;
      agendas.visitas.add(visitaParaAviso('age-1', visita));

      expect(await conciliar('col-1'), const Right<Failure, int>(1));
      expect(agendas.pedidos.single.endsWith('|30'), isTrue);
    });
  });

  group('ventana', () {
    test(
      'dado una marca de hace meses, no mira más atrás de los 90 días que el historial guarda',
      () async {
        marca.marca = DateTime.utc(2026, 3, 1);

        await conciliar('col-1');

        expect(agendas.pedidos.single, '2026-07-29T15:10:00.000Z|2026-10-27T15:10:00.000Z|30');
      },
    );

    test('dado que el reloj fue hacia atrás de la marca, no revisa ni mueve la marca', () async {
      marca.marca = DateTime.utc(2026, 10, 27, 16);

      expect(await conciliar('col-1'), const Right<Failure, int>(0));
      expect(agendas.pedidos, isEmpty);
      expect(marca.marca, DateTime.utc(2026, 10, 27, 16));
    });
  });

  group('fallas', () {
    test('dado que guardar un aviso falla, cuando los demás se guardan, la marca no avanza y la '
        'próxima revisión lo reintenta', () async {
      historial.prefijoQueFallaAlRegistrar = 'recordatorio-age-1-';
      agendas.visitas
        ..add(visitaParaAviso('age-1', visita))
        ..add(visitaParaAviso('age-2', visita));

      final r = await conciliar('col-1');

      expect(r, const Right<Failure, int>(1));
      expect(historial.filas.single.destino, const DestinoAgenda('age-2'));
      expect(marca.marca, DateTime.utc(2026, 10, 27, 12));

      historial.prefijoQueFallaAlRegistrar = null;
      expect(await conciliar('col-1'), const Right<Failure, int>(1));
      expect(historial.filas, hasLength(2));
      expect(marca.marca, ahora);
    });

    test('dado que la agenda no se puede leer, devuelve el error sin guardar nada ni mover la '
        'marca', () async {
      agendas.error = StateError('sin base');

      final r = await conciliar('col-1');

      expect(r.isLeft(), isTrue);
      expect(marca.marca, DateTime.utc(2026, 10, 27, 12));
    });

    test('dado que la marca no se puede leer, devuelve el error y no adivina', () async {
      marca.fallaAlLeer = true;
      agendas.visitas.add(visitaParaAviso('age-1', visita));

      final r = await conciliar('col-1');

      expect(r.isLeft(), isTrue);
      expect(historial.filas, isEmpty);
    });

    test('dado que la marca no se puede guardar, los avisos quedan guardados y la próxima '
        'revisión no los duplica', () async {
      marca.fallaAlGuardar = true;
      agendas.visitas.add(visitaParaAviso('age-1', visita));

      expect(await conciliar('col-1'), const Right<Failure, int>(1));
      expect(await conciliar('col-1'), const Right<Failure, int>(0));
      expect(historial.filas, hasLength(1));
    });
  });
}

String _hhmm(DateTime utc) {
  final l = utc.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
