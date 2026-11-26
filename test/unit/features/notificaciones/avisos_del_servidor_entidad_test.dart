// HU-NOT-004 / #516: lo que se guarda en `usuario.notif_preferences` y cómo se lee.
import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HoraDelAviso', () {
    test('lee «HH:MM» de 24 h y lo escribe igual', () {
      expect(HoraDelAviso.interpretar('09:00'), const HoraDelAviso(9, 0));
      expect(HoraDelAviso.interpretar('23:59')!.texto, '23:59');
      expect(const HoraDelAviso(7, 5).texto, '07:05');
      expect(HoraDelAviso.interpretar('00:00')!.texto, '00:00');
    });

    test('lo que no tiene esa forma no es una hora', () {
      for (final mal in [
        '9:00',
        '24:00',
        '12:60',
        '12:5',
        '',
        ' 09:00',
        '09:00 ',
        '09-00',
        'xx:yy',
      ]) {
        expect(HoraDelAviso.interpretar(mal), isNull, reason: mal);
      }
      expect(HoraDelAviso.interpretar(900), isNull);
      expect(HoraDelAviso.interpretar(null), isNull);
      expect(HoraDelAviso.interpretar(const ['09:00']), isNull);
    });

    test('los valores de siempre son 09:00 (cuotas) y 20:00 (agenda)', () {
      expect(HoraDelAviso.cuotaPorDefecto.texto, '09:00');
      expect(HoraDelAviso.agendaPorDefecto.texto, '20:00');
    });

    test('se ordenan por hora del día', () {
      expect(const HoraDelAviso(9, 0).compareTo(const HoraDelAviso(9, 1)), lessThan(0));
      expect(const HoraDelAviso(20, 0).compareTo(const HoraDelAviso(9, 59)), greaterThan(0));
    });
  });

  group('AvisosDelServidor.desdeJson', () {
    test(
      'null, algo que no es un objeto o un objeto vacío: todo prendido y las horas de siempre',
      () {
        for (final json in [null, 'hola', 3, const <Object?>[], const <String, Object?>{}]) {
          expect(AvisosDelServidor.desdeJson(json), const AvisosDelServidor(), reason: '$json');
        }
      },
    );

    test('lee los interruptores y las horas', () {
      final avisos = AvisosDelServidor.desdeJson(const {
        'pedidos': false,
        'tickets': true,
        'cuotas': false,
        'asignaciones': false,
        'agenda': false,
        'hora_cuota': '07:30',
        'hora_agenda': '21:15',
      });
      expect(avisos.pedidos, isFalse);
      expect(avisos.tickets, isTrue);
      expect(avisos.cuotas, isFalse);
      expect(avisos.asignaciones, isFalse);
      expect(avisos.agenda, isFalse);
      expect(avisos.horaCuota, const HoraDelAviso(7, 30));
      expect(avisos.horaAgenda, const HoraDelAviso(21, 15));
    });

    test(
      'una clave que falta o que no es booleana cuenta como prendida; una hora ilegible, la de siempre',
      () {
        final avisos = AvisosDelServidor.desdeJson(const {
          'pedidos': 'no',
          'tickets': 0,
          'hora_cuota': '9:00',
          'hora_agenda': 2000,
        });
        expect(avisos, const AvisosDelServidor());
      },
    );

    test('conserva las claves que esta versión no conoce', () {
      final avisos = AvisosDelServidor.desdeJson(const {
        'cuotas': false,
        'promociones': true,
        'version': 3,
        'anidado': {'a': 1},
      });
      expect(avisos.otras, {
        'promociones': true,
        'version': 3,
        'anidado': {'a': 1},
      });
      expect(avisos.aJson()['promociones'], isTrue);
      expect(avisos.aJson()['version'], 3);
      expect(avisos.aJson()['anidado'], {'a': 1});
    });
  });

  group('AvisosDelServidor.aJson', () {
    test('manda el objeto entero, con las horas en «HH:MM»', () {
      expect(const AvisosDelServidor().aJson(), {
        'pedidos': true,
        'tickets': true,
        'cuotas': true,
        'asignaciones': true,
        'agenda': true,
        'hora_cuota': '09:00',
        'hora_agenda': '20:00',
      });
    });

    test('ida y vuelta sin perder nada', () {
      const avisos = AvisosDelServidor(
        pedidos: false,
        cuotas: false,
        agenda: false,
        horaCuota: HoraDelAviso(6, 5),
        horaAgenda: HoraDelAviso(23, 45),
        otras: {'x': 1},
      );
      expect(AvisosDelServidor.desdeJson(avisos.aJson()), avisos);
    });

    test('lo que el servidor valida (forma de la hora) lo cumple siempre', () {
      final forma = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');
      for (var h = 0; h < 24; h++) {
        for (var m = 0; m < 60; m += 7) {
          final json = AvisosDelServidor(horaCuota: HoraDelAviso(h, m)).aJson();
          expect(forma.hasMatch(json['hora_cuota']! as String), isTrue);
        }
      }
    });

    test('una clave desconocida no pisa a las conocidas', () {
      final avisos = AvisosDelServidor.desdeJson(const {'pedidos': false, 'otra': 1});
      final json = avisos.copyWith(pedidos: true).aJson();
      expect(json['pedidos'], isTrue);
      expect(json['otra'], 1);
    });
  });

  group('cambiosSobre', () {
    test('aplica solo lo que difiere de la base y deja lo demás como está en destino', () {
      const base = AvisosDelServidor();
      final pedido = base.copyWith(tickets: false, horaAgenda: const HoraDelAviso(19, 30));
      const destino = AvisosDelServidor(
        pedidos: false,
        horaCuota: HoraDelAviso(7, 0),
        otras: {'nueva': 1},
      );
      final r = pedido.cambiosSobre(base: base, sobre: destino);
      expect(r.pedidos, isFalse);
      expect(r.tickets, isFalse);
      expect(r.horaCuota, const HoraDelAviso(7, 0));
      expect(r.horaAgenda, const HoraDelAviso(19, 30));
      expect(r.otras, {'nueva': 1});
    });

    test('sin cambios respecto de la base devuelve el destino', () {
      const base = AvisosDelServidor();
      const destino = AvisosDelServidor(cuotas: false);
      expect(base.cambiosSobre(base: base, sobre: destino), destino);
    });
  });
}
