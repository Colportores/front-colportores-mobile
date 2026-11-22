// HU-VIS-003 / issue #409 — «Modificar agenda» (vista 23, 23C·02 modificar, 23C·03 modificada y 23C·07
// error) de punta a punta desde el detalle: el formulario precargado, el aviso del recordatorio, el
// guardado y los casos límite (doble toque, falla a mitad, dos cambios seguidos, volver y reentrar,
// hora que ya pasó, texto 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/modificar_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/conciliacion_recordatorios_falsos.dart' show visitaParaAviso;
import '../../helpers/detalle_agenda_arnes.dart';

final _guardar = find.byKey(ClavesModificarAgenda.guardar);
final _campo = find.byKey(ClavesAgendarVisita.campoDiaYHora);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentarDetalle(tester);
}

Future<void> _repetir(WidgetTester tester, Key tecla, int veces) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(find.byKey(tecla));
    await tester.pump();
  }
}

/// Abre «Modificar» desde el detalle.
Future<void> _modificar(WidgetTester tester) =>
    _tocar(tester, find.byKey(ClavesDetalleAgenda.modificar));

/// Sube la hora [pasos] veces de a 5 min (12 = una hora).
Future<void> _subirHora(WidgetTester tester, int pasos) async {
  await _tocar(tester, _campo);
  await _repetir(tester, ClavesAgendarVisita.hojaMas, pasos);
  await _tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
}

String _textoDe(Key k) => (find.byKey(k).evaluate().single.widget as Text).data!;

void main() {
  group('23C·02 · Modificar agenda', () {
    testWidgets(
      'dado el canvas, cuando se abre «Modificar», entonces dibuja el formulario cargado',
      (tester) async {
        final arnes = await montarDetalle(
          tester,
          detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'Llamar antes'),
        );
        await _modificar(tester);

        expect(find.text('MODIFICAR AGENDA'), findsOneWidget);
        expect(find.text('Modificar agenda'), findsOneWidget);
        expect(find.text('MF'), findsOneWidget);
        expect(find.text('María Fernández'), findsOneWidget);
        expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
        expect(find.text('TIPO'), findsOneWidget);
        expect(find.text('DÍA Y HORA'), findsOneWidget);
        expect(find.text('Mañana · 14:30'), findsOneWidget);
        expect(find.text('FRANJA SUGERIDA'), findsOneWidget);
        expect(find.text('Primera tarde'), findsWidgets);
        expect(find.text('NOTA (OPCIONAL)'), findsOneWidget);
        expect(find.text('Llamar antes'), findsOneWidget);
        expect(
          _textoDe(ClavesModificarAgenda.textoRecordatorio),
          'Reprogramamos el recordatorio para las 14:00.',
        );
        expect(find.text('Guardar cambios'), findsOneWidget);
        expect(arnes.repo.recibidos, isEmpty);
      },
    );

    testWidgets('cambiar la hora cambia a cuándo suena el recordatorio, antes de guardar', (
      tester,
    ) async {
      await montarDetalle(tester);
      await _modificar(tester);
      await _subirHora(tester, 12);
      expect(find.text('Mañana · 15:30'), findsOneWidget);
      expect(
        _textoDe(ClavesModificarAgenda.textoRecordatorio),
        'Reprogramamos el recordatorio para las 15:00.',
      );
    });

    testWidgets('la ✕ cierra sin guardar y volver a entrar muestra lo guardado, no lo tocado', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      await _modificar(tester);
      await _subirHora(tester, 12);
      await _tocar(tester, find.byKey(ClavesModificarAgenda.cerrar));
      expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
      expect(arnes.repo.recibidos, isEmpty);

      await _modificar(tester);
      expect(find.text('Mañana · 14:30'), findsOneWidget);
    });
  });

  group('23C·03 · Agenda modificada', () {
    testWidgets(
      'dado que cambio la hora a las 15:30, cuando guardo, entonces el detalle muestra lo '
      'nuevo y avisa «El recordatorio pasó a las 15:00.»',
      (tester) async {
        final arnes = await montarDetalle(tester);
        await _modificar(tester);
        await _subirHora(tester, 12);
        await _tocar(tester, _guardar);

        expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
        expect(find.text('Guardado. El recordatorio pasó a las 15:00.'), findsOneWidget);
        expect(arnes.repo.recibidos, hasLength(1));
        expect(
          arnes.repo.recibidos.single.fechaProgramada.isAtSameMomentAs(
            DateTime(2026, 10, 24, 15, 30),
          ),
          isTrue,
        );
        expect(
          arnes.recordatorios.programados['ag-1']!.fechaProgramada.toLocal(),
          DateTime(2026, 10, 24, 15, 30),
        );
        expect(arnes.recordatorios.programados['ag-1']!.direccion, contains('Mataojo 2044'));
        // El detalle volvió a leer la agenda: ya muestra lo nuevo.
        expect(find.byKey(ClavesDetalleAgenda.cuando), findsOneWidget);
        expect(find.text('Sáb 24/10 · 15:30'), findsOneWidget);
        expect(find.text('15:00'), findsOneWidget);
      },
    );

    testWidgets('cambiar de entrevista a cobranza actualiza el título', (tester) async {
      final arnes = await montarDetalle(tester);
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));
      await _tocar(tester, _guardar);

      expect(arnes.repo.recibidos.single.tipo, TipoAgenda.cobranza);
      expect(arnes.recordatorios.programados['ag-1']!.tipo, TipoAgenda.cobranza);
      expect(find.byKey(ClavesDetalleAgenda.titulo), findsOneWidget);
      expect(find.text('Cobranza'), findsOneWidget);
    });

    testWidgets('la nota cambia y se ve en el detalle', (tester) async {
      await montarDetalle(tester);
      await _modificar(tester);
      await tester.enterText(find.byType(TextField), 'Pedir el teléfono del hijo');
      await _tocar(tester, _guardar);
      expect(find.text('Pedir el teléfono del hijo'), findsOneWidget);
    });

    testWidgets('sin permiso de notificaciones guarda y lo dice con verdad', (tester) async {
      final arnes = await montarDetalle(tester, permisoConcedido: false);
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));
      await _tocar(tester, _guardar);
      expect(arnes.repo.recibidos, hasLength(1));
      expect(
        find.text(
          'Guardado. Las notificaciones están apagadas: no te va a llegar el recordatorio.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('si falta menos que la anticipación no promete un recordatorio que no hay', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester, ahora: DateTime(2026, 10, 24, 14, 10));
      arnes.recordatorios.resultadoForzado = ResultadoRecordatorio.yaPaso;
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));
      expect(
        _textoDe(ClavesModificarAgenda.textoRecordatorio),
        'Falta menos de 30 min para la visita: no hay recordatorio.',
      );
      await _tocar(tester, _guardar);
      expect(
        find.text('Guardado. Falta menos de 30 min para la visita: no hay recordatorio.'),
        findsOneWidget,
      );
    });

    testWidgets('si el recordatorio no se pudo reprogramar, la agenda queda guardada y se avisa', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      arnes.recordatorios.resultadoForzado = ResultadoRecordatorio.noSePudo;
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));
      await _tocar(tester, _guardar);
      expect(arnes.repo.recibidos, hasLength(1));
      expect(
        find.text(
          'Guardado, pero no pudimos reprogramar el recordatorio. Revisá la visita en tu agenda.',
        ),
        findsOneWidget,
      );
    });
  });

  group('23C·07 · Error al guardar', () {
    testWidgets(
      'dado que falla el guardado, entonces avisa, conserva lo escrito y ofrece «Reintentar»',
      (tester) async {
        final arnes = await montarDetalle(tester);
        arnes.repo.fallas.add(const FailureInesperado());
        await _modificar(tester);
        await tester.enterText(find.byType(TextField), 'Mi nota');
        await _tocar(tester, find.text('Cobranza'));
        await _tocar(tester, _guardar);

        expect(
          find.text('No pudimos guardar el cambio. La agenda sigue como estaba.'),
          findsOneWidget,
        );
        expect(find.byKey(ClavesModificarAgenda.titulo), findsOneWidget);
        expect(find.text('Mi nota'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(
          arnes.recordatorios.programados,
          isEmpty,
          reason: 'el aviso solo se mueve si se guardó',
        );
      },
    );

    testWidgets('«Reintentar» guarda con el MISMO id de nota y cierra el formulario', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      arnes.repo.fallas.add(const FailureInesperado());
      await _modificar(tester);
      await tester.enterText(find.byType(TextField), 'Mi nota');
      await _tocar(tester, _guardar);
      await _tocar(tester, _guardar);

      expect(arnes.repo.recibidos, hasLength(2));
      expect(arnes.repo.recibidos.first.idNota, arnes.repo.recibidos.last.idNota);
      expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
      expect(find.text('No pudimos guardar el cambio. La agenda sigue como estaba.'), findsNothing);
    });

    testWidgets('si el guardado lanza una excepción a mitad, el botón vuelve a servir (no queda '
        '«Guardando…» trabado)', (tester) async {
      final arnes = await montarDetalle(tester);
      arnes.repo.lanzar = StateError('se cortó la base');
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));
      await _tocar(tester, _guardar);

      expect(find.byKey(ClavesModificarAgenda.avisoFalla), findsOneWidget);
      expect(find.text('Guardando…'), findsNothing);
      final boton = tester.widget<FilledButton>(
        find.descendant(of: _guardar, matching: find.byType(FilledButton)),
      );
      expect(boton.onPressed, isNotNull);
      // El texto de la excepción no se muestra: puede traer lo que escribió la persona.
      expect(find.textContaining('se cortó'), findsNothing);
    });

    testWidgets('si la agenda ya se cumplió mientras tanto, el aviso dice por qué', (tester) async {
      final arnes = await montarDetalle(tester);
      arnes.repo.fallas.add(
        const FailureValidacion(
          campos: {'agenda': 'Esta visita ya tiene resultado: no se puede modificar.'},
        ),
      );
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));
      await _tocar(tester, _guardar);
      expect(find.text('Esta visita ya tiene resultado: no se puede modificar.'), findsOneWidget);
    });
  });

  group('Doble toque y dos acciones seguidas', () {
    testWidgets('dos toques en «Guardar cambios» guardan una sola vez y el formulario no se cierra '
        'hasta que termina', (tester) async {
      final arnes = await montarDetalle(tester);
      arnes.repo.compuerta = Completer<void>();
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));

      await tester.tap(_guardar);
      await tester.pump();
      await tester.tap(_guardar);
      await asentarDetalle(tester);

      expect(arnes.repo.recibidos, hasLength(1));
      expect(find.text('Guardando…'), findsOneWidget);
      // Mientras guarda no se puede cerrar: ni la ✕ ni el botón atrás.
      expect(tester.widget<IconButton>(find.byKey(ClavesModificarAgenda.cerrar)).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await asentarDetalle(tester);
      expect(find.byKey(ClavesModificarAgenda.titulo), findsOneWidget);

      arnes.repo.compuerta!.complete();
      await asentarDetalle(tester);
      expect(find.byKey(ClavesModificarAgenda.titulo), findsNothing);
      expect(arnes.repo.recibidos, hasLength(1));
    });

    testWidgets(
      'dos cambios seguidos: el segundo parte de lo que dejó el primero y ninguno se pisa',
      (tester) async {
        final arnes = await montarDetalle(tester);
        await _modificar(tester);
        await _tocar(tester, find.text('Cobranza'));
        await _tocar(tester, _guardar);
        expect(find.text('Cobranza'), findsOneWidget);

        await _modificar(tester);
        await _subirHora(tester, 12);
        await _tocar(tester, _guardar);

        expect(arnes.repo.recibidos, hasLength(2));
        expect(arnes.repo.recibidos.first.tipo, TipoAgenda.cobranza);
        expect(arnes.repo.recibidos.last.tipo, TipoAgenda.cobranza);
        expect(
          arnes.repo.recibidos.last.fechaProgramada.isAtSameMomentAs(
            DateTime(2026, 10, 24, 15, 30),
          ),
          isTrue,
        );
        expect(arnes.repo.recibidos.first.idNota, isNot(arnes.repo.recibidos.last.idNota));
        expect(find.text('Sáb 24/10 · 15:30'), findsOneWidget);
      },
    );
  });

  group('Edge - la hora que ya pasó', () {
    Future<void> hoyAMediaTarde(WidgetTester tester) async {
      await _tocar(tester, _campo);
      await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(0)));
      await _tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
    }

    testWidgets('elegir una hora pasada la marca y avisa que no habrá recordatorio', (
      tester,
    ) async {
      await montarDetalle(tester);
      await _modificar(tester);
      await hoyAMediaTarde(tester);
      expect(find.text('Hoy · 14:30'), findsOneWidget);
      expect(find.byKey(ClavesAgendarVisita.errorHora), findsOneWidget);
      expect(
        _textoDe(ClavesModificarAgenda.textoRecordatorio),
        'Si la guardás igual, no te vamos a avisar: la hora ya pasó.',
      );
    });

    testWidgets('al guardar pide confirmar; «Guardar igual» guarda y saca el recordatorio viejo', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester);
      await arnes.recordatorios.programar(visitaParaAviso('ag-1', DateTime(2026, 10, 24, 14, 30)));
      await _modificar(tester);
      await hoyAMediaTarde(tester);
      await _tocar(tester, _guardar);

      expect(
        find.text('Hoy a las 14:30 ya pasó (son las 14:35). ¿La guardás igual?'),
        findsOneWidget,
      );
      expect(arnes.repo.recibidos, isEmpty);

      await _tocar(tester, find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual));
      expect(arnes.repo.recibidos, hasLength(1));
      expect(arnes.recordatorios.programados, isNot(contains('ag-1')));
      expect(find.text('Guardado. La hora ya había pasado: no hay recordatorio.'), findsOneWidget);
    });

    testWidgets('«Cambiar la hora» vuelve al selector sin guardar', (tester) async {
      final arnes = await montarDetalle(tester);
      await _modificar(tester);
      await hoyAMediaTarde(tester);
      await _tocar(tester, _guardar);
      await _tocar(tester, find.byKey(ClavesAgendarVisita.horaPasadaCambiar));
      expect(find.byKey(ClavesAgendarVisita.hojaListo), findsOneWidget);
      expect(arnes.repo.recibidos, isEmpty);
    });

    testWidgets('una agenda vencida que no cambia de hora no vuelve a preguntar', (tester) async {
      final arnes = await montarDetalle(tester, ahora: DateTime(2026, 10, 24, 18));
      await _modificar(tester);
      await _tocar(tester, find.text('Cobranza'));
      await _tocar(tester, _guardar);
      expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsNothing);
      expect(arnes.repo.recibidos, hasLength(1));
    });
  });

  group('La casa del formulario', () {
    testWidgets('si no se puede leer, «Guardar cambios» espera y la casa se reintenta', (
      tester,
    ) async {
      final arnes = await montarDetalle(tester, fallaDeCasa: const FailureInesperado());
      await _modificar(tester);
      expect(find.text('No pudimos leer la casa en tu teléfono.'), findsOneWidget);
      await tester.tap(_guardar, warnIfMissed: false);
      await asentarDetalle(tester);
      expect(arnes.repo.recibidos, isEmpty);
    });
  });

  group('Datos límite', () {
    testWidgets(
      'nota de 500 caracteres y texto al 200 % en 320×568: no desborda y se puede guardar',
      (tester) async {
        final arnes = await montarDetalle(
          tester,
          escala: 2,
          tamano: const Size(320, 568),
          detalle: DetalleDeAgenda(agenda: agendaDelDetalle(), nota: 'n' * 500),
        );
        await tester.scrollUntilVisible(
          find.byKey(ClavesDetalleAgenda.modificar),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _tocar(tester, find.byKey(ClavesDetalleAgenda.modificar));
        expect(tester.takeException(), isNull);
        await _tocar(tester, _guardar);
        expect(arnes.repo.recibidos, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  });
}
