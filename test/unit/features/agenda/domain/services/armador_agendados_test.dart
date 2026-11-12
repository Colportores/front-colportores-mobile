// La hoja «Agendados» del mapa (vista 06, 06C·03, #407): qué visitas muestra, cómo las cuenta por
// tipo y qué ubicaciones deja sin atenuar en el mapa.
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/armador_agendados.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/agenda_items_falsos.dart';

void main() {
  final ahora = DateTime(2026, 11, 11, 14, 35);
  DateTime hoyA(int hora, [int minuto = 0]) => DateTime(2026, 11, 11, hora, minuto);

  ItemAgenda conAlternativa(ItemAgenda item, String ubicacionId) => ItemAgenda(
    agenda: item.agenda,
    personaNombre: item.personaNombre,
    personaApellido: item.personaApellido,
    casa: item.casa,
    alternativa: DireccionDeAgenda(
      ubicacionId: ubicacionId,
      tipo: TipoUbicacion.casa,
      calle: 'Rivera',
      numero: '3920',
    ),
  );

  // El canvas 06C·03: una atrasada, tres de hoy y una de mañana.
  final canvas = [
    itemAgenda(
      'atr',
      DateTime(2026, 11, 10, 18),
      tipo: TipoAgenda.cobranza,
      ubicacionId: 'u-rivera',
    ),
    itemAgenda('c1', hoyA(15), tipo: TipoAgenda.cobranza, ubicacionId: 'u-italia'),
    itemAgenda('e1', hoyA(16, 30), ubicacionId: 'u-comercio'),
    itemAgenda('n1', hoyA(18), tipo: TipoAgenda.entrega, ubicacionId: 'u-michigan'),
    itemAgenda('e2', DateTime(2026, 11, 12, 10), ubicacionId: 'u-mataojo'),
  ];

  group('ArmadorAgendados', () {
    test('cuenta todas y por tipo, con las atrasadas, y agrupa como la Agenda', () {
      final hoja = ArmadorAgendados.armar(canvas, null, ahora);

      expect(hoja.cuentas.todas, 5);
      expect(hoja.cuentas.de(TipoAgenda.cobranza), 2);
      expect(hoja.cuentas.de(TipoAgenda.entrevista), 2);
      expect(hoja.cuentas.de(TipoAgenda.entrega), 1);
      expect(hoja.vista.atrasadas.map((i) => i.agenda.id), ['atr']);
      expect(hoja.vista.dias, hasLength(2));
      expect(hoja.vista.dias.first.items.map((i) => i.agenda.id), ['c1', 'e1', 'n1']);
      expect(hoja.vista.dias.last.items.map((i) => i.agenda.id), ['e2']);
      expect(hoja.ubicaciones, {'u-rivera', 'u-italia', 'u-comercio', 'u-michigan', 'u-mataojo'});
    });

    test('el chip de tipo filtra la lista y las ubicaciones, pero no las cuentas de los chips', () {
      final hoja = ArmadorAgendados.armar(canvas, TipoAgenda.cobranza, ahora);

      expect(hoja.vista.atrasadas.map((i) => i.agenda.id), ['atr']);
      expect(hoja.vista.dias.single.items.map((i) => i.agenda.id), ['c1']);
      expect(hoja.ubicaciones, {'u-rivera', 'u-italia'});
      expect(hoja.cuentas.todas, 5);
      expect(hoja.cuentas.de(TipoAgenda.entrevista), 2);
    });

    test(
      'un tipo sin visitas deja la lista vacía y las cuentas intactas (filtro sin resultados)',
      () {
        final sinEntregas = [
          for (final i in canvas)
            if (i.agenda.tipo != TipoAgenda.entrega) i,
        ];
        final hoja = ArmadorAgendados.armar(sinEntregas, TipoAgenda.entrega, ahora);

        expect(hoja.vista.estaVacia, isTrue);
        expect(hoja.ubicaciones, isEmpty);
        expect(hoja.cuentas.todas, 4);
        expect(hoja.cuentas.de(TipoAgenda.entrega), 0);
      },
    );

    test('solo cuentan las pendientes: cumplidas, canceladas, no cumplidas y borradas no son '
        '«agendados»', () {
      final hoja = ArmadorAgendados.armar(
        [
          ...canvas,
          itemAgenda('cum', hoyA(9), estado: EstadoAgenda.cumplida, ubicacionId: 'u-x'),
          itemAgenda('can', hoyA(19), estado: EstadoAgenda.cancelada, ubicacionId: 'u-y'),
          itemAgenda('noc', hoyA(10), estado: EstadoAgenda.noCumplida, ubicacionId: 'u-z'),
          itemAgenda('bor', hoyA(20), borrada: DateTime.utc(2026, 11, 1), ubicacionId: 'u-w'),
        ],
        null,
        ahora,
      );

      expect(hoja.cuentas.todas, 5);
      expect(hoja.ubicaciones, isNot(contains('u-x')));
      expect(hoja.ubicaciones.intersection({'u-y', 'u-z', 'u-w'}), isEmpty);
    });

    test('la de hoy cuya hora ya pasó sigue en HOY, no en atrasados (como la Agenda)', () {
      final hoja = ArmadorAgendados.armar([itemAgenda('pasada', hoyA(9))], null, ahora);

      expect(hoja.vista.atrasadas, isEmpty);
      expect(hoja.vista.dias.single.esHoy, isTrue);
    });

    test(
      'la ubicación de una cobranza con dirección alternativa es la alternativa (a donde se va)',
      () {
        final item = conAlternativa(
          itemAgenda('alt', hoyA(17), tipo: TipoAgenda.cobranza, ubicacionId: 'u-casa'),
          'u-trabajo',
        );

        final hoja = ArmadorAgendados.armar([item], null, ahora);

        expect(hoja.ubicaciones, {'u-trabajo'});
      },
    );

    test('una visita sin dirección en el teléfono se lista, pero no marca ninguna casa', () {
      final hoja = ArmadorAgendados.armar(
        [itemAgenda('sin', hoyA(17), conCasa: false)],
        null,
        ahora,
      );

      expect(hoja.cuentas.todas, 1);
      expect(hoja.ubicaciones, isEmpty);
    });

    test('sin visitas: todo vacío', () {
      final hoja = ArmadorAgendados.armar(const [], null, ahora);

      expect(hoja, VistaAgendados.vacia);
      expect(hoja.cuentas.todas, 0);
    });

    test('dos visitas en la misma casa la cuentan una vez en el mapa', () {
      final hoja = ArmadorAgendados.armar(
        [
          itemAgenda('a', hoyA(15), ubicacionId: 'u-1'),
          itemAgenda('b', hoyA(16), tipo: TipoAgenda.cobranza, ubicacionId: 'u-1'),
        ],
        null,
        ahora,
      );

      expect(hoja.cuentas.todas, 2);
      expect(hoja.ubicaciones, {'u-1'});
    });
  });
}
