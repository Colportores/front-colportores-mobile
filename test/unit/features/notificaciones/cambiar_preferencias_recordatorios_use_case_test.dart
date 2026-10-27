// HU-NOT-004 / issue #415 — cambiar las preferencias de los recordatorios y reprogramar los ya
// agendados, con los recordatorios reales (`RecordatoriosLocales`) sobre un motor de avisos en memoria
// que lee las preferencias recién guardadas.
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/motor_de_avisos_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/recordatorios_locales.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/cambiar_preferencias_recordatorios_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/agendas_para_recordar_falsas.dart';
import '../../../helpers/logger_mudo.dart';

void main() {
  late PreferenciasRecordatoriosRepositoryEnMemoria preferencias;
  late MotorDeAvisosEnMemoria motor;
  late PermisoNotificacionesSistemaEnMemoria permiso;
  late AgendasParaRecordarEnMemoria agendas;
  late RecordatoriosLocales recordatorios;
  late CambiarPreferenciasRecordatoriosUseCase cambiar;
  final ahora = DateTime(2026, 10, 27, 8);

  RecordatorioDeVisita visita(String id, int hora, {TipoAgenda tipo = TipoAgenda.entrevista}) =>
      RecordatorioDeVisita(
        agendaId: id,
        tipo: tipo,
        direccion: 'Av. Italia 1234',
        fechaProgramada: DateTime(2026, 10, 27, hora),
      );

  AvisoProgramado? aviso(String id) => motor.pendientes[RecordatoriosLocales.idDeAviso(id)];

  setUp(() {
    preferencias = PreferenciasRecordatoriosRepositoryEnMemoria();
    motor = MotorDeAvisosEnMemoria();
    permiso = PermisoNotificacionesSistemaEnMemoria();
    agendas = AgendasParaRecordarEnMemoria([
      visita('ag-1', 14),
      visita('ag-2', 16),
      visita('ag-3', 18),
    ]);
    recordatorios = RecordatoriosLocales(
      motor: motor,
      permiso: permiso,
      anticipacion: preferencias,
      activados: preferencias,
      ahora: () => ahora,
      logger: loggerMudo(),
    );
    cambiar = CambiarPreferenciasRecordatoriosUseCase(
      preferencias,
      ReprogramarRecordatoriosUseCase(
        agendas,
        recordatorios,
        ahora: () => ahora,
        logger: loggerMudo(),
      ),
      logger: loggerMudo(),
    );
  });

  Future<void> agendarTodas() async {
    for (final v in agendas.agendas) {
      await recordatorios.programar(v);
    }
  }

  const porDefecto = PreferenciasRecordatorios();

  group('Antes de cambiar (historial de avisos, HU-NOT-005)', () {
    CambiarPreferenciasRecordatoriosUseCase conGancho(Future<void> Function(String) gancho) =>
        CambiarPreferenciasRecordatoriosUseCase(
          preferencias,
          ReprogramarRecordatoriosUseCase(
            agendas,
            recordatorios,
            ahora: () => ahora,
            logger: loggerMudo(),
          ),
          antesDeCambiar: gancho,
          logger: loggerMudo(),
        );

    test('dado un cambio, primero guarda lo que sonó con las preferencias de antes y recién '
        'después escribe las nuevas', () async {
      final orden = <String>[];
      final caso = conGancho((colportorId) async {
        orden.add('antes:$colportorId:${(await preferencias.leer()).anticipacionMinutos}');
      });

      await caso(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
      );

      expect(orden, ['antes:col-1:30']);
      expect((await preferencias.leer()).anticipacionMinutos, 60);
    });

    test('dado que lo de antes falla, el cambio se guarda igual', () async {
      final caso = conGancho((_) async => throw StateError('sin base'));

      final r = await caso(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
      );

      expect(r.isRight(), isTrue);
      expect((await preferencias.leer()).anticipacionMinutos, 60);
    });

    test('dado que no hay quién tenga agendas (sin sesión), no llama a lo de antes', () async {
      var llamadas = 0;
      final caso = conGancho((_) async => llamadas++);

      await caso(
        colportorId: null,
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
      );

      expect(llamadas, 0);
    });
  });

  group('Escenario: Toggle recordatorios locales apagado', () {
    test(
      'dado que apago «Recordatorios de agenda», cuando tengo visitas agendadas, no se programan '
      'notificaciones locales',
      () async {
        await cambiar(
          colportorId: 'col-1',
          previas: porDefecto,
          nuevas: porDefecto.copyWith(activados: false),
        );

        expect(await recordatorios.programar(visita('ag-9', 15)), ResultadoRecordatorio.apagados);
        expect(aviso('ag-9'), isNull);
      },
    );

    test('dado tres visitas con recordatorio, cuando los apago, se cancelan también los de las '
        'visitas que ya agendé', () async {
      await agendarTodas();
      expect(motor.pendientes, hasLength(3));

      final r = await cambiar(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(activados: false),
      );

      expect(motor.pendientes, isEmpty);
      expect(r.getOrElse(() => throw StateError('falló')).reprogramados, 0);
      expect(preferencias.preferencias.activados, isFalse);
    });

    test('dado los recordatorios apagados, cuando los prendo de nuevo, vuelven los de las visitas '
        'ya agendadas', () async {
      await cambiar(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(activados: false),
      );

      final r = await cambiar(
        colportorId: 'col-1',
        previas: porDefecto.copyWith(activados: false),
        nuevas: porDefecto,
      );

      expect(motor.pendientes, hasLength(3));
      expect(r.getOrElse(() => throw StateError('falló')).reprogramados, 3);
      expect(aviso('ag-1')!.instante, DateTime(2026, 10, 27, 13, 30).toUtc());
    });

    test('dado los recordatorios apagados, cuando se programa una visita nueva, no queda ningún '
        'aviso viejo de esa agenda', () async {
      await recordatorios.programar(visita('ag-1', 14));
      await preferencias.guardarActivados(activados: false);

      expect(await recordatorios.programar(visita('ag-1', 15)), ResultadoRecordatorio.apagados);

      expect(aviso('ag-1'), isNull);
    });
  });

  group('Escenario: la anticipación cambia', () {
    test('dado tres recordatorios a 30 minutos, cuando paso a 60, los tres se reprograman y dice '
        'cuántos', () async {
      await agendarTodas();

      final r = await cambiar(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
      );

      final cambio = r.getOrElse(() => throw StateError('falló'));
      expect(cambio.reprogramados, 3);
      expect(cambio.preferencias.anticipacionMinutos, 60);
      expect(aviso('ag-1')!.instante, DateTime(2026, 10, 27, 13).toUtc());
      expect(aviso('ag-2')!.instante, DateTime(2026, 10, 27, 15).toUtc());
      expect(aviso('ag-3')!.instante, DateTime(2026, 10, 27, 17).toUtc());
      expect(preferencias.preferencias.anticipacionMinutos, 60);
    });

    test('dado el rango, cuando paso a 5 o a 120, se reprograma igual', () async {
      await agendarTodas();

      await cambiar(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 5),
      );
      expect(aviso('ag-1')!.instante, DateTime(2026, 10, 27, 13, 55).toUtc());

      await cambiar(
        colportorId: 'col-1',
        previas: porDefecto.copyWith(anticipacionMinutos: 5),
        nuevas: porDefecto.copyWith(anticipacionMinutos: 120),
      );
      expect(aviso('ag-1')!.instante, DateTime(2026, 10, 27, 12).toUtc());
    });

    test('dado una visita que queda a menos que la anticipación nueva, su aviso se cancela y no '
        'cuenta como reprogramado', () async {
      await agendarTodas();
      // Una visita a las 09:00 (ahora son las 08:00): con 30 minutos el aviso es a las 08:30.
      agendas.agendas.add(visita('ag-4', 9));
      await recordatorios.programar(visita('ag-4', 9));
      final r2 = await cambiar(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 90),
      );

      expect(r2.getOrElse(() => throw StateError('falló')).reprogramados, 3);
      expect(aviso('ag-4'), isNull);
    });

    test(
      'dado el permiso del teléfono apagado, cuando cambio la anticipación, los recordatorios se '
      'reprograman igual (valen cuando se active)',
      () async {
        permiso.estado = EstadoSistemaNotificaciones.apagadas;
        await agendarTodas();

        final r = await cambiar(
          colportorId: 'col-1',
          previas: porDefecto,
          nuevas: porDefecto.copyWith(anticipacionMinutos: 45),
        );

        expect(r.getOrElse(() => throw StateError('falló')).reprogramados, 3);
        expect(aviso('ag-1')!.instante, DateTime(2026, 10, 27, 13, 15).toUtc());
      },
    );

    test(
      'dado que no hay visitas agendadas, cuando cambio la anticipación, se guarda y dice 0',
      () async {
        agendas.agendas.clear();

        final r = await cambiar(
          colportorId: 'col-1',
          previas: porDefecto,
          nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
        );

        expect(r.getOrElse(() => throw StateError('falló')).reprogramados, 0);
        expect(preferencias.preferencias.anticipacionMinutos, 60);
      },
    );

    test(
      'dado un cambio, cuando se reprograma, se pide al colportor de la sesión y desde ahora',
      () async {
        await cambiar(
          colportorId: 'col-7',
          previas: porDefecto,
          nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
        );

        expect(agendas.ultimoColportor, 'col-7');
        expect(agendas.ultimoDesde, ahora);
      },
    );

    test('dado que solo cambió una preferencia, solo se escribe esa', () async {
      await cambiar(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
      );
      await cambiar(
        colportorId: 'col-1',
        previas: porDefecto.copyWith(anticipacionMinutos: 60),
        nuevas: porDefecto.copyWith(anticipacionMinutos: 60, activados: false),
      );

      expect(preferencias.guardados, ['minutos:60', 'activados:false']);
    });

    test('dado que no cambió nada, no escribe pero reprograma sin error', () async {
      final r = await cambiar(colportorId: 'col-1', previas: porDefecto, nuevas: porDefecto);

      expect(r.isRight(), isTrue);
      expect(preferencias.guardados, isEmpty);
    });

    test('dado que no hay colportor (sin sesión), se guarda y no se reprograma nada', () async {
      final r = await cambiar(
        colportorId: null,
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 60),
      );

      expect(r.getOrElse(() => throw StateError('falló')).reprogramados, 0);
      expect(agendas.consultas, 0);
      expect(preferencias.preferencias.anticipacionMinutos, 60);
    });
  });

  group('El interruptor vuelve a como estaba (24B·06)', () {
    test('dado que no se puede guardar, cuando cambio, devuelve el error y nada cambia', () async {
      await agendarTodas();
      preferencias.fallaAlGuardar = true;

      final r = await cambiar(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(activados: false),
      );

      expect(r.isLeft(), isTrue);
      expect(preferencias.preferencias, porDefecto);
      expect(motor.pendientes, hasLength(3));
    });

    test(
      'dado que no se pueden leer las agendas, cuando cambio la anticipación, devuelve el error y '
      'las preferencias vuelven a las de antes',
      () async {
        await agendarTodas();
        agendas.falla = true;

        final r = await cambiar(
          colportorId: 'col-1',
          previas: porDefecto,
          nuevas: porDefecto.copyWith(anticipacionMinutos: 90, activados: false),
        );

        expect(r.isLeft(), isTrue);
        expect(preferencias.preferencias, porDefecto);
        expect(preferencias.guardados, [
          'activados:false',
          'minutos:90',
          'minutos:30',
          'activados:true',
        ]);
        expect(motor.pendientes, hasLength(3));
      },
    );

    test('dado que falla el segundo guardado, el primero también se deshace', () async {
      final doble = _FallaElSegundoGuardado(preferencias);
      final caso = CambiarPreferenciasRecordatoriosUseCase(
        doble,
        ReprogramarRecordatoriosUseCase(agendas, recordatorios, logger: loggerMudo()),
        logger: loggerMudo(),
      );

      final r = await caso(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(activados: false, anticipacionMinutos: 90),
      );

      expect(r.isLeft(), isTrue);
      expect(preferencias.preferencias, porDefecto);
    });

    test('dado que deshacer también falla, no lanza y devuelve el error', () async {
      agendas.falla = true;
      final caso = CambiarPreferenciasRecordatoriosUseCase(
        _NoSePuedeDeshacer(preferencias),
        ReprogramarRecordatoriosUseCase(agendas, recordatorios, logger: loggerMudo()),
        logger: loggerMudo(),
      );

      final r = await caso(
        colportorId: 'col-1',
        previas: porDefecto,
        nuevas: porDefecto.copyWith(anticipacionMinutos: 90),
      );

      expect(r.isLeft(), isTrue);
    });
  });
}

/// Un repositorio cuyo segundo guardado falla (y después de eso, deshacer anda).
class _FallaElSegundoGuardado extends PreferenciasRecordatoriosRepositoryEnMemoria {
  _FallaElSegundoGuardado(PreferenciasRecordatoriosRepositoryEnMemoria base)
    : super(preferencias: base.preferencias) {
    _base = base;
  }

  late final PreferenciasRecordatoriosRepositoryEnMemoria _base;
  int _escrituras = 0;

  @override
  Future<void> guardarActivados({required bool activados}) async {
    _escrituras++;
    await _base.guardarActivados(activados: activados);
  }

  @override
  Future<void> guardarAnticipacion(int minutos) async {
    _escrituras++;
    if (_escrituras == 2) throw StateError('el almacén falló en el segundo guardado');
    await _base.guardarAnticipacion(minutos);
  }

  @override
  Future<PreferenciasRecordatorios> leer() => _base.leer();
}

/// Un repositorio que guarda una vez y después ya no deja escribir.
class _NoSePuedeDeshacer extends PreferenciasRecordatoriosRepositoryEnMemoria {
  _NoSePuedeDeshacer(PreferenciasRecordatoriosRepositoryEnMemoria base)
    : super(preferencias: base.preferencias);

  int _escrituras = 0;

  @override
  Future<void> guardarAnticipacion(int minutos) async {
    _escrituras++;
    if (_escrituras > 1) throw StateError('ya no se puede escribir');
    await super.guardarAnticipacion(minutos);
  }
}
