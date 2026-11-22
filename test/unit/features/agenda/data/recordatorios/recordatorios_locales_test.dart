// HU-NOT-002 / issue #453 — los recordatorios locales de las visitas agendadas, contra un motor de
// avisos en memoria (sin el plugin del teléfono).
import 'dart:async';

import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/motor_de_avisos_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/recordatorios_locales.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

/// Un `AppLogger` que guarda lo que se escribe, para comprobar que no filtra datos de la persona.
final class _Salida extends LogOutput {
  final List<String> lineas = [];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

final class _AnticipacionQueFalla implements AnticipacionRecordatorios {
  @override
  Future<int> minutos() async => throw StateError('no se pudo leer');
}

final class _AnticipacionDe implements AnticipacionRecordatorios {
  _AnticipacionDe(this.valor);

  int valor;

  @override
  Future<int> minutos() async => valor;
}

void main() {
  const direccion = 'Av. Italia 1234';
  late MotorDeAvisosEnMemoria motor;
  late PermisoNotificacionesSistemaEnMemoria permiso;
  late _Salida salida;
  late DateTime ahora;
  late _AnticipacionDe anticipacion;
  late RecordatoriosLocales recordatorios;

  // Hoy 27/10 a las 12:00 (hora del teléfono); las visitas son más tarde.
  setUp(() {
    motor = MotorDeAvisosEnMemoria();
    permiso = PermisoNotificacionesSistemaEnMemoria();
    salida = _Salida();
    ahora = DateTime(2026, 10, 27, 12);
    anticipacion = _AnticipacionDe(30);
    recordatorios = RecordatoriosLocales(
      motor: motor,
      permiso: permiso,
      anticipacion: anticipacion,
      ahora: () => ahora,
      logger: AppLogger(output: salida),
    );
  });

  RecordatorioDeVisita visita({
    String id = 'ag-1',
    TipoAgenda tipo = TipoAgenda.entrevista,
    String lugar = direccion,
    DateTime? cuando,
  }) => RecordatorioDeVisita(
    agendaId: id,
    tipo: tipo,
    direccion: lugar,
    fechaProgramada: cuando ?? DateTime(2026, 10, 27, 14),
  );

  AvisoProgramado? avisoDe(String id) => motor.pendientes[RecordatoriosLocales.idDeAviso(id)];

  group('Escenario: Recordatorio dispara a tiempo', () {
    test('dado una visita para las 14:00, cuando se programa, el aviso queda para las 13:30 con el '
        'texto de la HU', () async {
      final resultado = await recordatorios.programar(visita());

      expect(resultado, ResultadoRecordatorio.programado);
      final aviso = avisoDe('ag-1')!;
      expect(aviso.instante, DateTime(2026, 10, 27, 13, 30).toUtc());
      expect(aviso.instante.isUtc, isTrue);
      expect(aviso.cuerpo, 'Entrevista en Av. Italia 1234 a las 14:00');
      expect(aviso.payload, 'agenda:ag-1');
    });

    test(
      'dado una cobranza, cuando se programa, el texto dice «Cobranza» y su dirección',
      () async {
        await recordatorios.programar(
          visita(
            tipo: TipoAgenda.cobranza,
            lugar: 'Mataojo 2044',
            cuando: DateTime(2026, 10, 27, 18),
          ),
        );

        expect(avisoDe('ag-1')!.cuerpo, 'Cobranza en Mataojo 2044 a las 18:00');
      },
    );

    test('dado cualquier visita, cuando se programa, el aviso solo lleva tipo, hora y dirección '
        '(nunca el nombre del cliente)', () async {
      await recordatorios.programar(visita());

      final aviso = avisoDe('ag-1')!;
      // La entidad no recibe el nombre; esto ancla que título, cuerpo y payload no llevan nada más.
      expect(aviso.titulo, 'Recordatorio de visita');
      expect(aviso.cuerpo, 'Entrevista en Av. Italia 1234 a las 14:00');
      expect(aviso.payload, 'agenda:ag-1');
    });

    test('dado la anticipación elegida de 5, 60 o 120 minutos, cuando se programa, el aviso se '
        'corre en consecuencia', () async {
      for (final (minutos, esperada) in [
        (5, DateTime(2026, 10, 27, 13, 55)),
        (60, DateTime(2026, 10, 27, 13)),
        (120, DateTime(2026, 10, 27, 12)),
      ]) {
        anticipacion.valor = minutos;
        ahora = DateTime(2026, 10, 27, 11);
        await recordatorios.programar(visita());
        expect(avisoDe('ag-1')!.instante, esperada.toUtc(), reason: '$minutos minutos antes');
      }
    });

    test(
      'dado una anticipación fuera del rango, cuando se programa, se acota a 5 o a 120',
      () async {
        ahora = DateTime(2026, 10, 27, 8);
        anticipacion.valor = 0;
        await recordatorios.programar(visita());
        expect(avisoDe('ag-1')!.instante, DateTime(2026, 10, 27, 13, 55).toUtc());

        anticipacion.valor = 5000;
        await recordatorios.programar(visita());
        expect(avisoDe('ag-1')!.instante, DateTime(2026, 10, 27, 12).toUtc());
      },
    );

    test(
      'dado que no se puede leer la anticipación, cuando se programa, se usan los 30 minutos',
      () async {
        final sinLectura = RecordatoriosLocales(
          motor: motor,
          permiso: permiso,
          anticipacion: _AnticipacionQueFalla(),
          ahora: () => ahora,
          logger: AppLogger(output: salida),
        );

        final resultado = await sinLectura.programar(visita());

        expect(resultado, ResultadoRecordatorio.programado);
        expect(avisoDe('ag-1')!.instante, DateTime(2026, 10, 27, 13, 30).toUtc());
      },
    );

    test(
      'dado que la visita es en menos que la anticipación, cuando se programa, no se programa nada '
      '(yaPaso)',
      () async {
        final resultado = await recordatorios.programar(
          visita(cuando: DateTime(2026, 10, 27, 12, 20)),
        );

        expect(resultado, ResultadoRecordatorio.yaPaso);
        expect(motor.pendientes, isEmpty);
      },
    );

    test('dado que la hora del aviso es exactamente ahora, cuando se programa, ya pasó', () async {
      final resultado = await recordatorios.programar(
        visita(cuando: DateTime(2026, 10, 27, 12, 30)),
      );

      expect(resultado, ResultadoRecordatorio.yaPaso);
      expect(motor.pendientes, isEmpty);
    });
  });

  group('Escenario: Edit de hora reprograma', () {
    test('dado una visita a las 14:00 con aviso a las 13:30, cuando cambia a las 15:00, el aviso '
        'pasa a las 14:30 y queda uno solo', () async {
      await recordatorios.programar(visita());

      final resultado = await recordatorios.programar(visita(cuando: DateTime(2026, 10, 27, 15)));

      expect(resultado, ResultadoRecordatorio.programado);
      expect(motor.pendientes, hasLength(1));
      final aviso = avisoDe('ag-1')!;
      expect(aviso.instante, DateTime(2026, 10, 27, 14, 30).toUtc());
      expect(aviso.cuerpo, 'Entrevista en Av. Italia 1234 a las 15:00');
    });

    test(
      'dado una visita con aviso, cuando la hora nueva deja el aviso en el pasado, el aviso viejo '
      'se cancela (no puede sonar a la hora de antes)',
      () async {
        await recordatorios.programar(visita());

        final resultado = await recordatorios.programar(
          visita(cuando: DateTime(2026, 10, 27, 12, 10)),
        );

        expect(resultado, ResultadoRecordatorio.yaPaso);
        expect(motor.pendientes, isEmpty);
      },
    );

    test('dado dos agendas distintas, cuando se reprograma una, la otra no se toca', () async {
      await recordatorios.programar(visita());
      await recordatorios.programar(visita(id: 'ag-2', cuando: DateTime(2026, 10, 27, 16)));

      await recordatorios.programar(visita(cuando: DateTime(2026, 10, 27, 15)));

      expect(motor.pendientes, hasLength(2));
      expect(avisoDe('ag-2')!.instante, DateTime(2026, 10, 27, 15, 30).toUtc());
    });

    test(
      'dado el aviso con el plugin que falla, cuando se reprograma, no lanza, devuelve noSePudo y '
      'no deja el aviso viejo',
      () async {
        await recordatorios.programar(visita());
        motor.fallaAlProgramar = true;

        final resultado = await recordatorios.programar(visita(cuando: DateTime(2026, 10, 27, 15)));

        expect(resultado, ResultadoRecordatorio.noSePudo);
        expect(motor.pendientes, isEmpty);
      },
    );

    test('dado el plugin que falla al programar y al cancelar, cuando se programa, igual devuelve '
        'noSePudo sin lanzar', () async {
      motor
        ..fallaAlProgramar = true
        ..fallaAlCancelar = true;

      expect(await recordatorios.programar(visita()), ResultadoRecordatorio.noSePudo);
    });
  });

  group('Escenario: Cancelar visita cancela el recordatorio', () {
    test(
      'dado un recordatorio programado, cuando se cancela la visita, el aviso desaparece',
      () async {
        await recordatorios.programar(visita());

        final cancelado = await recordatorios.cancelar('ag-1');

        expect(cancelado, isTrue);
        expect(motor.pendientes, isEmpty);
      },
    );

    test(
      'dado una agenda sin recordatorio, cuando se cancela, no pasa nada y devuelve true',
      () async {
        expect(await recordatorios.cancelar('ag-que-no-existe'), isTrue);
        expect(motor.pendientes, isEmpty);
      },
    );

    test(
      'dado el plugin que falla al cancelar, cuando se cancela, no lanza y devuelve false',
      () async {
        await recordatorios.programar(visita());
        motor.fallaAlCancelar = true;

        expect(await recordatorios.cancelar('ag-1'), isFalse);
        expect(salida.lineas.join('\n'), contains('RECORDATORIO_CANCELAR'));
      },
    );

    test(
      'dado el recordatorio que se cancela dos veces, cuando se repite, la segunda no hace nada',
      () async {
        await recordatorios.programar(visita());

        expect(await recordatorios.cancelar('ag-1'), isTrue);
        expect(await recordatorios.cancelar('ag-1'), isTrue);
        expect(motor.pendientes, isEmpty);
      },
    );
  });

  group('Dos acciones seguidas, sin esperar a la primera', () {
    test('dado un «programar» que tarda, cuando se pide «cancelar» sin esperarlo, el aviso queda '
        'cancelado', () async {
      motor.programacionDemorada = Completer<void>();

      final programando = recordatorios.programar(visita());
      final cancelando = recordatorios.cancelar('ag-1');
      await Future<void>.delayed(Duration.zero);
      // El «cancelar» todavía no llegó al plugin: espera su turno.
      expect(motor.llamadas, ['programar:${RecordatoriosLocales.idDeAviso('ag-1')}']);
      motor.programacionDemorada!.complete();
      await Future.wait([programando, cancelando]);

      expect(motor.pendientes, isEmpty);
      expect(motor.llamadas.last, startsWith('cancelar:'));
    });

    test(
      'dado dos cambios de hora seguidos, cuando se piden sin esperar, gana el último',
      () async {
        motor.programacionDemorada = Completer<void>();

        final primera = recordatorios.programar(visita(cuando: DateTime(2026, 10, 27, 15)));
        final segunda = recordatorios.programar(visita(cuando: DateTime(2026, 10, 27, 17)));
        motor.programacionDemorada!.complete();
        await Future.wait([primera, segunda]);

        expect(motor.pendientes, hasLength(1));
        expect(avisoDe('ag-1')!.instante, DateTime(2026, 10, 27, 16, 30).toUtc());
      },
    );

    test(
      'dado un «programar» que falla, cuando se programa otra visita, el segundo se ejecuta igual',
      () async {
        motor.fallaAlProgramar = true;
        expect(await recordatorios.programar(visita()), ResultadoRecordatorio.noSePudo);
        motor.fallaAlProgramar = false;

        expect(await recordatorios.programar(visita(id: 'ag-2')), ResultadoRecordatorio.programado);

        expect(avisoDe('ag-2'), isNotNull);
      },
    );

    test('dado el doble toque en «agendar», cuando se programa dos veces la misma visita, queda un '
        'solo aviso', () async {
      await Future.wait([recordatorios.programar(visita()), recordatorios.programar(visita())]);

      expect(motor.pendientes, hasLength(1));
    });
  });

  group('Con el permiso del teléfono negado', () {
    test(
      'dado que las notificaciones están apagadas, cuando se programa, no falla: queda programado '
      'y avisa sinPermiso',
      () async {
        permiso.estado = EstadoSistemaNotificaciones.apagadas;

        final resultado = await recordatorios.programar(visita());

        expect(resultado, ResultadoRecordatorio.sinPermiso);
        expect(avisoDe('ag-1'), isNotNull);
        expect(await recordatorios.puedeAvisar(), isFalse);
      },
    );

    test('dado que iOS todavía no preguntó, cuando se consulta, no se puede avisar', () async {
      permiso.estado = EstadoSistemaNotificaciones.sinPreguntar;

      expect(await recordatorios.puedeAvisar(), isFalse);
    });

    test('dado el permiso activado, cuando se consulta, se puede avisar', () async {
      expect(await recordatorios.puedeAvisar(), isTrue);
    });

    test('dado que el sistema no contesta el estado, cuando se consulta o se programa, no lanza '
        '(consulta false, programa sinPermiso)', () async {
      permiso.fallaAlLeer = true;

      expect(await recordatorios.puedeAvisar(), isFalse);
      expect(await recordatorios.programar(visita()), ResultadoRecordatorio.sinPermiso);
      expect(avisoDe('ag-1'), isNotNull);
    });

    test(
      'dado el permiso que la persona activa después, cuando se consulta, se puede avisar',
      () async {
        permiso.estado = EstadoSistemaNotificaciones.apagadas;
        await recordatorios.programar(visita());
        expect(await recordatorios.puedeAvisar(), isFalse);

        permiso.estado = EstadoSistemaNotificaciones.activadas;

        expect(await recordatorios.puedeAvisar(), isTrue);
        expect(avisoDe('ag-1'), isNotNull);
      },
    );
  });

  group('Qué queda en el log', () {
    test('dado un fallo del plugin, cuando se programa, el log lleva el id de la agenda pero no la '
        'dirección', () async {
      motor.fallaAlProgramar = true;

      await recordatorios.programar(visita());

      final log = salida.lineas.join('\n');
      expect(log, contains('RECORDATORIO_PROGRAMAR'));
      expect(log, contains('ag-1'));
      expect(log, isNot(contains(direccion)));
    });
  });

  group('Id del aviso', () {
    test(
      'dado un id de agenda, cuando se calcula, siempre da el mismo número positivo de 31 bits',
      () {
        const id = '0192f3a0-7b1c-7cde-9f01-aaaaaaaaaaaa';
        final n = RecordatoriosLocales.idDeAviso(id);

        expect(RecordatoriosLocales.idDeAviso(id), n);
        expect(n, inInclusiveRange(0, 0x7fffffff));
      },
    );

    test('dado mil agendas, cuando se calcula su número, no hay choques', () {
      final ids = {
        for (var i = 0; i < 1000; i++)
          RecordatoriosLocales.idDeAviso(
            '0192f3a0-7b1c-7cde-9f01-${i.toString().padLeft(12, '0')}',
          ),
      };

      expect(ids, hasLength(1000));
    });
  });

  group('Tocar el recordatorio', () {
    test(
      'dado que la app está escuchando, cuando se toca un aviso, llega el id de la agenda',
      () async {
        await recordatorios.iniciar();
        final recibidos = <String>[];
        final suscripcion = recordatorios.agendasTocadas.listen(recibidos.add);

        motor.tocar('agenda:ag-7');
        motor.tocar('agenda:ag-8');
        await Future<void>.delayed(Duration.zero);

        expect(recibidos, ['ag-7', 'ag-8']);
        expect(await recordatorios.tomarAgendaPendiente(), isNull);
        await suscripcion.cancel();
      },
    );

    test(
      'dado que nadie escucha, cuando se toca un aviso, queda pendiente y se entrega una sola vez',
      () async {
        await recordatorios.iniciar();

        motor.tocar('agenda:ag-7');

        expect(await recordatorios.tomarAgendaPendiente(), 'ag-7');
        expect(await recordatorios.tomarAgendaPendiente(), isNull);
      },
    );

    test(
      'dado que la app arrancó por un aviso, cuando se inicia, el aviso queda pendiente',
      () async {
        motor.payloadDeLanzamiento = 'agenda:ag-9';

        await recordatorios.iniciar();

        expect(await recordatorios.tomarAgendaPendiente(), 'ag-9');
      },
    );

    test(
      'dado que se tocó más de un aviso sin escuchar, cuando se toma, queda el último',
      () async {
        await recordatorios.iniciar();

        motor.tocar('agenda:ag-1');
        motor.tocar('agenda:ag-2');

        expect(await recordatorios.tomarAgendaPendiente(), 'ag-2');
      },
    );

    test(
      'dado un payload que no es de una agenda o viene vacío, cuando se toca, se ignora',
      () async {
        await recordatorios.iniciar();

        motor
          ..tocar(null)
          ..tocar('')
          ..tocar('pedido:5');

        expect(await recordatorios.tomarAgendaPendiente(), isNull);
      },
    );

    test('dado que el plugin no arranca, cuando se inicia, no lanza y lo deja en el log', () async {
      motor.fallaAlIniciar = true;

      await recordatorios.iniciar();

      expect(salida.lineas.join('\n'), contains('RECORDATORIO_INICIAR'));
    });
  });
}
