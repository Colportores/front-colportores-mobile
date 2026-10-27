// «Agendar una visita» (vista 23, grupo A, HU-VIS-001, #408): un grupo por artboard (23A·01 a 23A·08) y
// los casos límite de cada flujo: doble toque, falla a mitad de la acción, dos acciones seguidas,
// volver atrás y reentrar, y datos límite (vacío, textos largos, textScaler 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/persona_falsos.dart';

final _boton = find.byKey(ClavesAgendarVisita.botonAgendar);
final _campo = find.byKey(ClavesAgendarVisita.campoDiaYHora);

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentarAgendar(tester);
}

Future<void> _abrirHoja(WidgetTester tester) => _tocar(tester, _campo);

Future<void> _repetir(WidgetTester tester, Key tecla, int veces) async {
  for (var i = 0; i < veces; i++) {
    await tester.tap(find.byKey(tecla));
    await tester.pump();
  }
}

Future<void> _listo(WidgetTester tester) =>
    _tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));

/// Elige hoy a las 11:00 (la hora ya pasó: son las 14:35).
Future<void> _hoyALas11(WidgetTester tester) async {
  await _abrirHoja(tester);
  await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(0)));
  await _repetir(tester, ClavesAgendarVisita.hojaMas, 12);
  await _listo(tester);
}

String _texto(Finder f) => (f.evaluate().single.widget as Text).data!;

void main() {
  group('23A·01 · Agendar entrevista', () {
    testWidgets('dado el canvas, cuando se abre, entonces dibuja todo el formulario', (
      tester,
    ) async {
      await montarAgendar(tester);
      expect(find.text('AGENDAR'), findsOneWidget);
      expect(find.text('Agendar visita'), findsOneWidget);
      expect(find.text('MF'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      expect(find.text('TIPO'), findsOneWidget);
      expect(find.text('Entrevista'), findsOneWidget);
      expect(find.text('Cobranza'), findsOneWidget);
      expect(find.text('DÍA Y HORA'), findsOneWidget);
      expect(find.text('Mañana · 10:00'), findsOneWidget);
      expect(find.text('FRANJA SUGERIDA'), findsOneWidget);
      for (final f in FranjaHoraria.values) {
        expect(find.byKey(ClavesAgendarVisita.franja(f)), findsOneWidget);
      }
      expect(find.text('NOTA (OPCIONAL)'), findsOneWidget);
      expect(find.text('Solo la ves vos'), findsOneWidget);
      expect(
        find.text('Te avisamos 30 min antes. Lo cambiás en Preferencias de notificaciones.'),
        findsOneWidget,
      );
      expect(find.descendant(of: _boton, matching: find.text('Agendar')), findsOneWidget);
      // Sin avisos: ni de permiso ni de falla.
      expect(find.byKey(ClavesAgendarVisita.avisoSinPermiso), findsNothing);
      expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsNothing);
      expect(find.byKey(ClavesAgendarVisita.errorHora), findsNothing);
    });

    testWidgets(
      'dada la hora por defecto, cuando se abre, entonces la franja sugerida viene elegida',
      (tester) async {
        await montarAgendar(tester);
        final elegida = tester.widget<ChoiceChip>(
          find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.mediaManiana)),
        );
        expect(elegida.selected, isTrue);
        final otra = tester.widget<ChoiceChip>(
          find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.primeraTarde)),
        );
        expect(otra.selected, isFalse);
      },
    );

    testWidgets(
      'dado el formulario completo, cuando se toca Agendar, entonces guarda, avisa y vuelve',
      (tester) async {
        final a = await montarAgendar(tester);
        await tester.enterText(find.byType(TextField), 'Tocar el timbre dos veces');
        await _tocar(tester, _boton);

        final recibida = a.repo.recibidas.single;
        expect(recibida.agenda.espacioId, 'esp-1');
        expect(recibida.agenda.espacioPersonaId, 'ep-p1');
        expect(recibida.agenda.tipo, TipoAgenda.entrevista);
        expect(recibida.agenda.colportorId, 'col-1');
        expect(recibida.agenda.slotCodigo, 'mid_morning');
        expect(recibida.agenda.fechaProgramada.toLocal(), DateTime(2026, 10, 24, 10));
        expect(recibida.nota?.texto, 'Tocar el timbre dos veces');
        expect(a.recordatorios.programados.values.single.direccion, 'Mataojo 2044 · Depto 3B');
        expect(a.resultados, [true]);
        expect(find.text('Agendar visita'), findsNothing);
        expect(find.text('Agendada. La casa queda como «Entrevista agendada».'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una cobranza, cuando se agenda, entonces el aviso no promete el color de la casa',
      (tester) async {
        final a = await montarAgendar(tester, tipo: TipoAgenda.cobranza);
        await _tocar(tester, _boton);
        expect(a.repo.recibidas.single.agenda.tipo, TipoAgenda.cobranza);
        expect(find.text('Agendada.'), findsOneWidget);
        expect(find.textContaining('Entrevista agendada'), findsNothing);
      },
    );

    testWidgets(
      'dado el selector de tipo, cuando se elige Cobranza, entonces se agenda una cobranza',
      (tester) async {
        final a = await montarAgendar(tester);
        await _tocar(tester, find.text('Cobranza'));
        await _tocar(tester, _boton);
        expect(a.repo.recibidas.single.agenda.tipo, TipoAgenda.cobranza);
      },
    );

    testWidgets(
      'dada la franja tocada, cuando se toca otra, entonces cambia; y tocar la elegida la saca',
      (tester) async {
        final a = await montarAgendar(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.primeraTarde)));
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.primeraTarde)),
              )
              .selected,
          isTrue,
        );
        await _tocar(tester, find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.primeraTarde)));
        await _tocar(tester, _boton);
        expect(a.repo.recibidas.single.agenda.slotCodigo, isNull);
      },
    );

    testWidgets('dada una nota en blanco, cuando se agenda, entonces no guarda nota', (
      tester,
    ) async {
      final a = await montarAgendar(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await _tocar(tester, _boton);
      expect(a.repo.recibidas.single.nota, isNull);
    });

    testWidgets(
      'dado el lector de pantalla, cuando recorre el formulario, entonces lee el campo y los chips',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await montarAgendar(tester);
        expect(
          find.bySemanticsLabel('Día y hora: Mañana · 10:00. Tocá para cambiar'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Media mañana, 10:00 a 11:30, elegida'), findsOneWidget);
        expect(find.bySemanticsLabel('Primera tarde, 16:30 a 18:00'), findsOneWidget);
        semantica.dispose();
      },
    );
  });

  group('23A·02 · Día y hora', () {
    testWidgets('dada la hoja, cuando se abre, entonces muestra los días, la hora y la franja', (
      tester,
    ) async {
      await montarAgendar(tester);
      await _abrirHoja(tester);
      expect(find.text('Día y hora'), findsOneWidget);
      expect(find.text('DÍA'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Mañana'), findsOneWidget);
      expect(find.text('Dom 25'), findsOneWidget);
      expect(find.text('Lun 26'), findsOneWidget);
      expect(find.text('Mar 27'), findsOneWidget);
      expect(find.text('Otro día…'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('Franja sugerida: media mañana'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.byKey(ClavesAgendarVisita.dia(1))).selected, isTrue);
    });

    testWidgets(
      'dado un día y una hora elegidos, cuando se toca Listo, entonces el campo los refleja',
      (tester) async {
        final a = await montarAgendar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(3)));
        await _repetir(tester, ClavesAgendarVisita.hojaMas, 3);
        await tester.pump();
        expect(find.text('10:15'), findsOneWidget);
        await _listo(tester);
        expect(find.text('Lunes 26/10 · 10:15'), findsOneWidget);
        await _tocar(tester, _boton);
        expect(
          a.repo.recibidas.single.agenda.fechaProgramada.toLocal(),
          DateTime(2026, 10, 26, 10, 15),
        );
      },
    );

    testWidgets(
      'dada la hora, cuando se baja de las 00:00 y se sube de las 23:55, entonces da la vuelta',
      (tester) async {
        await montarAgendar(tester);
        await _abrirHoja(tester);
        await _repetir(tester, ClavesAgendarVisita.hojaMenos, 120); // 10:00 -> 00:00
        expect(find.text('00:00'), findsOneWidget);
        await tester.tap(find.byKey(ClavesAgendarVisita.hojaMenos));
        await tester.pump();
        expect(find.text('23:55'), findsOneWidget);
        await tester.tap(find.byKey(ClavesAgendarVisita.hojaMas));
        await tester.pump();
        expect(find.text('00:00'), findsOneWidget);
        // Antes de las 08:30 la sugerida es la primera del día.
        expect(find.text('Franja sugerida: primera mañana'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una hora sin franja (21:00), cuando se mira la hoja, entonces no sugiere ninguna',
      (tester) async {
        await montarAgendar(tester);
        await _abrirHoja(tester);
        await _repetir(tester, ClavesAgendarVisita.hojaMas, 132); // 10:00 -> 21:00
        expect(find.text('21:00'), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.hojaFranja), findsNothing);
      },
    );

    testWidgets('dada la hoja cerrada sin Listo, cuando se vuelve, entonces no cambió nada', (
      tester,
    ) async {
      await montarAgendar(tester);
      await _abrirHoja(tester);
      await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(0)));
      await tester.tapAt(const Offset(195, 10));
      await asentarAgendar(tester);
      expect(find.text('Listo'), findsNothing);
      expect(find.text('Mañana · 10:00'), findsOneWidget);
    });

    testWidgets(
      'dada la franja sugerida, cuando cambia la hora y no se tocó a mano, entonces la sigue',
      (tester) async {
        await montarAgendar(tester);
        await _abrirHoja(tester);
        await _repetir(tester, ClavesAgendarVisita.hojaMas, 78); // 10:00 -> 16:30
        await _listo(tester);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.primeraTarde)),
              )
              .selected,
          isTrue,
        );
      },
    );

    testWidgets(
      'dada una franja elegida a mano, cuando cambia la hora, entonces se respeta la elección',
      (tester) async {
        final a = await montarAgendar(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.finDeTarde)));
        await _abrirHoja(tester);
        await _repetir(tester, ClavesAgendarVisita.hojaMas, 78);
        await _listo(tester);
        await _tocar(tester, _boton);
        expect(a.repo.recibidas.single.agenda.slotCodigo, 'late_afternoon');
      },
    );

    testWidgets('dado Otro día…, cuando se elige una fecha, entonces aparece como chip elegido', (
      tester,
    ) async {
      final a = await montarAgendar(tester);
      await _abrirHoja(tester);
      await _tocar(tester, find.byKey(ClavesAgendarVisita.otroDia));
      await tester.tap(find.text('30'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await asentarAgendar(tester);
      expect(find.byKey(ClavesAgendarVisita.diaElegido), findsOneWidget);
      expect(find.text('Vie 30/10'), findsOneWidget);
      await _listo(tester);
      expect(find.text('Viernes 30/10 · 10:00'), findsOneWidget);
      await _tocar(tester, _boton);
      expect(a.repo.recibidas.single.agenda.fechaProgramada.toLocal(), DateTime(2026, 10, 30, 10));
    });

    testWidgets(
      'dado textScaler 2.0 en un teléfono chico, cuando se abre la hoja, entonces no desborda',
      (tester) async {
        await montarAgendar(tester, escala: 2, tamano: const Size(320, 568));
        await _abrirHoja(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(ClavesAgendarVisita.hojaListo));
        expect(find.byKey(ClavesAgendarVisita.hojaListo), findsOneWidget);
      },
    );
  });

  group('23A·03 · La hora ya pasó', () {
    testWidgets(
      'dada una hora de hoy que ya pasó, cuando se elige, entonces el campo se marca y avisa',
      (tester) async {
        await montarAgendar(tester);
        await _hoyALas11(tester);
        expect(find.text('Hoy · 11:00'), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.errorHora), findsOneWidget);
        expect(_texto(find.byKey(ClavesAgendarVisita.errorHora)), 'Esa hora ya pasó');
        expect(
          find.text('Si la agendás igual, no te vamos a avisar: la hora ya pasó.'),
          findsOneWidget,
        );
        expect(find.textContaining('Te avisamos'), findsNothing);
      },
    );

    testWidgets(
      'dada la hora pasada, cuando se toca Agendar, entonces pregunta y no guarda todavía',
      (tester) async {
        final a = await montarAgendar(tester);
        await _hoyALas11(tester);
        await _tocar(tester, _boton);
        expect(
          find.text('Hoy a las 11:00 ya pasó (son las 14:35). ¿La agendás igual?'),
          findsOneWidget,
        );
        expect(find.text('Agendar igual'), findsOneWidget);
        expect(find.text('Cambiar la hora'), findsOneWidget);
        expect(a.repo.recibidas, isEmpty);
        expect(a.recordatorios.llamadas, isEmpty);
      },
    );

    testWidgets(
      'dada la pregunta, cuando se elige Agendar igual, entonces guarda sin recordatorio',
      (tester) async {
        final a = await montarAgendar(tester);
        await _hoyALas11(tester);
        await _tocar(tester, _boton);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual));
        expect(a.repo.cuantasQuedaron, 1);
        expect(a.recordatorios.llamadas, isEmpty);
        expect(a.resultados, [true]);
        expect(
          find.text('Agendada. La hora ya había pasado: no hay recordatorio.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'dada la pregunta, cuando se elige Cambiar la hora, entonces abre la hoja y no guarda',
      (tester) async {
        final a = await montarAgendar(tester);
        await _hoyALas11(tester);
        await _tocar(tester, _boton);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.horaPasadaCambiar));
        expect(find.text('Día y hora'), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.hojaListo), findsOneWidget);
        expect(a.repo.recibidas, isEmpty);
      },
    );

    testWidgets(
      'dada la pregunta cerrada sin elegir, cuando se vuelve, entonces no se guardó y se puede reintentar',
      (tester) async {
        final a = await montarAgendar(tester);
        await _hoyALas11(tester);
        await _tocar(tester, _boton);
        await tester.tapAt(const Offset(195, 10));
        await asentarAgendar(tester);
        expect(a.repo.recibidas, isEmpty);
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(of: _boton, matching: find.byType(FilledButton)),
              )
              .onPressed,
          isNotNull,
        );
        await _tocar(tester, _boton);
        expect(find.text('Agendar igual'), findsOneWidget);
      },
    );

    testWidgets(
      'dado el reloj que avanza mientras el formulario está abierto, cuando la hora pasa, entonces pregunta',
      (tester) async {
        final a = await montarAgendar(tester);
        // Mañana a las 10:00 y la persona recién guarda a las 10:30 de ese día.
        a.ahora = DateTime(2026, 10, 24, 10, 30);
        await _tocar(tester, _boton);
        expect(
          find.text('Hoy a las 10:00 ya pasó (son las 10:30). ¿La agendás igual?'),
          findsOneWidget,
        );
        expect(a.repo.recibidas, isEmpty);
      },
    );

    testWidgets(
      'dada una fecha de otro día que ya pasó, cuando se arma la pregunta, entonces dice el día',
      (tester) async {
        final a = await montarAgendar(tester);
        a.ahora = DateTime(2026, 10, 27, 9);
        await _tocar(tester, _boton);
        expect(
          find.text('El sáb 24/10 a las 10:00 ya pasó (son las 09:00). ¿La agendás igual?'),
          findsOneWidget,
        );
      },
    );

    testWidgets('dado textScaler 2.0, cuando se muestra la pregunta, entonces no desborda', (
      tester,
    ) async {
      await montarAgendar(tester, escala: 2, tamano: const Size(320, 568));
      await _hoyALas11(tester);
      await _tocar(tester, _boton);
      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsOneWidget);
    });
  });

  group('23A·04 · Agendando', () {
    testWidgets(
      'dado un guardado en curso, cuando se espera, entonces el botón dice Agendando… y todo se bloquea',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        final a = await montarAgendar(tester, repo: repo);
        await tester.tap(_boton);
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.descendant(of: _boton, matching: find.text('Agendando…')), findsOneWidget);
        final fb = tester.widget<FilledButton>(
          find.descendant(of: _boton, matching: find.byType(FilledButton)),
        );
        expect(fb.onPressed, isNull);
        expect(tester.widget<IconButton>(find.byKey(ClavesAgendarVisita.cerrar)).onPressed, isNull);
        expect(a.resultados, isEmpty);
        repo.compuerta!.complete();
        await asentarAgendar(tester);
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'dado un doble toque, cuando el primero está en curso, entonces se guarda una sola agenda',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        final a = await montarAgendar(tester, repo: repo);
        await tester.tap(_boton);
        await tester.tap(_boton);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(_boton, warnIfMissed: false);
        repo.compuerta!.complete();
        await asentarAgendar(tester);
        expect(repo.recibidas, hasLength(1));
        expect(repo.cuantasQuedaron, 1);
        expect(a.recordatorios.programados, hasLength(1));
        expect(a.rutas.cierres, 1);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando se intenta salir, entonces la pantalla no se cierra',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        final a = await montarAgendar(tester, repo: repo);
        await tester.tap(_boton);
        await tester.pump(const Duration(milliseconds: 50));
        final navegador = tester.state<NavigatorState>(find.byType(Navigator));
        await navegador.maybePop();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Agendar visita'), findsOneWidget);
        expect(a.rutas.cierres, 0);
        repo.compuerta!.complete();
        await asentarAgendar(tester);
      },
    );

    testWidgets(
      'dadas dos acciones seguidas, cuando se cambia el tipo con el guardado en curso, entonces no se pisa',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        await montarAgendar(tester, repo: repo);
        await tester.tap(_boton);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Cobranza'), warnIfMissed: false);
        await tester.tap(_campo, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Listo'), findsNothing);
        repo.compuerta!.complete();
        await asentarAgendar(tester);
        expect(repo.recibidas.single.agenda.tipo, TipoAgenda.entrevista);
      },
    );

    testWidgets(
      'dado un guardado lento, cuando termina con el teléfono girado a 2.0, entonces no desborda',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        await montarAgendar(tester, repo: repo, escala: 2, tamano: const Size(320, 568));
        await tester.tap(_boton);
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        repo.compuerta!.complete();
        await asentarAgendar(tester);
      },
    );
  });

  group('23A·05 · Agendada (éxito)', () {
    testWidgets('dado un guardado completo, cuando termina, entonces vuelve y avisa una sola vez', (
      tester,
    ) async {
      final a = await montarAgendar(tester);
      await _tocar(tester, _boton);
      expect(a.resultados, [true]);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Agendada. La casa queda como «Entrevista agendada».'), findsOneWidget);
    });

    testWidgets(
      'dado un recordatorio que no se pudo programar, cuando se agenda, entonces el aviso lo dice',
      (tester) async {
        final a = await montarAgendar(tester);
        a.recordatorios.resultadoForzado = ResultadoRecordatorio.noSePudo;
        await _tocar(tester, _boton);
        expect(a.repo.cuantasQuedaron, 1);
        expect(
          find.text(
            'Agendada, pero no pudimos programar el recordatorio. Revisá la visita en tu agenda.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'dado un recordatorio con menos tiempo que la anticipación, cuando se agenda, entonces lo dice',
      (tester) async {
        final a = await montarAgendar(tester);
        await _abrirHoja(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(0)));
        await _repetir(tester, ClavesAgendarVisita.hojaMas, 58); // 10:00 -> 14:50
        await _listo(tester);
        expect(
          find.text('Falta menos de 30 min para la visita: no hay recordatorio.'),
          findsOneWidget,
        );
        a.recordatorios.resultadoForzado = ResultadoRecordatorio.yaPaso;
        await _tocar(tester, _boton);
        expect(
          find.text('Agendada. Falta menos de 30 min para la visita: no hay recordatorio.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'dados los recordatorios apagados en las preferencias, cuando se agenda, entonces avisa que no habrá aviso',
      (tester) async {
        final a = await montarAgendar(tester);
        a.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
        a.recordatorios.resultadoForzado = ResultadoRecordatorio.apagados;
        // Vuelve a leer las preferencias como al volver a la app.
        a.telefono.recordatorios.permisoConcedido = true;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await asentarAgendar(tester);
        expect(find.textContaining('Los recordatorios de agenda están apagados'), findsOneWidget);
        expect(find.textContaining('Te avisamos'), findsNothing);
        await _tocar(tester, _boton);
        expect(
          find.text('Agendada. Los recordatorios están apagados: no te vamos a avisar.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('dada una anticipación de 60 minutos, cuando se abre, entonces el texto la usa', (
      tester,
    ) async {
      final a = await montarAgendar(tester, abrir: false);
      a.preferencias.preferencias = const PreferenciasRecordatorios(anticipacionMinutos: 60);
      await abrirAgendar(tester);
      expect(
        find.text('Te avisamos 60 min antes. Lo cambiás en Preferencias de notificaciones.'),
        findsOneWidget,
      );
    });
  });

  group('23A·06 · Error al guardar', () {
    testWidgets(
      'dada una falla del repositorio, cuando se agenda, entonces muestra el aviso y Reintentar',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
        final a = await montarAgendar(tester, repo: repo);
        await tester.enterText(find.byType(TextField), 'No perder esta nota');
        await _tocar(tester, _boton);
        expect(
          find.text('No pudimos guardar la agenda en tu teléfono. Probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.descendant(of: _boton, matching: find.text('Reintentar')), findsOneWidget);
        // Sigue en la pantalla, con lo escrito, y el botón vuelve a habilitarse.
        expect(find.text('Agendar visita'), findsOneWidget);
        expect(find.text('No perder esta nota'), findsOneWidget);
        final fb = tester.widget<FilledButton>(
          find.descendant(of: _boton, matching: find.byType(FilledButton)),
        );
        expect(fb.onPressed, isNotNull);
        expect(find.text('Agendando…'), findsNothing);
        expect(a.resultados, isEmpty);
        expect(a.recordatorios.llamadas, isEmpty);
      },
    );

    testWidgets('dada una falla, cuando se toca Reintentar, entonces guarda con los mismos ids', (
      tester,
    ) async {
      final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
      final a = await montarAgendar(tester, repo: repo);
      await _tocar(tester, _boton);
      await _tocar(tester, _boton);
      expect(repo.recibidas, hasLength(2));
      expect(repo.recibidas.map((e) => e.agenda.id).toSet(), hasLength(1));
      expect(repo.cuantasQuedaron, 1);
      expect(a.resultados, [true]);
      expect(find.text('Agendada. La casa queda como «Entrevista agendada».'), findsOneWidget);
    });

    testWidgets(
      'dada una excepción del repositorio, cuando se agenda, entonces no queda trabado en Agendando…',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..lanzar = StateError('Mataojo 2044 · María');
        await montarAgendar(tester, repo: repo);
        await _tocar(tester, _boton);
        expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsOneWidget);
        // El detalle de la excepción (puede traer datos de la persona) no llega a la pantalla.
        expect(find.textContaining('StateError'), findsNothing);
        expect(find.textContaining('Bad state'), findsNothing);
        final fb = tester.widget<FilledButton>(
          find.descendant(of: _boton, matching: find.byType(FilledButton)),
        );
        expect(fb.onPressed, isNotNull);
        await _tocar(tester, _boton);
        expect(repo.cuantasQuedaron, 1);
      },
    );

    testWidgets('dadas dos fallas seguidas, cuando se reintenta, entonces el aviso no se duplica', (
      tester,
    ) async {
      final repo = AgendaRepositorioQueAgenda()
        ..fallas.addAll([const FailureInesperado(), const FailureInesperado()]);
      await montarAgendar(tester, repo: repo);
      await _tocar(tester, _boton);
      await _tocar(tester, _boton);
      expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsOneWidget);
      await _tocar(tester, _boton);
      expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsNothing);
    });
  });

  group('23A·07 · Sin permiso de notificaciones', () {
    testWidgets('dado el permiso apagado, cuando se abre, entonces avisa y ofrece activarlas', (
      tester,
    ) async {
      await montarAgendar(
        tester,
        permisoConcedido: false,
        estadoSistema: EstadoSistemaNotificaciones.apagadas,
      );
      expect(find.byKey(ClavesAgendarVisita.avisoSinPermiso), findsOneWidget);
      expect(
        find.text(
          'Las notificaciones están apagadas: la visita se agenda, pero no te va a llegar el recordatorio.',
        ),
        findsOneWidget,
      );
      expect(find.text('Activar notificaciones'), findsOneWidget);
      // El texto del recordatorio queda en blanco.
      expect(find.byKey(ClavesAgendarVisita.textoRecordatorio), findsNothing);
      expect(find.textContaining('Te avisamos'), findsNothing);
    });

    testWidgets(
      'dado el permiso apagado, cuando se agenda, entonces la visita se guarda y el aviso lo aclara',
      (tester) async {
        final a = await montarAgendar(
          tester,
          permisoConcedido: false,
          estadoSistema: EstadoSistemaNotificaciones.apagadas,
        );
        await _tocar(tester, _boton);
        expect(a.repo.cuantasQuedaron, 1);
        expect(a.resultados, [true]);
        expect(
          find.text(
            'Agendada. Las notificaciones están apagadas: no te va a llegar el recordatorio.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'dado Activar notificaciones, cuando se toca, entonces pide el permiso una sola vez',
      (tester) async {
        final a = await montarAgendar(
          tester,
          permisoConcedido: false,
          estadoSistema: EstadoSistemaNotificaciones.apagadas,
        );
        // El diálogo del sistema sigue abierto mientras se toca por segunda vez.
        a.sistema.dialogoAbierto = Completer<void>();
        await tester.ensureVisible(find.byKey(ClavesAgendarVisita.accionNotificaciones));
        await tester.tap(find.byKey(ClavesAgendarVisita.accionNotificaciones));
        await asentarAgendar(tester, 2);
        await tester.tap(find.byKey(ClavesAgendarVisita.accionNotificaciones), warnIfMissed: false);
        await asentarAgendar(tester, 2);
        a.sistema.dialogoAbierto!.complete();
        await asentarAgendar(tester);
        expect(a.sistema.pedidos, 1);
        // Al volver el permiso, el aviso desaparece y vuelve el texto del recordatorio.
        a.recordatorios.permisoConcedido = true;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await asentarAgendar(tester);
        expect(find.byKey(ClavesAgendarVisita.avisoSinPermiso), findsNothing);
        expect(find.textContaining('Te avisamos 30 min antes'), findsOneWidget);
      },
    );

    testWidgets(
      'dado un permiso negado en el diálogo, cuando se vuelve a mirar, entonces ofrece los ajustes',
      (tester) async {
        final a = await montarAgendar(
          tester,
          permisoConcedido: false,
          estadoSistema: EstadoSistemaNotificaciones.apagadas,
        );
        a.sistema.respuestaAlPedir = false;
        await _tocar(tester, find.byKey(ClavesAgendarVisita.accionNotificaciones));
        expect(find.text('Abrir ajustes del teléfono'), findsOneWidget);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.accionNotificaciones));
        expect(a.sistema.ajustesAbiertos, 1);
      },
    );

    testWidgets(
      'dado un diálogo que no llega a mostrarse, cuando se toca, entonces lo dice y no se traba',
      (tester) async {
        final a = await montarAgendar(
          tester,
          permisoConcedido: false,
          estadoSistema: EstadoSistemaNotificaciones.apagadas,
        );
        a.sistema.fallaAlPedir = true;
        await _tocar(tester, find.byKey(ClavesAgendarVisita.accionNotificaciones));
        expect(
          find.text(
            'No pudimos activar las notificaciones desde acá. Activalas en los ajustes del teléfono.',
          ),
          findsOneWidget,
        );
        final enlace = tester.widget<TextButton>(
          find
              .descendant(
                of: find.byKey(ClavesAgendarVisita.accionNotificaciones),
                matching: find.byType(TextButton),
              )
              .first,
        );
        expect(enlace.onPressed, isNotNull);
      },
    );

    testWidgets(
      'dado el aviso de permiso, cuando se agrega una falla de guardado, entonces conviven',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
        await montarAgendar(
          tester,
          repo: repo,
          permisoConcedido: false,
          estadoSistema: EstadoSistemaNotificaciones.apagadas,
        );
        await _tocar(tester, _boton);
        expect(find.byKey(ClavesAgendarVisita.avisoSinPermiso), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsOneWidget);
      },
    );

    testWidgets('dado textScaler 2.0 con ambos avisos, cuando se abre, entonces no desborda', (
      tester,
    ) async {
      final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
      await montarAgendar(
        tester,
        repo: repo,
        permisoConcedido: false,
        estadoSistema: EstadoSistemaNotificaciones.apagadas,
        escala: 2,
        tamano: const Size(320, 568),
      );
      await _tocar(tester, _boton);
      expect(tester.takeException(), isNull);
    });
  });

  group('23A·08 · Sin conexión', () {
    testWidgets(
      'dado un teléfono sin conexión, cuando se agenda, entonces funciona igual y sin avisos',
      (tester) async {
        final a = await montarAgendar(tester, abrir: false);
        a.telefono.conexion.cambiarA(TipoConexion.sinConexion);
        await abrirAgendar(tester);
        expect(find.textContaining('conexión'), findsNothing);
        expect(find.textContaining('internet'), findsNothing);
        await _tocar(tester, _boton);
        expect(a.repo.cuantasQuedaron, 1);
        expect(a.resultados, [true]);
      },
    );
  });

  group('Persona y casa', () {
    testWidgets(
      'dada una agenda sin persona, cuando se abre, entonces dice Sin persona y guarda sin ella',
      (tester) async {
        final a = await montarAgendar(tester, espacioPersonaId: null);
        expect(find.text('Sin persona'), findsOneWidget);
        expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
        await _tocar(tester, _boton);
        expect(a.repo.recibidas.single.agenda.espacioPersonaId, isNull);
      },
    );

    testWidgets('dado un vínculo que ya no está, cuando se abre, entonces no inventa un nombre', (
      tester,
    ) async {
      await montarAgendar(tester, espacioPersonaId: 'ep-no-existe');
      expect(find.text('Sin persona'), findsOneWidget);
      expect(find.text('MF'), findsNothing);
    });

    testWidgets(
      'dada una casa que carga, cuando termina, entonces reemplaza el esqueleto por los datos',
      (tester) async {
        final espera = Completer<void>();
        await montarAgendar(tester, casaDemorada: espera);
        expect(find.text('Mataojo 2044 · Depto 3B'), findsNothing);
        expect(find.byKey(ClavesAgendarVisita.tarjetaPersona), findsOneWidget);
        espera.complete();
        await asentarAgendar(tester);
        expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una casa que no termina de cargar, cuando se toca Agendar, entonces igual se puede agendar',
      (tester) async {
        final espera = Completer<void>();
        final a = await montarAgendar(tester, casaDemorada: espera);
        await _tocar(tester, _boton);
        expect(a.repo.cuantasQuedaron, 1);
        // Sin la casa leída, el aviso lleva la dirección vacía en vez de inventar una.
        expect(a.recordatorios.programados.values.single.direccion, '');
      },
    );

    testWidgets(
      'dada una lectura de la casa que falla, cuando se abre, entonces lo dice y deja reintentar',
      (tester) async {
        await montarAgendar(tester, fallaDeCasa: const FailureInesperado());
        expect(find.text('No pudimos leer la casa en tu teléfono.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        await _tocar(tester, find.widgetWithText(TextButton, 'Reintentar'));
        expect(find.text('No pudimos leer la casa en tu teléfono.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dada una casa que ya no está, cuando se abre, entonces avisa que vuelva al mapa', (
      tester,
    ) async {
      await montarAgendar(tester, sinCasa: true);
      expect(
        find.text('Esta casa ya no está en tu teléfono. Volvé al mapa y elegila de nuevo.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'dada una casa que no es edificio, cuando se agenda, entonces la dirección no lleva depto',
      (tester) async {
        final a = await montarAgendar(
          tester,
          casa: (
            espacio: espacioDePersonas(numeroDepto: null, piso: null),
            ubicacion: ubicacionDePersonas(
              tipo: TipoUbicacion.casa,
              calle: 'Grecia',
              numero: '3307',
            ),
          ),
        );
        await _tocar(tester, _boton);
        expect(a.recordatorios.programados.values.single.direccion, 'Grecia 3307');
      },
    );

    testWidgets(
      'dado un edificio, cuando se agenda, entonces el aviso lleva el depto pero no el nombre',
      (tester) async {
        final a = await montarAgendar(tester);
        await _tocar(tester, _boton);
        final direccion = a.recordatorios.programados.values.single.direccion;
        expect(direccion, 'Mataojo 2044 · Depto 3B');
        expect(direccion, isNot(contains('María')));
      },
    );
  });

  group('Volver atrás y reentrar', () {
    testWidgets(
      'dada la pantalla cerrada con la X, cuando se vuelve a abrir, entonces arranca limpia',
      (tester) async {
        final a = await montarAgendar(tester);
        await tester.enterText(find.byType(TextField), 'Borrador');
        await _abrirHoja(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(0)));
        await _listo(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.cerrar));
        expect(a.resultados, [false]);
        expect(a.repo.recibidas, isEmpty);

        await abrirAgendar(tester);
        expect(find.text('Borrador'), findsNothing);
        expect(find.text('Mañana · 10:00'), findsOneWidget);
        await _tocar(tester, _boton);
        expect(a.resultados, [false, true]);
        expect(a.repo.cuantasQuedaron, 1);
      },
    );

    testWidgets(
      'dada una visita ya agendada, cuando se abre otra, entonces es una agenda nueva con otros ids',
      (tester) async {
        final a = await montarAgendar(tester);
        await _tocar(tester, _boton);
        await abrirAgendar(tester);
        await _tocar(tester, _boton);
        expect(a.repo.cuantasQuedaron, 2);
        expect(a.repo.recibidas.map((e) => e.agenda.id).toSet(), hasLength(2));
        expect(a.resultados, [true, true]);
      },
    );

    testWidgets(
      'dado el atrás del sistema, cuando no hay nada en curso, entonces vuelve sin guardar',
      (tester) async {
        final a = await montarAgendar(tester);
        final navegador = tester.state<NavigatorState>(find.byType(Navigator));
        await navegador.maybePop();
        await asentarAgendar(tester);
        expect(a.resultados, [false]);
        expect(a.repo.recibidas, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('dada una sesión sin usuario, cuando se intenta abrir, entonces no se abre nada', (
      tester,
    ) async {
      final a = await montarAgendar(tester, colportorId: ' ', abrir: false);
      await tester.tap(find.text('abrir agenda'));
      await asentarAgendar(tester);
      expect(a.resultados, [false]);
      expect(find.text('Agendar visita'), findsNothing);
      expect(a.rutas.aperturas, 1);
    });

    testWidgets(
      'dado el aviso de éxito, cuando se abre otra pantalla igual, entonces no queda un aviso viejo',
      (tester) async {
        final a = await montarAgendar(tester);
        await _tocar(tester, _boton);
        expect(find.byType(SnackBar), findsOneWidget);
        await abrirAgendar(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.cerrar));
        expect(a.resultados, [true, false]);
      },
    );
  });

  group('Datos límite', () {
    testWidgets('dada una nota de 600 caracteres, cuando se pega, entonces se corta en el tope', (
      tester,
    ) async {
      final a = await montarAgendar(tester);
      await tester.enterText(find.byType(TextField), 'ñ' * 600);
      await _tocar(tester, _boton);
      expect(a.repo.recibidas.single.nota!.texto.runes.length, 500);
    });

    testWidgets(
      'dada una nota con emoji, saltos de línea y acentos, cuando se agenda, entonces llega igual',
      (tester) async {
        final a = await montarAgendar(tester);
        await tester.enterText(find.byType(TextField), 'Tocá fuerte 🔔\nDepto 3B – “fondo”');
        await _tocar(tester, _boton);
        expect(a.repo.recibidas.single.nota!.texto, 'Tocá fuerte 🔔\nDepto 3B – “fondo”');
      },
    );

    testWidgets(
      'dados un nombre y una dirección larguísimos, cuando se abre a 2.0, entonces no desborda y se llega al botón',
      (tester) async {
        final larga = 'Maximiliano ' * 8;
        await montarAgendar(
          tester,
          personas: [clienteDePersonas('p1', larga, apellido: 'de la Santísima Trinidad ' * 3)],
          casa: (
            espacio: espacioDePersonas(numeroDepto: '3B', piso: null),
            ubicacion: ubicacionDePersonas(
              calle: 'Avenida General Don José Gervasio Artigas ' * 2,
              numero: '1234',
            ),
          ),
          escala: 2,
          tamano: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
        expect(_boton, findsOneWidget);
        await tester.ensureVisible(_campo);
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado textScaler 2.0 en 320x568, cuando se llega a cada campo, entonces todo es alcanzable',
      (tester) async {
        final a = await montarAgendar(tester, escala: 2, tamano: const Size(320, 568));
        for (final k in [
          ClavesAgendarVisita.campoDiaYHora,
          ClavesAgendarVisita.franja(FranjaHoraria.finDeTarde),
        ]) {
          await tester.ensureVisible(find.byKey(k));
          await tester.pump();
        }
        await tester.ensureVisible(find.byType(TextField));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _tocar(tester, _boton);
        expect(a.repo.cuantasQuedaron, 1);
      },
    );

    testWidgets(
      'dados los tamaños mínimos de toque, cuando se miden los controles, entonces miden 48 o más',
      (tester) async {
        await montarAgendar(tester);
        for (final f in [
          find.byKey(ClavesAgendarVisita.cerrar),
          _campo,
          _boton,
          find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.mediaManiana)),
        ]) {
          final r = tester.getRect(f);
          expect(r.height, greaterThanOrEqualTo(48), reason: '$f');
        }
      },
    );
  });
}
