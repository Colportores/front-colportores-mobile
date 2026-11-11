// HU-NOT-003 (#187) — el texto de cada aviso que nace de una push y cómo se guarda: los fijos
// (pedido, ticket, cuota) y los que llevan un dato de la base local (asignación, agenda de mañana).
import 'package:colportores_mobile/core/notificaciones/push_remotas.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/recibir_push_remota_use_case.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/auditoria_push_en_memoria.dart';
import '../../../helpers/datos_locales_de_push_en_memoria.dart';
import '../../../helpers/historial_notificaciones_falsos.dart';

const _id = '3f2b8c1e-9a4d-4e7b-8c1a-5d6e7f8a9b0c';
const _zona = '7c9e6679-7425-40de-944b-e07fc1f90ae7';
const _evento = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';

void main() {
  late HistorialEnMemoria historial;
  late AuditoriaPushEnMemoria auditoria;
  late DatosLocalesDePushEnMemoria datos;
  late RecibirPushRemotaUseCase recibir;

  setUp(() {
    historial = HistorialEnMemoria();
    auditoria = AuditoriaPushEnMemoria();
    datos = DatosLocalesDePushEnMemoria();
    recibir = RecibirPushRemotaUseCase(
      RegistrarNotificacionUseCase(historial, ahora: () => ahoraDelCentro),
      auditoria,
      datos,
      ahora: () => ahoraDelCentro,
    );
  });

  Future<String> titulo(Map<String, Object?> payload) async {
    final r = await recibir(MensajePush(payload));
    final nueva = r.getOrElse(() => throw StateError('falló')) as PushNueva;
    return nueva.aviso.titulo;
  }

  group('textos fijos', () {
    final casos = <(String, String, TipoNotificacion, String)>[
      (
        'pedido_autorizado',
        'pedido_id',
        TipoNotificacion.pedidoAutorizado,
        'Tu pedido fue autorizado',
      ),
      ('ticket_validado', 'ticket_id', TipoNotificacion.ticketValidado, 'Tu ticket fue validado'),
      (
        'ticket_rechazado',
        'ticket_id',
        TipoNotificacion.ticketRechazado,
        'Tu ticket fue rechazado',
      ),
      (
        'cuota_pendiente',
        'agenda_id',
        TipoNotificacion.cuotaPendiente,
        'Tenés una cuota pendiente de cobro',
      ),
    ];
    for (final (tipo, clave, tipoDeAviso, texto) in casos) {
      test(
        'dado `$tipo`, entonces el aviso dice «$texto», sin destino, y queda sin leer',
        () async {
          final r = await recibir(MensajePush({'type': tipo, clave: _id, 'event_id': _evento}));

          final aviso = (r.getOrElse(() => throw StateError('falló')) as PushNueva).aviso;
          expect(aviso.titulo, texto);
          expect(aviso.tipo, tipoDeAviso);
          expect(aviso.destino, isNull);
          expect(aviso.leida, isFalse);
          expect(historial.filas.single.id, 'push-$_evento');
        },
      );
    }
  });

  group('asignación a campaña', () {
    test(
      'dado campaña y zona conocidas, entonces «Te asignaron la zona [zona] en [campaña].»',
      () async {
        datos
          ..campanias[_id] = 'Verano 2027'
          ..zonas[_zona] = 'Cerro Norte';

        expect(
          await titulo({'type': 'asignacion_campania', 'campania_id': _id, 'zona_id': _zona}),
          'Te asignaron la zona Cerro Norte en Verano 2027.',
        );
      },
    );

    test(
      'dado que todavía no tiene zona, entonces «Te asignaron a la campaña [campaña].»',
      () async {
        datos.campanias[_id] = 'Verano 2027';

        expect(
          await titulo({'type': 'asignacion_campania', 'campania_id': _id}),
          'Te asignaron a la campaña Verano 2027.',
        );
      },
    );

    test('dado que la zona no bajó todavía con el sync, entonces el texto sin zona', () async {
      datos.campanias[_id] = 'Verano 2027';

      expect(
        await titulo({'type': 'asignacion_campania', 'campania_id': _id, 'zona_id': _zona}),
        'Te asignaron a la campaña Verano 2027.',
      );
    });

    test(
      'dado que la campaña no bajó todavía, entonces un texto que no inventa el nombre',
      () async {
        expect(
          await titulo({'type': 'asignacion_campania', 'campania_id': _id}),
          'Te asignaron a una campaña.',
        );
      },
    );

    test(
      'dado que la base no se deja leer, entonces el aviso se guarda igual con el texto sin nombre',
      () async {
        datos.falla = true;

        expect(
          await titulo({'type': 'asignacion_campania', 'campania_id': _id}),
          'Te asignaron a una campaña.',
        );
        expect(historial.filas, hasLength(1));
      },
    );

    test('dado el mismo evento repetido sin event_id, entonces no se duplica', () async {
      datos.campanias[_id] = 'Verano 2027';
      final payload = {'type': 'asignacion_campania', 'campania_id': _id};
      await recibir(MensajePush(payload));

      final segunda = await recibir(MensajePush(payload));

      expect(segunda.getOrElse(() => throw StateError('falló')), isA<PushYaRecibida>());
      expect(historial.filas, hasLength(1));
    });
  });

  group('agenda de mañana (sin id)', () {
    test('dado 1 visita, entonces «Mañana tenés 1 visita agendada»', () async {
      datos.visitasDeManana = 1;

      expect(await titulo({'type': 'agenda_manana'}), 'Mañana tenés 1 visita agendada');
      expect(datos.ahoraConsultado, ahoraDelCentro);
    });

    test('dado 3 visitas, entonces «Mañana tenés 3 visitas agendadas»', () async {
      datos.visitasDeManana = 3;

      expect(await titulo({'type': 'agenda_manana'}), 'Mañana tenés 3 visitas agendadas');
    });

    test(
      'dado que el teléfono no tiene visitas de mañana (el sync no las bajó), entonces no inventa '
      'la cantidad',
      () async {
        expect(await titulo({'type': 'agenda_manana'}), 'Mañana tenés visitas agendadas');
      },
    );

    test('dado que la base no se deja leer, entonces el aviso se guarda igual', () async {
      datos.falla = true;

      expect(await titulo({'type': 'agenda_manana'}), 'Mañana tenés visitas agendadas');
    });

    test(
      'dado el aviso nocturno repetido el mismo día sin event_id, entonces es un solo aviso; al día '
      'siguiente, otro',
      () async {
        var hoy = DateTime(2026, 11, 9, 21);
        final recibe = RecibirPushRemotaUseCase(
          RegistrarNotificacionUseCase(historial, ahora: () => hoy),
          auditoria,
          datos,
          ahora: () => hoy,
        );

        await recibe(const MensajePush({'type': 'agenda_manana'}));
        await recibe(const MensajePush({'type': 'agenda_manana'}));
        expect(historial.filas, hasLength(1));

        hoy = DateTime(2026, 11, 10, 21);
        await recibe(const MensajePush({'type': 'agenda_manana'}));
        expect(historial.filas, hasLength(2));
      },
    );
  });
}
