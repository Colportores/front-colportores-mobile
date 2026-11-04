// HU-VIS-002 (#508, «Rango filtro»): la lista de la campaña en curso que arma el armador con un estado
// cerrado o «Todas»: filtros, orden de la más nueva a la más vieja, agrupado por día y cortado en
// páginas para «Ver más».
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/filtros_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/armador_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/formato_agenda.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/agenda_items_falsos.dart';

void main() {
  // Miércoles 28/10/2026, 10:00 hora local.
  final ahora = DateTime(2026, 10, 28, 10);
  const cumplidas = FiltrosAgenda(estado: EstadoFiltroAgenda.cumplidas);
  const todas = FiltrosAgenda(estado: EstadoFiltroAgenda.todas);

  ItemAgenda item(
    String id,
    DateTime cuando, {
    EstadoAgenda estado = EstadoAgenda.cumplida,
    TipoAgenda tipo = TipoAgenda.entrevista,
    DateTime? borrada,
  }) => itemAgenda(id, cuando, estado: estado, tipo: tipo, borrada: borrada);

  List<String> ids(List<ItemAgenda> l) => [for (final i in l) i.agenda.id];

  group('EstadoFiltroAgenda.miraLaCampania', () {
    test('solo «Pendientes» queda en la ventana de 7 días', () {
      expect(EstadoFiltroAgenda.pendientes.miraLaCampania, isFalse);
      for (final e in EstadoFiltroAgenda.values.where((e) => e != EstadoFiltroAgenda.pendientes)) {
        expect(e.miraLaCampania, isTrue, reason: e.name);
      }
    });
  });

  group('ArmadorAgenda.armarCampania', () {
    test('trae las de hace más de 7 días, de la más nueva a la más vieja', () {
      final vista = ArmadorAgenda.armarCampania(
        [
          item('vieja', DateTime(2026, 9, 1, 9)),
          item('ayer', DateTime(2026, 10, 27, 16)),
          item('mitad', DateTime(2026, 10, 10, 9)),
        ],
        cumplidas,
        ahora,
      );

      expect(ids([for (final d in vista.dias) ...d.items]), ['ayer', 'mitad', 'vieja']);
      expect(vista.deCampania, isTrue);
      expect(vista.hayMas, isFalse);
      expect(vista.atrasadas, isEmpty);
    });

    test('cada estado cerrado deja solo el suyo', () {
      final items = [
        item('cumplida', DateTime(2026, 10, 1, 9)),
        item('no', DateTime(2026, 10, 2, 9), estado: EstadoAgenda.noCumplida),
        item('canc', DateTime(2026, 10, 3, 9), estado: EstadoAgenda.cancelada),
        item('prog', DateTime(2026, 10, 4, 9), estado: EstadoAgenda.programada),
      ];
      List<String> con(EstadoFiltroAgenda e) => ids([
        for (final d in ArmadorAgenda.armarCampania(items, FiltrosAgenda(estado: e), ahora).dias)
          ...d.items,
      ]);

      expect(con(EstadoFiltroAgenda.cumplidas), ['cumplida']);
      expect(con(EstadoFiltroAgenda.noCumplidas), ['no']);
      expect(con(EstadoFiltroAgenda.canceladas), ['canc']);
      expect(con(EstadoFiltroAgenda.todas), ['prog', 'canc', 'no', 'cumplida']);
    });

    test('«Todas» incluye lo que viene después de hoy', () {
      final vista = ArmadorAgenda.armarCampania(
        [item('futura', DateTime(2026, 12, 1, 9), estado: EstadoAgenda.programada)],
        todas,
        ahora,
      );

      expect(vista.dias.single.diasDesdeHoy, 34);
      expect(ids(vista.dias.single.items), ['futura']);
    });

    test('el filtro de tipo se combina con el de estado', () {
      final vista = ArmadorAgenda.armarCampania(
        [
          item('e', DateTime(2026, 10, 1, 9)),
          item('c', DateTime(2026, 10, 2, 9), tipo: TipoAgenda.cobranza),
        ],
        const FiltrosAgenda(tipo: TipoAgenda.cobranza, estado: EstadoFiltroAgenda.cumplidas),
        ahora,
      );

      expect(ids([for (final d in vista.dias) ...d.items]), ['c']);
    });

    test('deja afuera las bajas', () {
      final vista = ArmadorAgenda.armarCampania(
        [item('baja', DateTime(2026, 10, 1, 9), borrada: DateTime(2026, 10, 2))],
        cumplidas,
        ahora,
      );

      expect(vista.estaVacia, isTrue);
    });

    test(
      'agrupa por día, del más nuevo al más viejo, y dentro del día de la más tarde a la más temprana',
      () {
        final vista = ArmadorAgenda.armarCampania(
          [
            item('a', DateTime(2026, 10, 20, 9)),
            item('b', DateTime(2026, 10, 20, 17)),
            item('c', DateTime(2026, 10, 21, 8)),
            item('z', DateTime(2026, 10, 20, 9)),
          ],
          cumplidas,
          ahora,
        );

        expect(vista.dias.map((d) => d.dia), [DateTime(2026, 10, 21), DateTime(2026, 10, 20)]);
        expect(ids(vista.dias.last.items), ['b', 'z', 'a']);
        expect(vista.dias.map((d) => d.diasDesdeHoy), [-7, -8]);
      },
    );

    test('corta en la página y avisa que hay más; con exactamente una página no hay más', () {
      final items = [
        for (var i = 0; i < ArmadorAgenda.tamanoPagina + 1; i++)
          item(
            'i${i.toString().padLeft(3, '0')}',
            DateTime(2026, 10, 27).subtract(Duration(hours: i)),
          ),
      ];

      final primera = ArmadorAgenda.armarCampania(items, cumplidas, ahora);
      expect(primera.total, ArmadorAgenda.tamanoPagina);
      expect(primera.hayMas, isTrue);

      final todo = ArmadorAgenda.armarCampania(
        items,
        cumplidas,
        ahora,
        limite: ArmadorAgenda.tamanoPagina + 1,
      );
      expect(todo.total, ArmadorAgenda.tamanoPagina + 1);
      expect(todo.hayMas, isFalse);

      final justa = ArmadorAgenda.armarCampania(
        items.take(ArmadorAgenda.tamanoPagina).toList(),
        cumplidas,
        ahora,
      );
      expect(justa.hayMas, isFalse);
    });

    test('el tamaño de la página es el de las listas de la app, sin un número nuevo', () {
      expect(ArmadorAgenda.tamanoPagina, 50);
    });

    test('sin agendas queda vacía', () {
      expect(ArmadorAgenda.armarCampania(const [], todas, ahora).estaVacia, isTrue);
      expect(ArmadorAgenda.armarCampania(const [], todas, ahora).hayMas, isFalse);
    });

    test('un cambio de hora no corre los días', () {
      final vista = ArmadorAgenda.armarCampania(
        [item('a', DateTime(2026, 10, 25, 0, 30)), item('b', DateTime(2026, 10, 24, 23, 30))],
        cumplidas,
        ahora,
      );

      expect(vista.dias.map((d) => d.dia), [DateTime(2026, 10, 25), DateTime(2026, 10, 24)]);
    });
  });

  group('FormatoAgenda.subtituloDe', () {
    test('«En esta campaña» con un estado cerrado o «Todas»; la ventana con «Pendientes»', () {
      expect(FormatoAgenda.subtituloDe(FiltrosAgenda.porDefecto), 'Hoy y los próximos 7 días');
      expect(FormatoAgenda.subtituloDe(cumplidas), 'En esta campaña');
      expect(FormatoAgenda.subtituloDe(todas), 'En esta campaña');
      expect(
        FormatoAgenda.subtituloDe(const FiltrosAgenda(estado: EstadoFiltroAgenda.canceladas)),
        'En esta campaña',
      );
    });
  });
}
