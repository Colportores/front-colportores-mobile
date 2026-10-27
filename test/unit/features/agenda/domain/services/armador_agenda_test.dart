// HU-VIS-002: la ventana «hoy + 7 días», el filtrado y el agrupado por día de la agenda.
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/filtros_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/armador_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/formato_agenda.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/agenda_items_falsos.dart';

void main() {
  // Miércoles 28/10/2026, 10:00 hora local.
  final ahora = DateTime(2026, 10, 28, 10);

  group('VentanaAgenda', () {
    test('va de la medianoche de hoy a la del día 8 (hoy y los 7 siguientes)', () {
      final v = VentanaAgenda.de(ahora);

      expect(v.inicioDeHoy, DateTime(2026, 10, 28));
      expect(v.fin, DateTime(2026, 11, 5));
      expect(v.contiene(DateTime(2026, 10, 28)), isTrue);
      expect(v.contiene(DateTime(2026, 11, 4, 23, 59)), isTrue);
      expect(v.contiene(DateTime(2026, 11, 5)), isFalse);
      expect(v.contiene(DateTime(2026, 10, 27, 23, 59)), isFalse);
    });

    test('pide a la base el mismo rango, en UTC', () {
      final v = VentanaAgenda.de(ahora);

      expect(v.desdeUtc, DateTime(2026, 10, 28).toUtc());
      expect(v.hastaUtc, DateTime(2026, 11, 5).toUtc());
      expect(v.desdeUtc.isUtc, isTrue);
    });
  });

  group('ArmadorAgenda', () {
    test('agrupa por día, con las del día en orden de hora y el desempate por id', () {
      final vista = ArmadorAgenda.armar(
        [
          itemAgenda('c', DateTime(2026, 10, 29, 9)),
          itemAgenda('b', DateTime(2026, 10, 28, 16)),
          itemAgenda('z', DateTime(2026, 10, 28, 9)),
          itemAgenda('a', DateTime(2026, 10, 28, 9)),
          itemAgenda('d', DateTime(2026, 11, 4, 12)),
        ],
        FiltrosAgenda.porDefecto,
        ahora,
      );

      expect(vista.dias.map((d) => d.diasDesdeHoy), [0, 1, 7]);
      expect(vista.dias.map((d) => d.cantidad), [3, 1, 1]);
      expect(vista.dias.first.items.map((i) => i.agenda.id), ['a', 'z', 'b']);
      expect(vista.total, 5);
      expect(vista.dias.first.esHoy, isTrue);
      expect(vista.dias[1].esManana, isTrue);
    });

    test('deja afuera de los días lo anterior a hoy, lo del día 8 y las bajas', () {
      final vista = ArmadorAgenda.armar(
        [
          itemAgenda('ayer', DateTime(2026, 10, 27, 23, 59)),
          itemAgenda('hoy', DateTime(2026, 10, 28)),
          itemAgenda('ultimo', DateTime(2026, 11, 4, 23, 59)),
          itemAgenda('dia8', DateTime(2026, 11, 5)),
          itemAgenda('baja', DateTime(2026, 10, 29, 9), borrada: DateTime.utc(2026, 10, 25)),
        ],
        FiltrosAgenda.porDefecto,
        ahora,
      );

      expect(vista.dias.expand((d) => d.items).map((i) => i.agenda.id), ['hoy', 'ultimo']);
    });

    test('por defecto muestra solo las programadas, también la de hoy que ya pasó de hora', () {
      final vista = ArmadorAgenda.armar(
        [
          itemAgenda('pasada', DateTime(2026, 10, 28, 8)),
          itemAgenda('futura', DateTime(2026, 10, 28, 18)),
          itemAgenda('cumplida', DateTime(2026, 10, 28, 9), estado: EstadoAgenda.cumplida),
          itemAgenda('no', DateTime(2026, 10, 28, 9), estado: EstadoAgenda.noCumplida),
          itemAgenda('cancelada', DateTime(2026, 10, 28, 9), estado: EstadoAgenda.cancelada),
        ],
        FiltrosAgenda.porDefecto,
        ahora,
      );

      expect(vista.dias.single.items.map((i) => i.agenda.id), ['pasada', 'futura']);
    });

    group('ATRASADAS (agendas de días anteriores sin resultado)', () {
      List<String> ids(Iterable<ItemAgenda> items) => [for (final i in items) i.agenda.id];

      test('las programadas de antes de hoy van aparte, de la más antigua a la más reciente', () {
        final vista = ArmadorAgenda.armar(
          [
            itemAgenda('hoy', DateTime(2026, 10, 28, 8)),
            itemAgenda('ayer', DateTime(2026, 10, 27, 23, 59)),
            itemAgenda('lunes-b', DateTime(2026, 10, 26, 15)),
            itemAgenda('lunes-a', DateTime(2026, 10, 26, 9)),
            itemAgenda('mes', DateTime(2026, 9, 30, 12)),
          ],
          FiltrosAgenda.porDefecto,
          ahora,
        );

        expect(ids(vista.atrasadas), ['mes', 'lunes-a', 'lunes-b', 'ayer']);
        expect(ids(vista.dias.expand((d) => d.items)), ['hoy']);
        expect(vista.total, 5);
        expect(vista.estaVacia, isFalse);
      });

      test('la de hoy cuya hora ya pasó sigue en HOY, no en las atrasadas', () {
        final vista = ArmadorAgenda.armar(
          [
            itemAgenda('hoy-0000', DateTime(2026, 10, 28)),
            itemAgenda('hoy', DateTime(2026, 10, 28, 8)),
          ],
          FiltrosAgenda.porDefecto,
          ahora,
        );

        expect(vista.atrasadas, isEmpty);
        expect(ids(vista.dias.single.items), ['hoy-0000', 'hoy']);
      });

      test(
        'solo hay atrasadas si están programadas: lo cerrado y las bajas de ayer no cuentan',
        () {
          final vista = ArmadorAgenda.armar(
            [
              itemAgenda('cumplida', DateTime(2026, 10, 27, 9), estado: EstadoAgenda.cumplida),
              itemAgenda('no', DateTime(2026, 10, 27, 10), estado: EstadoAgenda.noCumplida),
              itemAgenda('cancelada', DateTime(2026, 10, 27, 11), estado: EstadoAgenda.cancelada),
              itemAgenda('baja', DateTime(2026, 10, 27, 12), borrada: DateTime.utc(2026, 10, 25)),
            ],
            FiltrosAgenda.porDefecto,
            ahora,
          );

          expect(vista.atrasadas, isEmpty);
          expect(vista.estaVacia, isTrue);
        },
      );

      test('si lo único que hay es una atrasada, la vista no está vacía', () {
        final vista = ArmadorAgenda.armar(
          [itemAgenda('ayer', DateTime(2026, 10, 27, 9))],
          FiltrosAgenda.porDefecto,
          ahora,
        );

        expect(vista.dias, isEmpty);
        expect(vista.estaVacia, isFalse);
      });

      test(
        'respetan el filtro de tipo, y los de estado que no son pendientes las dejan afuera',
        () {
          final items = [
            itemAgenda('e', DateTime(2026, 10, 27, 9)),
            itemAgenda('c', DateTime(2026, 10, 27, 11), tipo: TipoAgenda.cobranza),
          ];

          expect(
            ids(
              ArmadorAgenda.armar(
                items,
                const FiltrosAgenda(tipo: TipoAgenda.cobranza),
                ahora,
              ).atrasadas,
            ),
            ['c'],
          );
          expect(
            ids(
              ArmadorAgenda.armar(
                items,
                const FiltrosAgenda(tipo: TipoAgenda.entrevista),
                ahora,
              ).atrasadas,
            ),
            ['e'],
          );
          // «Todas» también las muestra (siguen pendientes); «Cumplidas» y las demás, no.
          expect(
            ids(
              ArmadorAgenda.armar(
                items,
                const FiltrosAgenda(estado: EstadoFiltroAgenda.todas),
                ahora,
              ).atrasadas,
            ),
            ['e', 'c'],
          );
          for (final estado in [
            EstadoFiltroAgenda.cumplidas,
            EstadoFiltroAgenda.noCumplidas,
            EstadoFiltroAgenda.canceladas,
          ]) {
            expect(
              ArmadorAgenda.armar(items, FiltrosAgenda(estado: estado), ahora).atrasadas,
              isEmpty,
            );
          }
        },
      );

      test('al pasar la medianoche, la de hoy pasa a atrasada', () {
        final items = [itemAgenda('hoy', DateTime(2026, 10, 28, 20))];

        expect(ArmadorAgenda.armar(items, FiltrosAgenda.porDefecto, ahora).atrasadas, isEmpty);
        final manana = ArmadorAgenda.armar(
          items,
          FiltrosAgenda.porDefecto,
          DateTime(2026, 10, 29, 0, 1),
        );
        expect(ids(manana.atrasadas), ['hoy']);
        expect(manana.dias, isEmpty);
      });
    });

    test('filtra por tipo', () {
      final items = [
        itemAgenda('e', DateTime(2026, 10, 28, 9)),
        itemAgenda('c', DateTime(2026, 10, 28, 11), tipo: TipoAgenda.cobranza),
      ];

      final cobranzas = ArmadorAgenda.armar(
        items,
        const FiltrosAgenda(tipo: TipoAgenda.cobranza),
        ahora,
      );
      final entrevistas = ArmadorAgenda.armar(
        items,
        const FiltrosAgenda(tipo: TipoAgenda.entrevista),
        ahora,
      );

      expect(cobranzas.dias.single.items.map((i) => i.agenda.id), ['c']);
      expect(entrevistas.dias.single.items.map((i) => i.agenda.id), ['e']);
    });

    test('filtra por cada estado y «Todas» las muestra a todas', () {
      final items = [
        for (final e in EstadoAgenda.values)
          itemAgenda(e.name, DateTime(2026, 10, 29, 9), estado: e),
      ];
      List<String> ids(EstadoFiltroAgenda f) => ArmadorAgenda.armar(
        items,
        FiltrosAgenda(estado: f),
        ahora,
      ).dias.expand((d) => d.items).map((i) => i.agenda.id).toList();

      expect(ids(EstadoFiltroAgenda.pendientes), ['programada']);
      expect(ids(EstadoFiltroAgenda.cumplidas), ['cumplida']);
      expect(ids(EstadoFiltroAgenda.noCumplidas), ['noCumplida']);
      expect(ids(EstadoFiltroAgenda.canceladas), ['cancelada']);
      expect(ids(EstadoFiltroAgenda.todas), hasLength(4));
    });

    test('sin nada que mostrar devuelve la vista vacía', () {
      expect(ArmadorAgenda.armar([], FiltrosAgenda.porDefecto, ahora).estaVacia, isTrue);
    });

    test('con 500 agendas en un día las junta en un solo grupo', () {
      final items = [
        for (var i = 0; i < 500; i++)
          itemAgenda('a${i.toString().padLeft(3, '0')}', DateTime(2026, 10, 30, 8, i % 60)),
      ];

      final vista = ArmadorAgenda.armar(items, FiltrosAgenda.porDefecto, ahora);

      expect(vista.dias, hasLength(1));
      expect(vista.dias.single.cantidad, 500);
    });
  });

  group('ItemAgenda.estaVencida', () {
    test('vence cuando la hora ya pasó, no antes ni justo en la hora', () {
      expect(itemAgenda('a', DateTime(2026, 10, 28, 9, 59, 59)).estaVencida(ahora), isTrue);
      expect(itemAgenda('a', DateTime(2026, 10, 28, 10)).estaVencida(ahora), isFalse);
      expect(itemAgenda('a', DateTime(2026, 10, 28, 10, 1)).estaVencida(ahora), isFalse);
    });

    test('solo vence la que sigue programada', () {
      final pasada = DateTime(2026, 10, 28, 8);

      for (final e in EstadoAgenda.values.where((e) => e != EstadoAgenda.programada)) {
        expect(itemAgenda('a', pasada, estado: e).estaVencida(ahora), isFalse, reason: e.name);
      }
    });
  });

  group('FiltrosAgenda', () {
    test('los de la primera vez son «Todas» y «Pendientes»', () {
      expect(FiltrosAgenda.porDefecto.tipo, isNull);
      expect(FiltrosAgenda.porDefecto.estado, EstadoFiltroAgenda.pendientes);
      expect(FiltrosAgenda.porDefecto.esPorDefecto, isTrue);
      expect(FiltrosAgenda.porDefecto.conTipo(TipoAgenda.cobranza).esPorDefecto, isFalse);
      expect(FiltrosAgenda.porDefecto.conEstado(EstadoFiltroAgenda.todas).esPorDefecto, isFalse);
    });
  });

  group('FormatoAgenda', () {
    test('los rótulos del día dicen HOY y MAÑANA, y llevan el conteo', () {
      final vista = ArmadorAgenda.armar(
        [
          itemAgenda('a', DateTime(2026, 10, 28, 9)),
          itemAgenda('b', DateTime(2026, 10, 28, 10)),
          itemAgenda('c', DateTime(2026, 10, 29, 9)),
          itemAgenda('d', DateTime(2026, 10, 31, 9)),
        ],
        FiltrosAgenda.porDefecto,
        ahora,
      );

      expect(FormatoAgenda.rotuloDelDia(vista.dias[0]), 'HOY · MIÉRCOLES 28');
      expect(FormatoAgenda.rotuloDelDia(vista.dias[1]), 'MAÑANA · JUEVES 29');
      expect(FormatoAgenda.rotuloDelDia(vista.dias[2]), 'SÁBADO 31');
      expect(FormatoAgenda.rotuloConConteo(vista.dias[0]), 'HOY · MIÉRCOLES 28 (2)');
    });

    test('la dirección lleva el depto solo en un edificio', () {
      final edificio = itemAgenda(
        'a',
        DateTime(2026, 10, 28, 9),
        tipoUbicacion: TipoUbicacion.edificio,
        numeroDepto: '4B',
      );
      final casa = itemAgenda('b', DateTime(2026, 10, 28, 9), numeroDepto: '4B');
      final sinNumero = itemAgenda('c', DateTime(2026, 10, 28, 9), numero: null);
      final sinDireccion = itemAgenda('d', DateTime(2026, 10, 28, 9), conCasa: false);

      expect(FormatoAgenda.direccion(edificio), 'Av. Italia 1234 · Depto 4B');
      expect(FormatoAgenda.direccion(casa), 'Av. Italia 1234');
      expect(FormatoAgenda.direccion(sinNumero), 'Av. Italia');
      expect(FormatoAgenda.direccion(sinDireccion), isNull);
    });

    test('sin persona el título es la dirección; sin nada, «Visita sin datos»', () {
      final sinPersona = itemAgenda('a', DateTime(2026, 10, 28, 9), nombre: null, apellido: null);
      final vacia = itemAgenda(
        'b',
        DateTime(2026, 10, 28, 9),
        nombre: null,
        apellido: null,
        conCasa: false,
      );

      expect(FormatoAgenda.titulo(sinPersona), 'Av. Italia 1234');
      expect(FormatoAgenda.subtitulo(sinPersona), isNull);
      expect(FormatoAgenda.titulo(vacia), 'Visita sin datos');
    });

    test('el cierre dice cuándo se canceló, cumplió o no se cumplió', () {
      final cancelada = itemAgenda(
        'a',
        DateTime(2026, 10, 28, 9),
        estado: EstadoAgenda.cancelada,
        actualizada: DateTime(2026, 10, 22, 12),
      );

      expect(FormatoAgenda.cierre(cancelada), 'Cancelada el 22/10');
      expect(FormatoAgenda.cierre(itemAgenda('b', DateTime(2026, 10, 28, 9))), isNull);
    });

    test('el nombre de la persona no aparece en el texto de depuración', () {
      final item = itemAgenda('a', DateTime(2026, 10, 28, 9), nombre: 'Marta', apellido: 'Suárez');

      expect(item.toString(), isNot(contains('Marta')));
      expect(item.toString(), isNot(contains('Suárez')));
    });
  });
}
