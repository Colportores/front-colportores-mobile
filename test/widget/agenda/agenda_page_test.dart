// HU-VIS-002 (vista 23B): la pestaña «Agenda». Un test por artboard (23B·01 a 23B·09 y la hoja
// «Estado») y por caso límite de cada flujo: doble toque, falla a mitad de la acción, acciones
// seguidas, volver a la pestaña, datos límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agenda.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';

/// Miércoles 28/10/2026, 10:00 (hora local).
final _base = DateTime(2026, 10, 28, 10);

const _hoyConDos = 'HOY · MIÉRCOLES 28 (2)';

/// El reloj de un test: se le cambia la hora a mano.
final class _Reloj {
  _Reloj(this.ahora);
  DateTime ahora;
  DateTime leer() => ahora;
}

/// Monta [AgendaPage] sola, con el lector falso. Devuelve el interruptor de «pestaña a la vista».
Future<ValueNotifier<bool>> _montar(
  WidgetTester tester,
  ConsultaAgendaFalsa repo, {
  _Reloj? reloj,
  bool activa = true,
  List<Override> overrides = const [],
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final visible = ValueNotifier<bool>(activa);
  final r = reloj ?? _Reloj(_base);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        consultaAgendaRepositoryProvider.overrideWithValue(repo),
        relojAgendaProvider.overrideWithValue(r.leer),
        ...overrides,
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, activa, _) => AgendaPage(colportorId: 'col-1', activa: activa),
          ),
        ),
      ),
    ),
  );
  await _asentar(tester);
  return visible;
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

ItemAgenda _entrevista(String id, DateTime cuando, {String nombre = 'Ana'}) =>
    itemAgenda(id, cuando, nombre: nombre);

ItemAgenda _cobranza(String id, DateTime cuando, {String nombre = 'Luis'}) => itemAgenda(
  id,
  cuando,
  nombre: nombre,
  tipo: TipoAgenda.cobranza,
  calle: 'Rivera',
  numero: '77',
);

/// La agenda de ejemplo del canvas: dos hoy y una mañana.
List<ItemAgenda> _delCanvas() => [
  _entrevista('e1', DateTime(2026, 10, 28, 14, 30), nombre: 'Ana'),
  _cobranza('c1', DateTime(2026, 10, 28, 17), nombre: 'Luis'),
  _entrevista('e2', DateTime(2026, 10, 29, 9), nombre: 'Marta'),
];

void main() {
  group('23B·01 · Hoy y próximos 7 días', () {
    _probar('muestra el encabezado, los filtros y las agendas agrupadas por día con su conteo', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(_delCanvas());
      await _montar(tester, repo);

      expect(find.text('AGENDA'), findsOneWidget);
      expect(find.text('Agenda'), findsOneWidget);
      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget);
      for (final chip in ['Todas', 'Entrevistas', 'Cobranzas', 'Pendientes ▾']) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      expect(find.text(_hoyConDos), findsOneWidget);
      expect(find.text('MAÑANA · JUEVES 29 (1)'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(find.text('Luis Martínez'), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsNWidgets(2));
      expect(find.text('Rivera 77'), findsOneWidget);
      expect(find.text('14:30'), findsOneWidget);
      expect(find.text('17:00'), findsOneWidget);
      expect(find.text('Entrevista'), findsNWidgets(2));
      expect(find.text('Cobranza'), findsOneWidget);
      // Los días se leen en orden: hoy primero.
      expect(
        tester.getTopLeft(find.text(_hoyConDos)).dy,
        lessThan(tester.getTopLeft(find.text('MAÑANA · JUEVES 29 (1)')).dy),
      );
    });

    _probar('lee la ventana de hoy a los próximos 7 días del colportor de la sesión', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(_delCanvas());
      await _montar(tester, repo);

      final pedido = repo.pedidos.single;
      expect(pedido.colportorId, 'col-1');
      expect(pedido.desde, DateTime(2026, 10, 28).toUtc());
      expect(pedido.hasta, DateTime(2026, 11, 5).toUtc());
    });

    _probar('sin destino para el detalle las filas no se tocan y no llevan la flecha', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));

      expect(find.text('›'), findsNothing);
      expect(find.text('+ Agendar'), findsNothing);
    });

    _probar('con destino para el detalle las filas llevan la flecha y se abren con su id', (
      tester,
    ) async {
      final abiertas = <String>[];
      await _montar(
        tester,
        ConsultaAgendaFalsa(_delCanvas()),
        overrides: [
          abrirDetalleDeAgendaProvider.overrideWithValue((id) async {
            abiertas.add(id);
            return null;
          }),
        ],
      );

      expect(find.text('›'), findsNWidgets(3));
      await tester.tap(find.text('Luis Martínez'));
      await _asentar(tester);

      expect(abiertas, ['c1']);
    });

    _probar('«+ Agendar» sale en el primer día cuando hay a dónde llevarlo', (tester) async {
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa(_delCanvas()),
        overrides: [
          agendarDesdeLaAgendaProvider.overrideWithValue(() async {
            llamadas++;
            return true;
          }),
        ],
      );

      expect(find.text('+ Agendar'), findsOneWidget);
      await tester.tap(find.text('+ Agendar'));
      await _asentar(tester);

      expect(llamadas, 1);
    });

    _probar('si hoy no hay nada, «+ Agendar» queda en el primer día que tiene agendas', (
      tester,
    ) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('e2', DateTime(2026, 10, 30, 9))]),
        overrides: [agendarDesdeLaAgendaProvider.overrideWithValue(() async => true)],
      );

      expect(find.text('+ Agendar'), findsOneWidget);
      expect(find.textContaining('HOY'), findsNothing);
    });

    _probar('una cobranza en otra dirección muestra la alternativa', (tester) async {
      final con = ItemAgenda(
        agenda: _cobranza('c1', DateTime(2026, 10, 28, 17)).agenda,
        personaNombre: 'Luis',
        personaApellido: 'Pérez',
        casa: const DireccionDeAgenda(
          ubicacionId: 'ub-1',
          tipo: TipoUbicacion.casa,
          calle: 'Av. Italia',
          numero: '1',
        ),
        alternativa: const DireccionDeAgenda(
          ubicacionId: 'ub-alt',
          tipo: TipoUbicacion.casa,
          calle: 'Rivera',
          numero: '77',
        ),
      );
      await _montar(tester, ConsultaAgendaFalsa([con]));

      expect(find.text('Rivera 77'), findsOneWidget);
      expect(find.text('Av. Italia 1'), findsNothing);
    });

    _probar('un edificio muestra el depto junto a la dirección', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          itemAgenda(
            'e1',
            DateTime(2026, 10, 28, 14),
            tipoUbicacion: TipoUbicacion.edificio,
            numeroDepto: '4B',
          ),
        ]),
      );

      expect(find.text('Av. Italia 1234 · Depto 4B'), findsOneWidget);
    });

    _probar('una agenda sin persona muestra la dirección como título', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          itemAgenda('e1', DateTime(2026, 10, 28, 14), nombre: null, apellido: null),
        ]),
      );

      expect(find.text('Av. Italia 1234'), findsOneWidget);
    });

    _probar('se repinta sola cuando se agenda o se cancela (stream reactivo)', (tester) async {
      final repo = ConsultaAgendaFalsa(_delCanvas());
      await _montar(tester, repo);
      expect(find.text('Ana Martínez'), findsOneWidget);

      repo.emitir([
        ..._delCanvas().skip(1),
        _entrevista('e3', DateTime(2026, 10, 28, 19), nombre: 'Rosa'),
      ]);
      await _asentar(tester);

      expect(find.text('Ana Martínez'), findsNothing);
      expect(find.text('Rosa Martínez'), findsOneWidget);
      expect(find.text(_hoyConDos), findsOneWidget);
      expect(repo.pedidos, hasLength(1), reason: 'no vuelve a pedir: escucha el mismo stream');
    });
  });

  group('23B·02 · Visita con la hora vencida', () {
    final vencida = _entrevista('e0', DateTime(2026, 10, 28, 9, 30), nombre: 'Elena');

    _probar('la entrevista que pasó de hora sigue en «Pendientes» y dice qué hacer', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa([vencida, ..._delCanvas()]));

      expect(find.text('Elena Martínez'), findsOneWidget);
      expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
    });

    _probar('sin destino para registrar no ofrece «Registrar»', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([vencida]));

      expect(find.text('Registrar'), findsNothing);
      expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
    });

    _probar('«Registrar» abre el registro de la visita de esa casa y ese espacio', (tester) async {
      final recibidos = <ContextoDeVisita>[];
      await _montar(
        tester,
        ConsultaAgendaFalsa([vencida]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((contexto) async {
            recibidos.add(contexto);
            return true;
          }),
        ],
      );

      await tester.tap(find.text('Registrar'));
      await _asentar(tester);

      expect(recibidos, [(ubicacionId: 'ub-e0', espacioId: 'esp-e0', agendaId: 'e0')]);
    });

    _probar('«Registrar» reemplaza a la flecha en esa fila', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([vencida, _entrevista('e1', DateTime(2026, 10, 28, 18))]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) async => true),
          abrirDetalleDeAgendaProvider.overrideWithValue((_) async => null),
        ],
      );

      expect(find.text('Registrar'), findsOneWidget);
      expect(find.text('›'), findsOneWidget, reason: 'solo la fila que no está vencida');
    });

    _probar('la cobranza vencida lo dice, pero no ofrece «Registrar» (el cobro tiene su flujo)', (
      tester,
    ) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_cobranza('c0', DateTime(2026, 10, 28, 9))]),
        overrides: [registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) async => true)],
      );

      expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
      expect(find.text('Registrar'), findsNothing);
    });

    _probar('la que todavía no llegó a su hora no está vencida', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));

      expect(find.text('Pasó la hora · registrá qué pasó'), findsNothing);
    });

    _probar('pasa a vencida sola cuando el reloj cruza su hora, sin tocar nada', (tester) async {
      final reloj = _Reloj(DateTime(2026, 10, 28, 9, 59, 30));
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('e1', DateTime(2026, 10, 28, 10))]),
        reloj: reloj,
        overrides: [registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) async => true)],
      );
      expect(find.text('Registrar'), findsNothing);

      reloj.ahora = DateTime(2026, 10, 28, 10, 0, 30);
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();

      expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
      expect(find.text('Registrar'), findsOneWidget);
    });
  });

  group('ATRASADAS · agendas de días anteriores que siguen sin resultado (P3)', () {
    // Lunes 26/10 y martes 27/10, con hoy miércoles 28/10 a las 10:00.
    final lunes = _entrevista('lun', DateTime(2026, 10, 26, 15, 30), nombre: 'Lidia');
    final martes = _entrevista('mar', DateTime(2026, 10, 27, 9), nombre: 'Mario');

    _probar('arriba de HOY, con su conteo, de la más antigua a la más reciente', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([..._delCanvas(), martes, lunes]));

      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(find.text('ATRASADAS (2)'), findsOneWidget);
      expect(find.text(_hoyConDos), findsOneWidget);
      expect(y('ATRASADAS (2)'), lessThan(y('Lidia Martínez')));
      expect(y('Lidia Martínez'), lessThan(y('Mario Martínez')));
      expect(y('Mario Martínez'), lessThan(y(_hoyConDos)));
    });

    _probar('cada fila dice su día además de la hora y que pasó la hora', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([lunes, martes]));

      expect(find.text('26/10\n15:30'), findsOneWidget);
      expect(find.text('27/10\n09:00'), findsOneWidget);
      expect(find.text('Pasó la hora · registrá qué pasó'), findsNWidgets(2));
    });

    _probar('las de hoy y las de después no llevan el día en la hora', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([lunes, ..._delCanvas()]));

      expect(find.text('14:30'), findsOneWidget);
      expect(find.textContaining('28/10'), findsNothing);
    });

    _probar('sin ninguna atrasada no aparece el grupo', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));

      expect(find.textContaining('ATRASADAS'), findsNothing);
    });

    _probar('si lo único que hay son atrasadas no es «sin agendas» y se ven igual', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([lunes]));

      expect(find.text('ATRASADAS (1)'), findsOneWidget);
      expect(find.text('Lidia Martínez'), findsOneWidget);
      expect(find.text('No tenés visitas en los próximos 7 días'), findsNothing);
    });

    _probar('lo cerrado de días anteriores no es atrasado', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          itemAgenda('c', DateTime(2026, 10, 26, 9), estado: EstadoAgenda.cumplida),
          itemAgenda('n', DateTime(2026, 10, 26, 10), estado: EstadoAgenda.noCumplida),
          itemAgenda('x', DateTime(2026, 10, 26, 11), estado: EstadoAgenda.cancelada),
        ]),
      );

      expect(find.textContaining('ATRASADAS'), findsNothing);
      expect(find.text('No tenés visitas en los próximos 7 días'), findsOneWidget);
    });

    _probar('«Registrar» manda SU agenda, no otra de la misma casa (ayer y hoy en un espacio)', (
      tester,
    ) async {
      final recibidos = <ContextoDeVisita>[];
      // Dos agendas programadas en la misma casa y el mismo espacio: ayer y hoy.
      final ayer = itemAgenda(
        'a0',
        DateTime(2026, 10, 27, 9),
        espacioId: 'esp-casa',
        ubicacionId: 'ub-casa',
      );
      final hoy = itemAgenda(
        'a1',
        DateTime(2026, 10, 28, 9),
        espacioId: 'esp-casa',
        ubicacionId: 'ub-casa',
      );
      await _montar(
        tester,
        ConsultaAgendaFalsa([hoy, ayer]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((contexto) async {
            recibidos.add(contexto);
            return true;
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('agenda_registrar_a1')));
      await _asentar(tester);
      await tester.tap(find.byKey(const Key('agenda_registrar_a0')));
      await _asentar(tester);

      expect(recibidos, [
        (ubicacionId: 'ub-casa', espacioId: 'esp-casa', agendaId: 'a1'),
        (ubicacionId: 'ub-casa', espacioId: 'esp-casa', agendaId: 'a0'),
      ]);
    });

    _probar('una cobranza atrasada se ve pero no ofrece «Registrar»', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_cobranza('cob', DateTime(2026, 10, 26, 11))]),
        overrides: [registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) async => true)],
      );

      expect(find.text('ATRASADAS (1)'), findsOneWidget);
      expect(find.text('Luis Martínez'), findsOneWidget);
      expect(find.text('Registrar'), findsNothing);
    });

    _probar(
      'con un registro abierto el resto sigue apagado y, al guardarse, el grupo se actualiza',
      (tester) async {
        final repo = ConsultaAgendaFalsa([lunes, martes]);
        final espera = Completer<Object?>();
        await _montar(
          tester,
          repo,
          overrides: [registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) => espera.future)],
        );

        await tester.tap(find.byKey(const Key('agenda_registrar_lun')));
        await tester.pump();
        expect(
          tester.widget<TextButton>(find.byKey(const Key('agenda_registrar_mar'))).onPressed,
          isNull,
        );

        // Se guardó la visita del lunes: la lectura reactiva la saca del grupo.
        repo.emitir([
          itemAgenda(
            'lun',
            DateTime(2026, 10, 26, 15, 30),
            nombre: 'Lidia',
            estado: EstadoAgenda.cumplida,
          ),
          martes,
        ]);
        espera.complete(true);
        await _asentar(tester);

        expect(find.text('ATRASADAS (1)'), findsOneWidget);
        expect(find.text('Lidia Martínez'), findsNothing);
        expect(
          tester.widget<TextButton>(find.byKey(const Key('agenda_registrar_mar'))).onPressed,
          isNotNull,
        );

        repo.emitir([]);
        await _asentar(tester);
        expect(find.textContaining('ATRASADAS'), findsNothing);
        expect(find.text('No tenés visitas en los próximos 7 días'), findsOneWidget);
      },
    );

    _probar('los filtros las alcanzan: «Cobranzas» y «Cumplidas» las acotan u ocultan', (
      tester,
    ) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([lunes, _cobranza('cob', DateTime(2026, 10, 27, 11))]),
      );
      expect(find.text('ATRASADAS (2)'), findsOneWidget);

      await tester.tap(find.text('Cobranzas'));
      await _asentar(tester);
      expect(find.text('ATRASADAS (1)'), findsOneWidget);
      expect(find.text('Lidia Martínez'), findsNothing);

      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cumplidas'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ATRASADAS'), findsNothing);
    });

    _probar('«+ Agendar» sale en HOY y no en las atrasadas', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([lunes, ..._delCanvas()]),
        overrides: [agendarDesdeLaAgendaProvider.overrideWithValue(() async => true)],
      );

      expect(find.text('+ Agendar'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('+ Agendar')).dy,
        greaterThan(tester.getTopLeft(find.text('Lidia Martínez')).dy),
      );
    });

    _probar('si no hay días, «+ Agendar» sale en el rótulo de las atrasadas', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([lunes]),
        overrides: [agendarDesdeLaAgendaProvider.overrideWithValue(() async => true)],
      );

      expect(find.text('+ Agendar'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('+ Agendar')).dy,
        lessThan(tester.getTopLeft(find.text('Lidia Martínez')).dy),
      );
    });

    _probar('al pasar la medianoche, la de hoy que no se registró pasa a ATRASADAS', (
      tester,
    ) async {
      final reloj = _Reloj(DateTime(2026, 10, 28, 23, 59, 30));
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('e1', DateTime(2026, 10, 28, 18), nombre: 'Elena')]),
        reloj: reloj,
      );
      expect(find.textContaining('ATRASADAS'), findsNothing);
      expect(find.text('HOY · MIÉRCOLES 28 (1)'), findsOneWidget);

      reloj.ahora = DateTime(2026, 10, 29, 0, 0, 30);
      await tester.pump(const Duration(seconds: 30));
      await _asentar(tester);

      expect(find.text('ATRASADAS (1)'), findsOneWidget);
      expect(find.text('Elena Martínez'), findsOneWidget);
      expect(find.textContaining('HOY'), findsNothing);
    });

    _probar('el grupo se anuncia como encabezado y cada fila dice su día', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, ConsultaAgendaFalsa([lunes]));

      expect(
        tester.getSemantics(find.text('ATRASADAS (1)')),
        isSemantics(label: 'ATRASADAS (1)', isHeader: true),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^26/10\. 15:30\. Entrevista\. Lidia Martínez')),
        findsOneWidget,
      );
      semantica.dispose();
    });

    _probar('con muchas atrasadas y el texto al 200 % en 320 px no desborda', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          for (var i = 0; i < 12; i++)
            itemAgenda(
              'v$i',
              DateTime(2026, 10, 20 + i % 7, 9, i),
              nombre: 'Persona con un nombre larguísimo número $i',
              calle: 'Avenida General Fructuoso Rivera y Ellauri',
            ),
        ]),
        overrides: [registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) async => true)],
        escala: 2,
        tamano: const Size(320, 700),
      );

      expect(find.text('ATRASADAS (12)'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('agenda_registrar_v11')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('agenda_filas')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('23B·03 · Filtro por tipo', () {
    _probar('«Cobranzas» deja solo las cobranzas y «Todas» las devuelve, sin volver a leer', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(_delCanvas());
      await _montar(tester, repo);

      await tester.tap(find.text('Cobranzas'));
      await _asentar(tester);
      expect(find.text('Luis Martínez'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsNothing);
      expect(find.text('HOY · MIÉRCOLES 28 (1)'), findsOneWidget);

      await tester.tap(find.text('Entrevistas'));
      await _asentar(tester);
      expect(find.text('Luis Martínez'), findsNothing);
      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(find.text('Marta Martínez'), findsOneWidget);

      await tester.tap(find.text('Todas'));
      await _asentar(tester);
      expect(find.text('Luis Martínez'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(repo.pedidos, hasLength(1));
    });

    _probar('el chip elegido se anuncia como seleccionado', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));
      await tester.tap(find.text('Cobranzas'));
      await _asentar(tester);

      expect(
        tester.getSemantics(find.widgetWithText(ChipAgenda, 'Cobranzas')),
        isSemantics(label: 'Cobranzas', isButton: true, isSelected: true, hasSelectedState: true),
      );
      semantica.dispose();
    });
  });

  group('23B·04 · Hoja «Estado»', () {
    _probar('«Pendientes ▾» abre la hoja con las cinco opciones y «Aplicar»', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));

      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();

      expect(find.text('Estado'), findsOneWidget);
      for (final opcion in ['Pendientes', 'Cumplidas', 'No cumplidas', 'Canceladas', 'Todas']) {
        expect(find.text(opcion), findsWidgets, reason: opcion);
      }
      expect(find.text('Programadas, de hoy en adelante'), findsOneWidget);
      expect(find.text('Aplicar'), findsOneWidget);
      expect(find.text('✓'), findsOneWidget);
    });

    _probar('elegir una opción no cambia nada hasta tocar «Aplicar»', (tester) async {
      final repo = ConsultaAgendaFalsa([
        ..._delCanvas(),
        itemAgenda(
          'x',
          DateTime(2026, 10, 29, 15),
          nombre: 'Olga',
          estado: EstadoAgenda.cancelada,
          actualizada: DateTime(2026, 10, 22, 12),
        ),
      ]);
      await _montar(tester, repo);
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('agenda_estado_canceladas')));
      await tester.pumpAndSettle();
      expect(find.text('Ana Martínez'), findsOneWidget, reason: 'la hoja aún no aplicó');

      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.text('Estado'), findsNothing);
      expect(find.text('Olga Martínez'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsNothing);
      expect(find.text('Canceladas ▾'), findsOneWidget);
    });

    _probar('cerrar la hoja sin aplicar conserva el filtro', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agenda_estado_todas')));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();

      expect(find.text('Estado'), findsNothing);
      expect(find.text('Pendientes ▾'), findsOneWidget);
    });

    _probar('un doble toque en «Aplicar» cierra la hoja una sola vez', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agenda_estado_todas')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aplicar'));
      await tester.tap(find.text('Aplicar'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Todas ▾'), findsOneWidget);
      expect(find.text('Hoy y los próximos 7 días'), findsOneWidget, reason: 'la pantalla sigue');
    });

    _probar('un doble toque en «Pendientes ▾» abre una sola hoja', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));

      await tester.tap(find.text('Pendientes ▾'));
      await tester.tap(find.text('Pendientes ▾'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Estado'), findsOneWidget);
    });
  });

  group('23B·05 · Agendas canceladas', () {
    final cancelada = itemAgenda(
      'x',
      DateTime(2026, 10, 29, 15),
      nombre: 'Olga',
      estado: EstadoAgenda.cancelada,
      actualizada: DateTime(2026, 10, 22, 12),
    );

    _probar('«Canceladas» muestra la fila tachada, con su etiqueta y «Cancelada el 22/10»', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa([cancelada]));
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agenda_estado_canceladas')));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelada el 22/10'), findsOneWidget);
      expect(find.text('Cancelada'), findsOneWidget);
      final titulo = tester.widget<Text>(find.text('Olga Martínez'));
      expect(titulo.style?.decoration, TextDecoration.lineThrough);
    });

    _probar('«Todas» mezcla pendientes y cerradas, y cada una dice su estado', (tester) async {
      final cumplida = itemAgenda(
        'y',
        DateTime(2026, 10, 28, 8),
        nombre: 'Pedro',
        estado: EstadoAgenda.cumplida,
        actualizada: DateTime(2026, 10, 28, 8, 30),
      );
      final noCumplida = itemAgenda(
        'z',
        DateTime(2026, 10, 28, 9),
        nombre: 'Sara',
        estado: EstadoAgenda.noCumplida,
        actualizada: DateTime(2026, 10, 28, 9, 30),
      );
      await _montar(
        tester,
        ConsultaAgendaFalsa([cumplida, noCumplida, cancelada, ..._delCanvas()]),
        tamano: const Size(390, 1600),
      );
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agenda_estado_todas')));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.text('Cumplida'), findsOneWidget);
      expect(find.text('Cumplida el 28/10'), findsOneWidget);
      expect(find.text('No cumplida'), findsOneWidget);
      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsOneWidget);
      // Una cerrada cuya hora ya pasó no es «vencida»: no pide registrar nada.
      expect(find.text('Pasó la hora · registrá qué pasó'), findsNothing);
    });
  });

  group('23B·06 · Cargando', () {
    _probar('mientras lee muestra los filtros y bloques grises, sin textos de la agenda', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, ConsultaAgendaFalsa()..congelada = true);

      expect(find.byType(EsqueletoAgenda), findsOneWidget);
      expect(find.text('Todas'), findsOneWidget);
      expect(find.textContaining('HOY'), findsNothing);
      expect(find.text('No tenés visitas en los próximos 7 días'), findsNothing);
      expect(find.bySemanticsLabel('Cargando tu agenda'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('23B·07 · Sin agendas', () {
    _probar('muestra el vacío con su texto y «+ Agendar» si hay a dónde llevarlo', (tester) async {
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa(),
        overrides: [
          agendarDesdeLaAgendaProvider.overrideWithValue(() async {
            llamadas++;
            return true;
          }),
        ],
      );

      expect(find.text('No tenés visitas en los próximos 7 días'), findsOneWidget);
      expect(
        find.text('Agendá una entrevista o una cobranza desde la ficha de la persona o desde acá.'),
        findsOneWidget,
      );
      expect(find.text('Todas'), findsOneWidget);
      await tester.tap(find.text('+ Agendar'));
      await _asentar(tester);
      expect(llamadas, 1);
    });

    _probar('sin destino para agendar no muestra el botón, pero sí el texto', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa());

      expect(find.text('No tenés visitas en los próximos 7 días'), findsOneWidget);
      expect(find.text('+ Agendar'), findsNothing);
    });

    _probar('las agendas que caen fuera de la ventana no cuentan: sigue vacía', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          itemAgenda('ayer', DateTime(2026, 10, 27, 23, 59), estado: EstadoAgenda.cumplida),
          _entrevista('dia8', DateTime(2026, 11, 5)),
        ]),
      );

      expect(find.text('No tenés visitas en los próximos 7 días'), findsOneWidget);
    });
  });

  group('23B·08 · Filtros sin resultados', () {
    _probar('muestra «Ninguna agenda con estos filtros» y «Limpiar filtros» vuelve a todo', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa([_entrevista('e1', DateTime(2026, 10, 28, 14))]));
      await tester.tap(find.text('Cobranzas'));
      await _asentar(tester);

      expect(find.text('Ninguna agenda con estos filtros'), findsOneWidget);
      expect(find.text('No tenés visitas en los próximos 7 días'), findsNothing);

      await tester.tap(find.text('Limpiar filtros'));
      await _asentar(tester);

      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(find.text('Ninguna agenda con estos filtros'), findsNothing);
    });

    _probar('un estado sin agendas también cae en «sin resultados», no en el vacío', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));
      await tester.tap(find.text('Pendientes ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agenda_estado_cumplidas')));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(find.text('Ninguna agenda con estos filtros'), findsOneWidget);
      expect(find.text('Cumplidas ▾'), findsOneWidget);
    });
  });

  group('23B·09 · Error de lectura', () {
    _probar('muestra «No pudimos leer tu agenda.» con «Reintentar» y sin filtros', (tester) async {
      final repo = ConsultaAgendaFalsa()..error = StateError('disco');
      await _montar(tester, repo);

      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Todas'), findsNothing);
      expect(find.text('No tenés visitas en los próximos 7 días'), findsNothing);
    });

    _probar('no muestra el detalle técnico del error', (tester) async {
      final repo = ConsultaAgendaFalsa()..error = StateError('SQLITE_CORRUPT en agenda');
      await _montar(tester, repo);

      expect(find.textContaining('SQLITE'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    });

    _probar('«Reintentar» vuelve a leer y, si ahora anda, muestra la agenda', (tester) async {
      final repo = ConsultaAgendaFalsa(_delCanvas())..error = StateError('disco');
      await _montar(tester, repo);
      expect(repo.pedidos, hasLength(1));

      repo.error = null;
      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);

      expect(repo.pedidos, hasLength(2));
      expect(find.text('No pudimos leer tu agenda.'), findsNothing);
      expect(find.text('Ana Martínez'), findsOneWidget);
    });

    _probar('un error que llega después de los primeros datos también se dice, y se recupera', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa(_delCanvas());
      await _montar(tester, repo);
      expect(find.text('Ana Martínez'), findsOneWidget);

      repo.emitirError(StateError('disco'));
      await _asentar(tester);

      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      expect(find.text('Ana Martínez'), findsNothing);

      // Si la lectura vuelve a emitir, la agenda vuelve.
      repo.emitir(_delCanvas());
      await _asentar(tester);

      expect(find.text('No pudimos leer tu agenda.'), findsNothing);
      expect(find.text('Ana Martínez'), findsOneWidget);
    });

    _probar('si sigue fallando, vuelve a mostrar el error y «Reintentar» sigue habilitado', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa()..error = StateError('disco');
      await _montar(tester, repo);

      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);
      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);

      expect(repo.pedidos, hasLength(3));
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
    });

    _probar('un doble toque en «Reintentar» lee una sola vez', (tester) async {
      final repo = ConsultaAgendaFalsa()..error = StateError('disco');
      await _montar(tester, repo);

      await tester.tap(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'), warnIfMissed: false);
      await _asentar(tester);

      expect(repo.pedidos, hasLength(2));
    });

    _probar('sin la base abierta (sin sesión de datos) también cae en el error', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [relojAgendaProvider.overrideWithValue(() => _base)],
          child: MaterialApp(
            theme: temaClaro(),
            home: const Scaffold(body: AgendaPage(colportorId: 'col-1')),
          ),
        ),
      );
      await _asentar(tester);

      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
    });
  });

  group('Casos límite', () {
    _probar('doble toque en «Registrar»: abre un solo registro y mientras tanto queda apagado', (
      tester,
    ) async {
      final espera = Completer<Object?>();
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('e0', DateTime(2026, 10, 28, 9))]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) {
            llamadas++;
            return espera.future;
          }),
        ],
      );

      await tester.tap(find.text('Registrar'));
      await tester.pump();
      await tester.tap(find.text('Registrar'), warnIfMissed: false);
      await tester.pump();

      expect(llamadas, 1);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('agenda_registrar_e0'))).onPressed,
        isNull,
        reason: 'mientras el registro está abierto el botón está apagado',
      );

      espera.complete(true);
      await _asentar(tester);

      expect(
        tester.widget<TextButton>(find.byKey(const Key('agenda_registrar_e0'))).onPressed,
        isNotNull,
      );
    });

    _probar('si el registro falla, avisa y el botón vuelve a quedar habilitado', (tester) async {
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('e0', DateTime(2026, 10, 28, 9))]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) {
            llamadas++;
            throw StateError('sin hoja');
          }),
        ],
      );

      await tester.tap(find.text('Registrar'));
      await _asentar(tester);

      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('agenda_registrar_e0'))).onPressed,
        isNotNull,
      );

      await tester.tap(find.text('Registrar'));
      await _asentar(tester);
      expect(llamadas, 2);
    });

    _probar('si el registro falla de forma asíncrona, tampoco queda trabado', (tester) async {
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('e0', DateTime(2026, 10, 28, 9))]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((_) async {
            llamadas++;
            throw StateError('se cayó');
          }),
        ],
      );

      await tester.tap(find.text('Registrar'));
      await _asentar(tester);
      await tester.tap(find.text('Registrar'));
      await _asentar(tester);

      expect(llamadas, 2);
    });

    _probar('dos «Registrar» seguidos en filas distintas: el segundo espera al primero', (
      tester,
    ) async {
      final espera = Completer<Object?>();
      final llamadas = <String?>[];
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          _entrevista('e0', DateTime(2026, 10, 28, 8), nombre: 'Elena'),
          _entrevista('e1', DateTime(2026, 10, 28, 9), nombre: 'Rosa'),
        ]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((c) {
            llamadas.add(c.espacioId);
            return espera.future;
          }),
        ],
      );

      await tester.tap(find.byKey(const Key('agenda_registrar_e0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('agenda_registrar_e1')), warnIfMissed: false);
      await tester.pump();

      expect(llamadas, ['esp-e0']);

      espera.complete(true);
      await _asentar(tester);
      await tester.tap(find.byKey(const Key('agenda_registrar_e1')));
      await _asentar(tester);

      expect(llamadas, ['esp-e0', 'esp-e1'], reason: 'ninguno se pierde ni se pisa');
    });

    _probar('doble toque en una fila abre un solo detalle', (tester) async {
      final espera = Completer<Object?>();
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa(_delCanvas()),
        overrides: [
          abrirDetalleDeAgendaProvider.overrideWithValue((_) {
            llamadas++;
            return espera.future;
          }),
        ],
      );

      await tester.tap(find.text('Ana Martínez'));
      await tester.pump();
      await tester.tap(find.text('Luis Martínez'));
      await tester.pump();

      expect(llamadas, 1);

      espera.complete(null);
      await _asentar(tester);
      await tester.tap(find.text('Luis Martínez'));
      await _asentar(tester);
      expect(llamadas, 2, reason: 'al volver, la pantalla acepta otro toque');
    });

    _probar('si el detalle falla avisa y las filas siguen tocables', (tester) async {
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa(_delCanvas()),
        overrides: [
          abrirDetalleDeAgendaProvider.overrideWithValue((_) {
            llamadas++;
            throw StateError('sin detalle');
          }),
        ],
      );

      await tester.tap(find.text('Ana Martínez'));
      await _asentar(tester);
      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOneWidget);

      await tester.tap(find.text('Luis Martínez'));
      await _asentar(tester);
      expect(llamadas, 2);
    });

    _probar('doble toque en «+ Agendar» abre un solo formulario', (tester) async {
      final espera = Completer<Object?>();
      var llamadas = 0;
      await _montar(
        tester,
        ConsultaAgendaFalsa(_delCanvas()),
        overrides: [
          agendarDesdeLaAgendaProvider.overrideWithValue(() {
            llamadas++;
            return espera.future;
          }),
        ],
      );

      await tester.tap(find.text('+ Agendar'));
      await tester.pump();
      await tester.tap(find.text('+ Agendar'));
      await tester.pump();

      expect(llamadas, 1);
      espera.complete(true);
      await _asentar(tester);
    });

    _probar('volver a la pestaña conserva los filtros y renueva la hora', (tester) async {
      final reloj = _Reloj(DateTime(2026, 10, 28, 9, 30));
      final repo = ConsultaAgendaFalsa([
        ..._delCanvas(),
        _entrevista('e9', DateTime(2026, 10, 28, 10), nombre: 'Elena'),
      ]);
      final visible = await _montar(tester, repo, reloj: reloj);
      await tester.tap(find.text('Entrevistas'));
      await _asentar(tester);
      expect(find.text('Luis Martínez'), findsNothing);

      visible.value = false;
      await _asentar(tester);
      reloj.ahora = DateTime(2026, 10, 28, 11);
      visible.value = true;
      await _asentar(tester);

      expect(find.text('Luis Martínez'), findsNothing, reason: 'el filtro «Entrevistas» sigue');
      expect(find.text('Ana Martínez'), findsOneWidget);
      expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
    });

    _probar('con la pestaña fuera de vista no corre el reloj del minuto', (tester) async {
      final reloj = _Reloj(DateTime(2026, 10, 28, 9, 59, 30));
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('e1', DateTime(2026, 10, 28, 10))]),
        reloj: reloj,
        activa: false,
      );

      reloj.ahora = DateTime(2026, 10, 28, 10, 0, 30);
      await tester.pump(const Duration(minutes: 2));

      expect(find.text('Pasó la hora · registrá qué pasó'), findsNothing);
    });

    _probar('al pasar la medianoche, «mañana» pasa a ser «hoy» y se lee la ventana nueva', (
      tester,
    ) async {
      final reloj = _Reloj(DateTime(2026, 10, 28, 23, 59, 30));
      final repo = ConsultaAgendaFalsa([_entrevista('e1', DateTime(2026, 10, 29, 0, 10))]);
      await _montar(tester, repo, reloj: reloj);
      expect(find.text('MAÑANA · JUEVES 29 (1)'), findsOneWidget);

      reloj.ahora = DateTime(2026, 10, 29, 0, 0, 30);
      await tester.pump(const Duration(seconds: 30));
      await _asentar(tester);

      expect(find.text('HOY · JUEVES 29 (1)'), findsOneWidget);
      expect(repo.pedidos.last.desde, DateTime(2026, 10, 29).toUtc());
      expect(repo.pedidos.last.hasta, DateTime(2026, 11, 6).toUtc());
    });

    _probar('una lista larga se recorre hasta la última agenda', (tester) async {
      final repo = ConsultaAgendaFalsa([
        for (var i = 0; i < 80; i++)
          _entrevista(
            'e${i.toString().padLeft(2, '0')}',
            DateTime(2026, 10, 30, 8, i % 60),
            nombre: 'Persona${i.toString().padLeft(2, '0')}',
          ),
      ]);
      await _montar(tester, repo);

      await tester.scrollUntilVisible(
        find.text('Persona79 Martínez'),
        400,
        scrollable: find.descendant(
          of: find.byKey(const Key('agenda_filas')),
          matching: find.byType(Scrollable),
        ),
      );

      expect(find.text('Persona79 Martínez'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _probar('textos larguísimos no desbordan, ni a 320 px con el texto al 200 %', (tester) async {
      final largo = 'María de los Ángeles ' * 4;
      final recibidos = <ContextoDeVisita>[];
      final repo = ConsultaAgendaFalsa([
        itemAgenda(
          'e0',
          DateTime(2026, 10, 28, 9),
          nombre: largo,
          apellido: 'Fernández de la Peña y Echeverría',
          calle: 'Avenida Doctor Presidente General Don José Gervasio Artigas',
          numero: '123456 bis apto. 1001',
        ),
        _cobranza('c1', DateTime(2026, 10, 28, 17)),
      ]);
      await _montar(
        tester,
        repo,
        escala: 2,
        tamano: const Size(320, 640),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((c) async {
            recibidos.add(c);
            return true;
          }),
          abrirDetalleDeAgendaProvider.overrideWithValue((_) async => null),
        ],
      );

      expect(tester.takeException(), isNull);
      // Con el texto al 200 % el encabezado y los filtros ocupan casi la pantalla: todo se desplaza.
      await tester.scrollUntilVisible(
        find.text('Registrar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Registrar'));
      await tester.pump();
      expect(find.text('Registrar'), findsOneWidget);
      await tester.tap(find.text('Registrar'));
      await _asentar(tester);
      expect(tester.takeException(), isNull);
      expect(recibidos, hasLength(1), reason: 'el botón es alcanzable con el texto al 200 %');
    });

    _probar('el vacío, el error y el sin resultados caben a 320 px con el texto al 200 %', (
      tester,
    ) async {
      for (final repo in [
        ConsultaAgendaFalsa(),
        ConsultaAgendaFalsa()..error = StateError('x'),
        ConsultaAgendaFalsa(_delCanvas()),
      ]) {
        await _montar(tester, repo, escala: 2, tamano: const Size(320, 640));
        if (repo.items.isNotEmpty) {
          await tester.ensureVisible(find.text('Cobranzas'));
          await tester.tap(find.text('Cobranzas'));
          await tester.tap(find.text('Entrevistas'));
          await _asentar(tester);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  group('Accesibilidad', () {
    _probar('cada fila se anuncia entera, en un solo nodo, y los controles miden 48', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          _entrevista('e0', DateTime(2026, 10, 28, 9), nombre: 'Elena'),
          ..._delCanvas(),
        ]),
        overrides: [
          registrarVisitaDesdeLaCasaProvider.overrideWith(
            (ref) =>
                (_) async => true,
          ),
          abrirDetalleDeAgendaProvider.overrideWith(
            (ref) =>
                (_) async => null,
          ),
        ],
      );

      expect(
        find.bySemanticsLabel(
          '09:00. Entrevista. Elena Martínez. Av. Italia 1234. Pasó la hora · registrá qué pasó',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('14:30. Entrevista. Ana Martínez. Av. Italia 1234'),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    _probar('los rótulos de día son encabezados', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, ConsultaAgendaFalsa(_delCanvas()));

      expect(
        tester.getSemantics(find.text(_hoyConDos)),
        isSemantics(label: _hoyConDos, isHeader: true),
      );
      semantica.dispose();
    });
  });
}
