// HU-VIS-002 (#508, «Rango filtro»): con un estado cerrado o «Todas» la pestaña «Agenda» mira la
// campaña en curso, de la más nueva a la más vieja, con «Ver más» y el subtítulo «En esta campaña».
// «Pendientes» sigue en hoy y los próximos 7 días. Cada filtro con agendas de hace más de 7 días, el
// «Ver más» y sus casos límite: doble toque, volver al filtro, error de lectura, datos límite y texto
// al 200 %.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/armador_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agenda.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';

/// Miércoles 28/10/2026, 10:00 (hora local).
final _base = DateTime(2026, 10, 28, 10);

/// Monta [AgendaPage] sola, con el lector falso, sobre una pantalla [alto] de alta.
Future<void> _montar(
  WidgetTester tester,
  ConsultaAgendaFalsa repo, {
  double escala = 1,
  double alto = 844,
}) async {
  tester.view.physicalSize = Size(390, alto);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultaAgendaRepositoryProvider.overrideWithValue(repo),
        relojAgendaProvider.overrideWithValue(() => _base),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const Scaffold(body: AgendaPage(colportorId: 'col-1')),
      ),
    ),
  );
  await _asentar(tester);
}

Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Cada test termina desmontando la pantalla: el temporizador del minuto se cancela en `dispose`.
void _probar(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _elegirEstado(WidgetTester tester, String actual, String nuevo) async {
  const claves = {
    'Pendientes': 'pendientes',
    'Cumplidas': 'cumplidas',
    'No cumplidas': 'noCumplidas',
    'Canceladas': 'canceladas',
    'Todas': 'todas',
  };
  await tester.tap(find.text('$actual ▾'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('agenda_estado_${claves[nuevo]}')));
  await tester.tap(find.text('Aplicar'));
  await tester.pumpAndSettle();
}

ItemAgenda _de(
  String id,
  DateTime cuando, {
  EstadoAgenda estado = EstadoAgenda.cumplida,
  TipoAgenda tipo = TipoAgenda.entrevista,
  String nombre = 'Ana',
}) => itemAgenda(id, cuando, estado: estado, tipo: tipo, nombre: nombre);

/// Lo que dejó la campaña: una cumplida de hace tres semanas, una de ayer, una no cumplida, una
/// cancelada y una programada de la semana que viene.
List<ItemAgenda> _campania() => [
  _de('vieja', DateTime(2026, 10, 7, 9), nombre: 'Vieja'),
  _de('ayer', DateTime(2026, 10, 27, 16), nombre: 'Ayer'),
  _de('no', DateTime(2026, 10, 12, 11), estado: EstadoAgenda.noCumplida, nombre: 'Nadie'),
  _de('canc', DateTime(2026, 10, 15, 18), estado: EstadoAgenda.cancelada, nombre: 'Raúl'),
  _de('prog', DateTime(2026, 11, 2, 9), estado: EstadoAgenda.programada, nombre: 'Luego'),
];

/// Los nombres de las filas, de arriba abajo.
List<String> _filas(WidgetTester tester) {
  final filas = tester.widgetList<FilaAgenda>(find.byType(FilaAgenda)).toList()
    ..sort((a, b) {
      final ya = tester.getTopLeft(find.byWidget(a)).dy;
      final yb = tester.getTopLeft(find.byWidget(b)).dy;
      return ya.compareTo(yb);
    });
  return [for (final f in filas) f.item.agenda.id];
}

void main() {
  group('Estados cerrados: la campaña, no la ventana de 7 días', () {
    _probar('«Cumplidas» muestra las de hace más de 7 días, de la más nueva a la más vieja', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(_campania());
      await _montar(tester, repo);

      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      expect(_filas(tester), ['ayer', 'vieja']);
      expect(find.text('Ninguna agenda con estos filtros'), findsNothing);
      // Lee la campaña con el día de hoy.
      expect(repo.pedidosCampania.last, (colportorId: 'col-1', hoy: DateTime(2026, 10, 28)));
    });

    _probar('«No cumplidas» y «Canceladas» también miran toda la campaña', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(_campania()));

      await _elegirEstado(tester, 'Pendientes', 'No cumplidas');
      expect(_filas(tester), ['no']);

      await _elegirEstado(tester, 'No cumplidas', 'Canceladas');
      expect(_filas(tester), ['canc']);
    });

    _probar('«Todas» muestra toda la campaña, también lo que viene, de la más nueva a la vieja', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa(_campania()));

      await _elegirEstado(tester, 'Pendientes', 'Todas');

      expect(_filas(tester), ['prog', 'ayer', 'canc', 'no', 'vieja']);
    });

    _probar('el filtro de tipo sigue valiendo en la campaña', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          ..._campania(),
          _de('cobro', DateTime(2026, 10, 9, 10), tipo: TipoAgenda.cobranza, nombre: 'Cobro'),
        ]),
      );
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');
      expect(_filas(tester), ['ayer', 'cobro', 'vieja']);

      await tester.tap(find.text('Cobranzas'));
      await tester.pumpAndSettle();

      expect(_filas(tester), ['cobro']);
    });

    _probar('el subtítulo dice «En esta campaña» y «Pendientes» vuelve a la ventana de 7 días', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(_campania());
      await _montar(tester, repo);
      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget);
      expect(find.text('En esta campaña'), findsNothing);
      expect(repo.pedidosCampania, isEmpty);

      await _elegirEstado(tester, 'Pendientes', 'Todas');
      expect(find.text('En esta campaña'), findsOneWidget);
      expect(find.text('Hoy y los próximos 7 días'), findsNothing);

      await _elegirEstado(tester, 'Todas', 'Pendientes');
      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget);
      expect(find.text('En esta campaña'), findsNothing);
    });

    _probar('los días van del más nuevo al más viejo, sin conteo, y cada fila lleva su fecha', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa(_campania()));

      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      expect(find.text('MARTES 27'), findsOneWidget);
      expect(find.text('MIÉRCOLES 7'), findsOneWidget);
      expect(find.textContaining('('), findsNothing);
      expect(find.textContaining('27/10'), findsOneWidget);
      expect(find.textContaining('07/10'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('MARTES 27')).dy,
        lessThan(tester.getTopLeft(find.text('MIÉRCOLES 7')).dy),
      );
    });

    _probar('«Pendientes» sigue sin leer la campaña: la ventana, con las atrasadas', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa([
        _de('atrasada', DateTime(2026, 10, 20, 9), estado: EstadoAgenda.programada),
        _de('hoy', DateTime(2026, 10, 28, 14), estado: EstadoAgenda.programada),
        _de('vieja', DateTime(2026, 10, 7, 9)),
      ]);
      await _montar(tester, repo);

      expect(_filas(tester), ['atrasada', 'hoy']);
      expect(find.text('ATRASADAS (1)'), findsOneWidget);
      expect(repo.pedidosCampania, isEmpty);
      expect(repo.pedidos, isNotEmpty);
    });
  });

  group('Estados de la lista de la campaña', () {
    _probar('sin agendas cerradas dice «Ninguna agenda con estos filtros»', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_de('prog', _base, estado: EstadoAgenda.programada)]),
      );

      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      expect(find.text('Ninguna agenda con estos filtros'), findsOneWidget);
      expect(find.text('Limpiar filtros'), findsOneWidget);
      expect(find.text('Ver más'), findsNothing);
    });

    _probar('«Limpiar filtros» vuelve a «Pendientes» y a la ventana', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_de('prog', _base, estado: EstadoAgenda.programada)]),
      );
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      await tester.tap(find.text('Limpiar filtros'));
      await tester.pumpAndSettle();

      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget);
      expect(_filas(tester), ['prog']);
    });

    _probar('cargando muestra el esqueleto y no «Ver más»', (tester) async {
      final repo = ConsultaAgendaFalsa(_campania());
      await _montar(tester, repo);
      repo.congelada = true;

      await _elegirEstado(tester, 'Pendientes', 'Todas');

      expect(find.byType(EsqueletoAgenda), findsOneWidget);
      expect(find.text('Ver más'), findsNothing);
      expect(find.text('En esta campaña'), findsOneWidget);
    });

    _probar('un error al leer la campaña dice «No pudimos leer tu agenda.» y «Reintentar» relee', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(_campania());
      await _montar(tester, repo);
      await _elegirEstado(tester, 'Pendientes', 'Todas');
      expect(repo.pedidosCampania, hasLength(1));

      repo.emitirError(StateError('disco'));
      await _asentar(tester);
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);

      repo.error = null;
      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);

      expect(find.text('No pudimos leer tu agenda.'), findsNothing);
      expect(repo.pedidosCampania, hasLength(2));
      expect(_filas(tester), isNotEmpty);
    });

    _probar('la lista se actualiza sola cuando cambia lo leído', (tester) async {
      final repo = ConsultaAgendaFalsa(_campania());
      await _montar(tester, repo);
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');
      expect(_filas(tester), ['ayer', 'vieja']);

      repo.emitir([..._campania(), _de('nueva', DateTime(2026, 10, 28, 8))]);
      await _asentar(tester);

      expect(_filas(tester), ['nueva', 'ayer', 'vieja']);
    });
  });

  group('«Ver más»', () {
    // 120 cumplidas, una por hora hacia atrás: la 0 es la más nueva.
    List<ItemAgenda> muchas(int n) => [
      for (var i = 0; i < n; i++)
        _de(
          'c${i.toString().padLeft(3, '0')}',
          DateTime(2026, 10, 28, 8).subtract(Duration(hours: i)),
        ),
    ];

    _probar('muestra una página y «Ver más» suma la siguiente hasta que no queda nada', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa(muchas(120)), alto: 30000);
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      expect(find.byType(FilaAgenda), findsNWidgets(ArmadorAgenda.tamanoPagina));
      expect(find.byKey(const ValueKey('c049')), findsOneWidget);
      expect(find.byKey(const ValueKey('c050')), findsNothing);
      expect(find.text('Ver más'), findsOneWidget);

      await tester.tap(find.text('Ver más'));
      await tester.pumpAndSettle();
      expect(find.byType(FilaAgenda), findsNWidgets(2 * ArmadorAgenda.tamanoPagina));
      expect(find.text('Ver más'), findsOneWidget);

      await tester.tap(find.text('Ver más'));
      await tester.pumpAndSettle();
      expect(find.byType(FilaAgenda), findsNWidgets(120));
      expect(find.text('Ver más'), findsNothing);
    });

    _probar('con exactamente una página no hay «Ver más»', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(muchas(ArmadorAgenda.tamanoPagina)), alto: 30000);
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      expect(find.byType(FilaAgenda), findsNWidgets(ArmadorAgenda.tamanoPagina));
      expect(find.text('Ver más'), findsNothing);
    });

    _probar('un doble toque en «Ver más» suma una sola página', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(muchas(220)), alto: 30000);
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      await tester.tap(find.text('Ver más'));
      await tester.tap(find.text('Ver más'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(FilaAgenda), findsNWidgets(2 * ArmadorAgenda.tamanoPagina));
    });

    _probar('cambiar de filtro y volver empieza otra vez por la primera página', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(muchas(120)), alto: 30000);
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');
      await tester.tap(find.text('Ver más'));
      await tester.pumpAndSettle();
      expect(find.byType(FilaAgenda), findsNWidgets(2 * ArmadorAgenda.tamanoPagina));

      await _elegirEstado(tester, 'Cumplidas', 'Canceladas');
      await _elegirEstado(tester, 'Canceladas', 'Cumplidas');

      expect(find.byType(FilaAgenda), findsNWidgets(ArmadorAgenda.tamanoPagina));
      expect(find.text('Ver más'), findsOneWidget);
    });

    _probar('«Ver más» con el texto al 200 % se alcanza y no desborda', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(muchas(80)), escala: 2);
      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      await tester.scrollUntilVisible(find.byKey(const Key('agenda_ver_mas')), 400);
      final tamano = tester.getSize(find.byKey(const Key('agenda_ver_mas')));

      expect(tamano.height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });

  group('Datos límite de la campaña', () {
    _probar('textos largos y el texto al 200 % no desbordan', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          itemAgenda(
            'larga',
            DateTime(2026, 10, 7, 9),
            estado: EstadoAgenda.cumplida,
            nombre: 'Maria de los Angeles',
            apellido: 'Fernandez de la Torre y Casal',
            calle: 'Avenida General Jose Gervasio Artigas y Bulevar',
            numero: '123456',
          ),
        ]),
        escala: 2,
      );

      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      expect(_filas(tester), ['larga']);
      expect(tester.takeException(), isNull);
    });

    _probar('una agenda de otro año se ordena después de las de este', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          _de('2025', DateTime(2025, 12, 30, 9)),
          _de('2026', DateTime(2026, 1, 2, 9)),
        ]),
      );

      await _elegirEstado(tester, 'Pendientes', 'Cumplidas');

      expect(_filas(tester), ['2026', '2025']);
    });
  });
}
