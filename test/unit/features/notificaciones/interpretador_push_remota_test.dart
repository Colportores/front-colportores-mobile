// HU-NOT-003 (#187) — cómo se lee el `data` de una push remota: tipo de evento y UUIDs, nada más
// (R-NO02). Un campo que no sea eso se descarta junto con el mensaje.
import 'package:colportores_mobile/features/notificaciones/domain/entities/push_remota.dart';
import 'package:colportores_mobile/features/notificaciones/domain/services/interpretador_push_remota.dart';
import 'package:test/test.dart';

const _pedido = '3f2b8c1e-9a4d-4e7b-8c1a-5d6e7f8a9b0c';
const _evento = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';

void main() {
  group('un payload válido', () {
    test('dado `{type: pedido_autorizado, pedido_id}`, cuando se lee, entonces es la push del '
        'pedido', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'event_id': _evento,
      });

      expect(
        lectura,
        isA<PushLeida>().having(
          (l) => l.push,
          'push',
          const PushRemota(
            tipo: TipoPushRemota.pedidoAutorizado,
            eventoId: _evento,
            entidadId: _pedido,
          ),
        ),
      );
    });

    test('dado el payload del ejemplo de la HU (sin `event_id`), cuando se lee, entonces el evento '
        'se reconoce por su tipo y su pedido', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
      });

      expect((lectura as PushLeida).push.eventoId, 'pedido_autorizado:$_pedido');
    });

    test('dado el mismo payload leído dos veces, entonces da el mismo evento (idempotencia)', () {
      final datos = {'type': 'pedido_autorizado', 'pedido_id': _pedido};

      final primera = InterpretadorPushRemota.leer(datos) as PushLeida;
      final segunda = InterpretadorPushRemota.leer({...datos}) as PushLeida;

      expect(primera.push, segunda.push);
    });

    test('dado un UUID en mayúsculas, entonces se normaliza a minúsculas: el mismo evento no se '
        'guarda dos veces por la capitalización', () {
      final mayusculas = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido.toUpperCase(),
        'event_id': _evento.toUpperCase(),
      });
      final minusculas = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'event_id': _evento,
      });

      expect((mayusculas as PushLeida).push, (minusculas as PushLeida).push);
    });
  });

  group('datos personales (R-NO02, «Edge: payload con PII»)', () {
    test('dado un payload con el nombre de un cliente, cuando se lee, entonces se descarta y '
        'nombra el campo, no su valor', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'cliente_nombre': 'María Fernández',
      });

      expect(lectura, isA<PushConDatosPersonales>());
      final campos = (lectura as PushConDatosPersonales).campos;
      expect(campos, ['cliente_nombre']);
      expect(campos.join(), isNot(contains('María')));
    });

    test(
      'dado un campo `*_id` cuyo valor es un texto y no un UUID, entonces es un dato personal',
      () {
        final lectura = InterpretadorPushRemota.leer({
          'type': 'pedido_autorizado',
          'pedido_id': 'Juan Pérez',
        });

        expect((lectura as PushConDatosPersonales).campos, ['pedido_id']);
      },
    );

    test('dado un `type` con texto libre, entonces es un dato personal', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'Tu pedido de Juan Pérez fue autorizado',
        'pedido_id': _pedido,
      });

      expect((lectura as PushConDatosPersonales).campos, ['type']);
    });

    test('dado un campo cuyo nombre es texto de una persona, entonces la auditoría guarda «?» '
        'en su lugar', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        'Juan Pérez, 11 5555-1234': 'x',
      });

      expect((lectura as PushConDatosPersonales).campos, ['?']);
    });

    test(
      'dado un valor que no es texto (un mapa, un número, null), entonces es un dato personal',
      () {
        final lectura = InterpretadorPushRemota.leer({
          'type': 'pedido_autorizado',
          'pedido_id': _pedido,
          'cliente': {'nombre': 'Ana'},
          'monto': 1500,
          'nota_id': null,
        });

        expect((lectura as PushConDatosPersonales).campos, ['cliente', 'monto', 'nota_id']);
      },
    );

    test('dado un payload con datos personales y un tipo desconocido, entonces gana el descarte '
        'por privacidad', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'tipo_del_futuro',
        'telefono': '11 5555-1234',
      });

      expect(lectura, isA<PushConDatosPersonales>());
    });

    test('dado un payload con muchísimos campos sospechosos, entonces la auditoría guarda un tope '
        'y sin repetidos', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'pedido_autorizado',
        'pedido_id': _pedido,
        for (var i = 0; i < 40; i++) 'campo_$i': 'x',
      });

      expect(
        (lectura as PushConDatosPersonales).campos,
        hasLength(InterpretadorPushRemota.maximoDeCamposAuditados),
      );
    });
  });

  group('lo que no se puede usar, sin ser un problema de privacidad', () {
    test('dado un payload sin `type`, entonces se ignora', () {
      final lectura = InterpretadorPushRemota.leer({'pedido_id': _pedido});

      expect(
        lectura,
        isA<PushIgnorada>().having((l) => l.motivo, 'motivo', MotivoPushIgnorada.sinTipo),
      );
    });

    test('dado un `type` que esta versión no conoce (el servidor va adelante), entonces se ignora '
        'sin descartarlo como sospechoso', () {
      final lectura = InterpretadorPushRemota.leer({'type': 'tipo_del_futuro', 'algo_id': _pedido});

      expect(
        lectura,
        isA<PushIgnorada>().having((l) => l.motivo, 'motivo', MotivoPushIgnorada.tipoDesconocido),
      );
    });

    test('dado `pedido_autorizado` sin el pedido, entonces se ignora', () {
      final lectura = InterpretadorPushRemota.leer({'type': 'pedido_autorizado'});

      expect(
        lectura,
        isA<PushIgnorada>().having((l) => l.motivo, 'motivo', MotivoPushIgnorada.sinEntidad),
      );
    });

    test('dado un payload vacío, entonces se ignora', () {
      expect(InterpretadorPushRemota.leer({}), isA<PushIgnorada>());
    });
  });

  group('los tipos del contrato (backend-supabase#237)', () {
    const campania = '9b2e7f1a-3c4d-4e5f-8a6b-7c8d9e0f1a2b';

    for (final (tipo, clave) in [
      ('ticket_validado', 'ticket_id'),
      ('ticket_rechazado', 'ticket_id'),
      ('cuota_pendiente', 'agenda_id'),
    ]) {
      test('dado `$tipo` con `$clave`, entonces es una push válida del tipo', () {
        final lectura = InterpretadorPushRemota.leer({
          'type': tipo,
          clave: _pedido,
          'event_id': _evento,
        });

        final push = (lectura as PushLeida).push;
        expect(push.tipo.codigo, tipo);
        expect(push.entidadId, _pedido);
        expect(push.eventoId, _evento);
      });

      test('dado `$tipo` sin `$clave`, entonces se ignora', () {
        final lectura = InterpretadorPushRemota.leer({'type': tipo});

        expect(
          lectura,
          isA<PushIgnorada>().having((l) => l.motivo, 'motivo', MotivoPushIgnorada.sinEntidad),
        );
      });
    }

    test(
      'dado `cuota_pendiente` con `cuota_id` y sin `agenda_id` (la clave descartada), entonces se '
      'ignora',
      () {
        final lectura = InterpretadorPushRemota.leer({
          'type': 'cuota_pendiente',
          'cuota_id': _pedido,
        });

        expect(lectura, isA<PushIgnorada>());
      },
    );

    test('dado `asignacion_campania` con campaña y zona, entonces trae los dos ids', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'asignacion_campania',
        'campania_id': campania,
        'zona_id': _pedido,
      });

      final push = (lectura as PushLeida).push;
      expect(push.entidadId, campania);
      expect(push.entidadOpcionalId, _pedido);
      expect(push.eventoId, 'asignacion_campania:$campania:$_pedido');
    });

    test('dado `asignacion_campania` sin zona, entonces la zona queda en null', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'asignacion_campania',
        'campania_id': campania,
      });

      final push = (lectura as PushLeida).push;
      expect(push.entidadOpcionalId, isNull);
      expect(push.eventoId, 'asignacion_campania:$campania');
    });

    test(
      'dado `asignacion_campania` con una zona que no es un UUID, entonces es un dato personal',
      () {
        final lectura = InterpretadorPushRemota.leer({
          'type': 'asignacion_campania',
          'campania_id': campania,
          'zona_id': 'Cerro Norte',
        });

        expect((lectura as PushConDatosPersonales).campos, ['zona_id']);
      },
    );

    test('dado `agenda_manana` sin ningún id, entonces es válida (no pide entidad)', () {
      final lectura = InterpretadorPushRemota.leer({'type': 'agenda_manana', 'event_id': _evento});

      final push = (lectura as PushLeida).push;
      expect(push.entidadId, isNull);
      expect(push.eventoId, _evento);
    });

    test('dado `agenda_manana` sin `event_id`, entonces el evento es del día en que llegó', () {
      final lectura = InterpretadorPushRemota.leer({
        'type': 'agenda_manana',
      }, ahora: DateTime(2026, 11, 9, 21));

      expect((lectura as PushLeida).push.eventoId, 'agenda_manana:2026-11-09');
    });

    test('dado `agenda_manana` con un campo de más, entonces es un dato personal', () {
      final lectura = InterpretadorPushRemota.leer({'type': 'agenda_manana', 'visitas': '3'});

      expect((lectura as PushConDatosPersonales).campos, ['visitas']);
    });
  });
}
