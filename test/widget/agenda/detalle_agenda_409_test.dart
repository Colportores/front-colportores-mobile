// HU-VIS-003 / issue #409 — el detalle de una agenda (vista 23, 23C·01 y 23C·06 y sus estados): lo que
// dibuja el canvas letra por letra, la agenda cerrada, leer/cargar/error, «Registrar resultado» y el
// enlace «Cancelar agenda», y los casos límite (doble toque, volver y reentrar, texto 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart' show visitaDe;
import '../../helpers/detalle_agenda_arnes.dart';

String _texto(Key k) {
  final f = find.descendant(of: find.byKey(k), matching: find.byType(Text));
  return _textos(f).join('|');
}

List<String> _textos(Finder f) => [for (final w in f.evaluate()) (w.widget as Text).data ?? ''];

void main() {
  group('23C·01 · Detalle de una agenda programada', () {
    testWidgets('dado el canvas, cuando se abre, entonces dibuja todo lo que dice el diseño', (
      tester,
    ) async {
      await montarDetalle(tester);

      expect(find.text('AGENDA'), findsOneWidget);
      expect(find.text('Entrevista'), findsOneWidget);
      expect(find.text('María Fernández · Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(_texto(ClavesDetalleAgenda.estado), 'Estado|Programada');
      expect(_texto(ClavesDetalleAgenda.cuando), 'Cuándo|Sáb 24/10 · 14:30');
      expect(_texto(ClavesDetalleAgenda.franja), 'Franja|Primera tarde');
      expect(_texto(ClavesDetalleAgenda.recordatorio), 'Recordatorio|14:00');
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      expect(find.text('Modificar'), findsOneWidget);
      expect(find.text('Cancelar agenda'), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.avisoCerrada), findsNothing);
    });

    testWidgets('la nota de la agenda se muestra tal cual; sin nota, «Sin nota»', (tester) async {
      await montarDetalle(
        tester,
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'Pedirle el teléfono del hijo'),
      );
      expect(_texto(ClavesDetalleAgenda.nota), 'Nota|Pedirle el teléfono del hijo');
    });

    testWidgets('una cobranza se titula «Cobranza» y una agenda sin franja dice «Sin franja»', (
      tester,
    ) async {
      await montarDetalle(
        tester,
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(tipo: TipoAgenda.cobranza, slot: null)),
      );
      expect(find.text('Cobranza'), findsOneWidget);
      expect(_texto(ClavesDetalleAgenda.franja), 'Franja|Sin franja');
      expect(_texto(ClavesDetalleAgenda.nota), 'Nota|Sin nota');
    });

    testWidgets('el recordatorio sigue la anticipación elegida en las preferencias', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester, abrir: false);
      arnes.telefono.preferencias.preferencias = const PreferenciasRecordatorios(
        anticipacionMinutos: 60,
      );
      await abrirDetalle(tester);
      expect(_texto(ClavesDetalleAgenda.recordatorio), 'Recordatorio|13:30');
    });

    testWidgets('con los recordatorios apagados dice «Apagado»', (tester) async {
      final arnes = await montarDetalle(tester, abrir: false);
      arnes.telefono.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await abrirDetalle(tester);
      expect(_texto(ClavesDetalleAgenda.recordatorio), 'Recordatorio|Apagado');
    });

    testWidgets('si la hora del aviso ya pasó dice «Ya pasó», no una hora que no va a sonar', (
      tester,
    ) async {
      await montarDetalle(tester, ahora: DateTime(2026, 10, 24, 14, 10));
      expect(_texto(ClavesDetalleAgenda.recordatorio), 'Recordatorio|Ya pasó');
    });

    testWidgets('si el aviso cae otro día que la visita, dice el día', (tester) async {
      await montarDetalle(
        tester,
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(cuando: DateTime(2026, 10, 24, 0, 10))),
      );
      expect(_texto(ClavesDetalleAgenda.recordatorio), 'Recordatorio|Vie 23/10 · 23:40');
    });

    testWidgets('sin conexión no cambia nada: todo se lee del teléfono', (tester) async {
      await montarDetalle(tester);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
    });
  });

  group('23C·06 · Una agenda que ya no se puede modificar', () {
    testWidgets('cumplida: muestra el resultado, el aviso y ninguna salida', (tester) async {
      await montarDetalle(
        tester,
        detalle: DetalleDeAgenda(
          agenda: agendaDelDetalle(estado: EstadoAgenda.cumplida),
          visita: visitaDe('vis-1'),
        ),
      );
      expect(
        find.text('Esta visita ya tiene resultado: no se puede modificar ni cancelar.'),
        findsOneWidget,
      );
      expect(_texto(ClavesDetalleAgenda.estado), 'Estado|Cumplida · Entrevista hecha');
      expect(_texto(ClavesDetalleAgenda.recordatorio), 'Recordatorio|—');
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.registrar), findsNothing);
      expect(find.text('Cancelar agenda'), findsNothing);
    });

    testWidgets('no cumplida: mismo aviso, con el resultado de la visita', (tester) async {
      await montarDetalle(
        tester,
        detalle: DetalleDeAgenda(
          agenda: agendaDelDetalle(estado: EstadoAgenda.noCumplida),
          visita: visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto),
        ),
      );
      expect(_texto(ClavesDetalleAgenda.estado), 'Estado|No cumplida · No contestó');
      expect(find.byKey(ClavesDetalleAgenda.avisoCerrada), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
    });

    testWidgets('cancelada: su propio aviso, sin salidas', (tester) async {
      await montarDetalle(
        tester,
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(estado: EstadoAgenda.cancelada)),
      );
      expect(find.text('Esta agenda está cancelada: no se puede modificar.'), findsOneWidget);
      expect(_texto(ClavesDetalleAgenda.estado), 'Estado|Cancelada');
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
      expect(find.text('Cancelar agenda'), findsNothing);
    });
  });

  group('Cargando, error y agenda que ya no está', () {
    testWidgets('mientras lee muestra «Cargando la agenda…» y después el detalle', (tester) async {
      final repo = AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDelDetalle()))
        ..compuertaDeLectura = Completer<void>();
      await montarDetalle(tester, repo: repo);
      expect(find.byKey(ClavesDetalleAgenda.cargando), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);

      repo.compuertaDeLectura!.complete();
      await asentarDetalle(tester);
      expect(find.byKey(ClavesDetalleAgenda.cargando), findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
    });

    testWidgets('si no se puede leer, avisa y «Reintentar» lo vuelve a leer', (tester) async {
      final repo = AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDelDetalle()))
        ..fallasDeLectura.add(const FailureInesperado());
      await montarDetalle(tester, repo: repo);
      expect(find.text('No pudimos leer la agenda en tu teléfono.'), findsOneWidget);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);

      await tester.tap(find.byKey(ClavesDetalleAgenda.reintentar));
      await asentarDetalle(tester);
      expect(find.byKey(ClavesDetalleAgenda.aviso), findsNothing);
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      expect(repo.lecturas, 2);
    });

    testWidgets('una agenda que ya no está en el teléfono lo dice y no ofrece salidas', (
      tester,
    ) async {
      await montarDetalle(tester, repo: AgendaRepositorioDetalle(null));
      expect(
        find.text('Esa agenda ya no está en tu teléfono. Volvé a la lista de agendados.'),
        findsOneWidget,
      );
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsNothing);
    });

    testWidgets('la casa que no se puede leer no tapa el detalle: queda sin el lugar', (
      tester,
    ) async {
      await montarDetalle(tester, fallaDeCasa: const FailureInesperado());
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget, reason: 'sin el lugar, solo la persona');
      expect(find.textContaining('Mataojo'), findsNothing);
    });
  });

  group('«Registrar resultado»', () {
    testWidgets('sin destino conectado, el botón no se ofrece', (tester) async {
      await montarDetalle(tester);
      expect(find.byKey(ClavesDetalleAgenda.registrar), findsNothing);
    });

    testWidgets('lleva a la casa de ESTA agenda (con su id)', (tester) async {
      final arnes = await montarDetalle(tester, conRegistrar: true);
      await tester.tap(find.byKey(ClavesDetalleAgenda.registrar));
      await asentarDetalle(tester);
      expect(arnes.registros, hasLength(1));
      expect(arnes.registros.single.espacioId, 'esp-1');
      expect(arnes.registros.single.agendaId, 'ag-1');
    });

    testWidgets('un doble toque abre una sola vez; al volver se vuelve a leer la agenda', (
      tester,
    ) async {
      final espera = Completer<void>();
      final arnes = await montarDetalle(tester, conRegistrar: true, registrarDemorado: espera);
      await tester.tap(find.byKey(ClavesDetalleAgenda.registrar));
      await tester.pump();
      await tester.tap(find.byKey(ClavesDetalleAgenda.registrar));
      await asentarDetalle(tester);
      expect(arnes.registros, hasLength(1));

      final lecturas = arnes.repo.lecturas;
      espera.complete();
      await asentarDetalle(tester);
      expect(arnes.repo.lecturas, lecturas + 1, reason: 'la visita pudo cerrar la agenda');
    });
  });

  group('«Cancelar agenda»', () {
    testWidgets('solo se ofrece en una programada', (tester) async {
      await montarDetalle(tester);
      expect(find.text('Cancelar agenda'), findsOneWidget);
    });
  });

  group('Casos límite', () {
    testWidgets('volver y reentrar: cada apertura lee de nuevo y no queda nada colgado', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      expect(arnes.repo.lecturas, 1);
      await tester.tap(find.byKey(ClavesDetalleAgenda.volver));
      await asentarDetalle(tester);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsNothing);

      await abrirDetalle(tester);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
      expect(arnes.repo.lecturas, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nota larguísima y texto al 200 % en 320×568: nada se corta ni desborda', (
      tester,
    ) async {
      await montarDetalle(
        tester,
        escala: 2,
        tamano: const Size(320, 568),
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'Muy larga ' * 60),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(ClavesDetalleAgenda.modificar),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(ClavesDetalleAgenda.modificar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cada renglón se lee como una sola frase: «Estado: Programada»', (tester) async {
      await montarDetalle(tester);
      final semantica = tester.getSemantics(find.byKey(ClavesDetalleAgenda.estado));
      expect(semantica.label, contains('Estado'));
      expect(semantica.label, contains('Programada'));
    });
  });
}
