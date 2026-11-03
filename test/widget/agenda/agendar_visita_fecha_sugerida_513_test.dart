// Vista 39, R·02 y R·03 en «Agendar visita» (#513): la fecha sugerida por las entrevistas cercanas
// (300 m) y el interruptor «Entrevista estricta» con la hora acordada. Inventario del canvas:
//   R·02 PROGRAMAR ENTREVISTA   → tarjeta SUGERIDA + franjas + interruptor apagado
//   R·03 ENTREVISTA ESTRICTA    → tarjeta FECHA + interruptor prendido + HORA ACORDADA
//   estados que pide la HU y el canvas no dibuja: cargando, vacío, error de lectura, sin conexión
//   (todo es local), éxito y falla al guardar.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/entrevista_cercana.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';

final _boton = find.byKey(ClavesAgendarVisita.botonAgendar);
final _campo = find.byKey(ClavesAgendarVisita.campoDiaYHora);
final _tarjeta = find.byKey(ClavesAgendarVisita.tarjetaFecha);
final _interruptor = find.byKey(ClavesAgendarVisita.interruptorEstricta);
final _horaAcordada = find.byKey(ClavesAgendarVisita.campoHoraAcordada);

/// Dos entrevistas el lunes 26/10 por la tarde (el canvas dibuja «2 entrevistas a menos de 300 m»):
/// 16:30 a 18:00, «Primera tarde».
final _dosEnLaTarde = [
  EntrevistaCercana(fecha: DateTime(2026, 10, 26, 16, 45)),
  EntrevistaCercana(fecha: DateTime(2026, 10, 26, 17, 15)),
];

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentarAgendar(tester);
}

bool _prendido(WidgetTester tester) => tester.widget<SwitchListTile>(_interruptor).value;

Future<ArnesAgendar> _montar(
  WidgetTester tester, {
  List<EntrevistaCercana>? cercanas,
  EntrevistasCercanasFalsas? lectura,
  AgendaRepositorioQueAgenda? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) => montarAgendar(
  tester,
  cercanas: lectura ?? EntrevistasCercanasFalsas(cercanas ?? _dosEnLaTarde),
  repo: repo,
  escala: escala,
  tamano: tamano,
  abrir: abrir,
);

void main() {
  group('R·02 · la fecha sugerida', () {
    testWidgets(
      'dado que hay 2 entrevistas a menos de 300 m, cuando se abre, entonces dibuja la tarjeta SUGERIDA como el canvas',
      (tester) async {
        final lectura = EntrevistasCercanasFalsas(_dosEnLaTarde);
        await _montar(tester, lectura: lectura);
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(find.text('Lunes 26/10 · 16:30 a 18:00'), findsOneWidget);
        expect(find.text('2 entrevistas a menos de 300 m ese día'), findsOneWidget);
        expect(find.text('Cambiar'), findsOneWidget);
        expect(find.text('Entrevista estricta'), findsOneWidget);
        expect(find.text('Hora fija acordada con la persona'), findsOneWidget);
        expect(_campo, findsNothing);
        expect(find.text('DÍA Y HORA'), findsNothing);
        expect(_prendido(tester), isFalse);
        // La franja de la sugerencia viene elegida, como el chip del canvas.
        final chip = find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.primeraTarde));
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        // Se pidió con la casa, el colportor, la distancia del canvas y desde ahora.
        expect(lectura.pedidas, hasLength(1));
        expect(lectura.pedidas.single.espacioId, 'esp-1');
        expect(lectura.pedidas.single.colportorId, 'col-1');
        expect(lectura.pedidas.single.radio, 300);
        expect(lectura.pedidas.single.desde, DateTime(2026, 10, 23, 14, 35));
      },
    );

    testWidgets(
      'dada la sugerencia, cuando se guarda, entonces la agenda queda ese día con la franja y sin estricta',
      (tester) async {
        final a = await _montar(tester);
        await _tocar(tester, _boton);
        final agenda = a.repo.recibidas.single.agenda;
        expect(agenda.fechaProgramada, DateTime(2026, 10, 26, 16, 30).toUtc());
        expect(agenda.slotCodigo, 'early_afternoon');
        expect(agenda.esEstricta, isFalse);
        expect(a.resultados, [true]);
      },
    );

    testWidgets('dada 1 sola entrevista cerca, cuando se abre, entonces lo dice en singular', (
      tester,
    ) async {
      await _montar(tester, cercanas: [EntrevistaCercana(fecha: DateTime(2026, 10, 27, 10, 30))]);
      expect(find.text('1 entrevista a menos de 300 m ese día'), findsOneWidget);
      expect(find.text('Martes 27/10 · 10:00 a 11:30'), findsOneWidget);
    });

    testWidgets(
      'dado que ninguna está cerca, cuando se abre, entonces no se sugiere nada y queda el campo DÍA Y HORA',
      (tester) async {
        await _montar(tester, cercanas: const []);
        expect(_tarjeta, findsNothing);
        expect(find.text('SUGERIDA'), findsNothing);
        expect(find.text('DÍA Y HORA'), findsOneWidget);
        expect(find.text('Mañana · 10:00'), findsOneWidget);
        expect(_interruptor, findsOneWidget);
      },
    );

    testWidgets(
      'dado que ya pasaron todas, cuando se abre, entonces no se sugiere una fecha vencida',
      (tester) async {
        await _montar(tester, cercanas: [EntrevistaCercana(fecha: DateTime(2026, 10, 23, 14, 0))]);
        expect(_tarjeta, findsNothing);
        expect(find.text('Mañana · 10:00'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una falla al leer, cuando se abre, entonces el formulario sigue igual, sin aviso, y se puede agendar',
      (tester) async {
        final a = await _montar(
          tester,
          lectura: EntrevistasCercanasFalsas(const [], falla: StateError('sin base')),
        );
        expect(_tarjeta, findsNothing);
        expect(find.text('Mañana · 10:00'), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsNothing);
        await _tocar(tester, _boton);
        expect(a.repo.recibidas.single.agenda.slotCodigo, 'mid_morning');
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'dada una lectura lenta, cuando todavía no llegó, entonces el formulario se puede usar y al llegar se sugiere',
      (tester) async {
        final compuerta = Completer<void>();
        await _montar(
          tester,
          lectura: EntrevistasCercanasFalsas(_dosEnLaTarde, compuerta: compuerta),
        );
        expect(_tarjeta, findsNothing);
        expect(find.text('Mañana · 10:00'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(of: _boton, matching: find.byType(FilledButton)),
              )
              .onPressed,
          isNotNull,
        );
        compuerta.complete();
        await asentarAgendar(tester);
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(find.text('Lunes 26/10 · 16:30 a 18:00'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una lectura lenta, cuando la persona ya eligió otra franja, entonces la sugerencia no le pisa lo elegido',
      (tester) async {
        final compuerta = Completer<void>();
        await _montar(
          tester,
          lectura: EntrevistasCercanasFalsas(_dosEnLaTarde, compuerta: compuerta),
        );
        await _tocar(tester, find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.finDeManiana)));
        compuerta.complete();
        await asentarAgendar(tester);
        expect(_tarjeta, findsNothing);
        expect(find.text('Mañana · 10:00'), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.finDeManiana)),
              )
              .selected,
          isTrue,
        );
      },
    );

    testWidgets(
      'dada la sugerencia, cuando se toca Cambiar y se elige otra hora, entonces vuelve el campo DÍA Y HORA',
      (tester) async {
        await _montar(tester);
        await _tocar(tester, _tarjeta);
        expect(find.byKey(ClavesAgendarVisita.hojaHora), findsOneWidget);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.hojaMas));
        await _tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
        expect(_tarjeta, findsNothing);
        expect(find.text('DÍA Y HORA'), findsOneWidget);
        expect(find.text('Lunes 26/10 · 16:35'), findsOneWidget);
      },
    );

    testWidgets(
      'dada la sugerencia, cuando se elige otra franja a mano, entonces ya no se llama sugerida',
      (tester) async {
        await _montar(tester);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.mediaTarde)));
        expect(_tarjeta, findsNothing);
        expect(find.text('DÍA Y HORA'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una cobranza, cuando se abre, entonces no hay tarjeta ni interruptor, y al pasar a Entrevista se sugiere',
      (tester) async {
        await montarAgendar(
          tester,
          tipo: TipoAgenda.cobranza,
          cercanas: EntrevistasCercanasFalsas(_dosEnLaTarde),
        );
        expect(_tarjeta, findsNothing);
        expect(_interruptor, findsNothing);
        expect(find.text('DÍA Y HORA'), findsOneWidget);
        await _tocar(tester, find.text('Entrevista'));
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(_interruptor, findsOneWidget);
      },
    );
  });

  group('R·03 · entrevista estricta', () {
    testWidgets(
      'dado el formulario, cuando se prende el interruptor, entonces dibuja FECHA y HORA ACORDADA y saca las franjas',
      (tester) async {
        await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        expect(_prendido(tester), isTrue);
        expect(find.text('FECHA'), findsOneWidget);
        expect(find.text('Sábado 24/10'), findsOneWidget);
        expect(find.text('Cambiar'), findsOneWidget);
        expect(find.text('HORA ACORDADA'), findsOneWidget);
        expect(find.text('10:00'), findsOneWidget);
        expect(find.text('FRANJA SUGERIDA'), findsNothing);
        expect(find.text('DÍA Y HORA'), findsNothing);
        for (final f in FranjaHoraria.values) {
          expect(find.byKey(ClavesAgendarVisita.franja(f)), findsNothing);
        }
      },
    );

    testWidgets(
      'dada la entrevista estricta, cuando se guarda, entonces se guarda es_estricta con la hora exacta y sin franja',
      (tester) async {
        final a = await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        await _tocar(tester, _boton);
        final agenda = a.repo.recibidas.single.agenda;
        expect(agenda.esEstricta, isTrue);
        expect(agenda.slotCodigo, isNull);
        expect(agenda.fechaProgramada, DateTime(2026, 10, 24, 10).toUtc());
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'dada la sugerencia, cuando se prende y se apaga el interruptor, entonces vuelve la tarjeta SUGERIDA con su franja',
      (tester) async {
        await _montar(tester);
        await _tocar(tester, _interruptor);
        expect(find.text('FECHA'), findsOneWidget);
        expect(find.text('Lunes 26/10'), findsOneWidget);
        expect(find.text('16:30'), findsOneWidget);
        expect(find.text('2 entrevistas a menos de 300 m ese día'), findsNothing);
        await _tocar(tester, _interruptor);
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(find.text('Lunes 26/10 · 16:30 a 18:00'), findsOneWidget);
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
      'dada la entrevista estricta, cuando se escribe la hora acordada, entonces se guarda esa hora',
      (tester) async {
        final a = await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        await _tocar(tester, _horaAcordada);
        await tester.tap(find.byIcon(Icons.keyboard_outlined));
        await tester.pump();
        final campos = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
        await tester.enterText(campos.at(0), '9');
        await tester.enterText(campos.at(1), '45');
        await tester.tap(find.text('OK'));
        await asentarAgendar(tester);
        expect(find.text('09:45'), findsOneWidget);
        await _tocar(tester, _boton);
        final agenda = a.repo.recibidas.single.agenda;
        expect(agenda.fechaProgramada, DateTime(2026, 10, 24, 9, 45).toUtc());
        expect(agenda.esEstricta, isTrue);
        expect(agenda.slotCodigo, isNull);
      },
    );

    testWidgets(
      'dada la entrevista estricta, cuando se cierra el selector sin elegir, entonces la hora no cambia',
      (tester) async {
        await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        await _tocar(tester, _horaAcordada);
        await tester.tap(find.text('Cancel'));
        await asentarAgendar(tester);
        expect(find.text('10:00'), findsOneWidget);
      },
    );

    testWidgets(
      'dada la entrevista estricta, cuando se toca Cambiar, entonces la hoja pide solo el día',
      (tester) async {
        await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        await _tocar(tester, _tarjeta);
        expect(find.text('Día'), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.hojaHora), findsNothing);
        expect(find.byKey(ClavesAgendarVisita.hojaMas), findsNothing);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(2)));
        await _tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
        expect(find.text('Domingo 25/10'), findsOneWidget);
        // La hora no se tocó.
        expect(find.text('10:00'), findsOneWidget);
      },
    );

    testWidgets(
      'dada una hora acordada que ya pasó, cuando se elige hoy, entonces el aviso va bajo HORA ACORDADA y se confirma al guardar',
      (tester) async {
        final a = await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        await _tocar(tester, _tarjeta);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.dia(0)));
        await _tocar(tester, find.byKey(ClavesAgendarVisita.hojaListo));
        expect(find.byKey(ClavesAgendarVisita.errorHoraAcordada), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.errorHora), findsNothing);
        await _tocar(tester, _boton);
        expect(a.repo.recibidas, isEmpty);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual));
        expect(a.repo.recibidas.single.agenda.esEstricta, isTrue);
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'dada la estricta prendida, cuando se pasa a Cobranza y se vuelve, entonces la cobranza no es estricta y la estricta se conserva',
      (tester) async {
        final a = await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        await _tocar(tester, find.text('Cobranza'));
        expect(_interruptor, findsNothing);
        expect(_horaAcordada, findsNothing);
        expect(find.text('DÍA Y HORA'), findsOneWidget);
        expect(find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.mediaManiana)), findsOneWidget);
        await _tocar(tester, find.text('Entrevista'));
        expect(_prendido(tester), isTrue);
        expect(_horaAcordada, findsOneWidget);
        // Y una cobranza guardada con la estricta prendida debajo no la lleva.
        await _tocar(tester, find.text('Cobranza'));
        await _tocar(tester, _boton);
        final agenda = a.repo.recibidas.single.agenda;
        expect(agenda.esEstricta, isFalse);
        expect(agenda.slotCodigo, 'mid_morning');
      },
    );
  });

  group('casos límite de los dos artboards', () {
    testWidgets(
      'dado un doble toque en Agendar con la estricta, cuando se tocan dos veces seguidas, entonces se guarda una sola vez',
      (tester) async {
        final a = await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        await tester.ensureVisible(_boton);
        await tester.pump();
        await tester.tap(_boton);
        await tester.tap(_boton, warnIfMissed: false);
        await asentarAgendar(tester);
        expect(a.repo.recibidas, hasLength(1));
        expect(a.repo.cuantasQuedaron, 1);
        expect(a.repo.recibidas.single.agenda.esEstricta, isTrue);
      },
    );

    testWidgets(
      'dada una falla al guardar, cuando se toca Reintentar, entonces conserva la estricta y la hora, y guarda con los mismos ids',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
        final a = await _montar(tester, cercanas: const [], repo: repo);
        await _tocar(tester, _interruptor);
        await _tocar(tester, _boton);
        expect(find.byKey(ClavesAgendarVisita.avisoFalla), findsOneWidget);
        expect(find.descendant(of: _boton, matching: find.text('Reintentar')), findsOneWidget);
        // El botón volvió a habilitarse y los controles siguen como estaban.
        expect(_prendido(tester), isTrue);
        expect(tester.widget<SwitchListTile>(_interruptor).onChanged, isNotNull);
        expect(find.text('10:00'), findsOneWidget);
        await _tocar(tester, _boton);
        expect(a.repo.recibidas, hasLength(2));
        expect(a.repo.recibidas[0].agenda.id, a.repo.recibidas[1].agenda.id);
        expect(a.repo.recibidas[1].agenda.esEstricta, isTrue);
        expect(a.repo.cuantasQuedaron, 1);
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando se intenta tocar el interruptor y la hora, entonces no responden',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        final a = await _montar(tester, cercanas: const [], repo: repo);
        await _tocar(tester, _interruptor);
        await tester.ensureVisible(_boton);
        await tester.pump();
        await tester.tap(_boton);
        await tester.pump();
        expect(tester.widget<SwitchListTile>(_interruptor).onChanged, isNull);
        await tester.tap(_horaAcordada, warnIfMissed: false);
        await asentarAgendar(tester, 3);
        expect(find.text('OK'), findsNothing);
        repo.compuerta!.complete();
        await asentarAgendar(tester);
        expect(a.resultados, [true]);
        expect(a.repo.recibidas.single.agenda.esEstricta, isTrue);
      },
    );

    testWidgets(
      'dados tres toques seguidos al interruptor, cuando terminan, entonces queda prendido y con un solo campo de hora',
      (tester) async {
        await _montar(tester, cercanas: const []);
        await tester.ensureVisible(_interruptor);
        await tester.pump();
        for (var i = 0; i < 3; i++) {
          await tester.tap(_interruptor);
          await tester.pump();
        }
        await asentarAgendar(tester);
        expect(_prendido(tester), isTrue);
        expect(_horaAcordada, findsOneWidget);
        expect(find.text('HORA ACORDADA'), findsOneWidget);
      },
    );

    testWidgets(
      'dado volver atrás y reentrar, cuando se abre de nuevo, entonces arranca con la sugerencia y sin estricta',
      (tester) async {
        final lectura = EntrevistasCercanasFalsas(_dosEnLaTarde);
        final a = await _montar(tester, lectura: lectura);
        await _tocar(tester, _interruptor);
        await _tocar(tester, find.byKey(ClavesAgendarVisita.cerrar));
        expect(find.text('abrir agenda'), findsOneWidget);
        await abrirAgendar(tester);
        expect(_prendido(tester), isFalse);
        expect(find.text('SUGERIDA'), findsOneWidget);
        expect(lectura.pedidas, hasLength(2));
        expect(a.repo.recibidas, isEmpty);
      },
    );

    testWidgets(
      'dadas muchas entrevistas en muchos días, cuando se abre, entonces sugiere el día con más y desempata por el más próximo',
      (tester) async {
        final muchas = [
          for (var dia = 0; dia < 60; dia++)
            for (var n = 0; n < (dia == 40 || dia == 20 ? 5 : 1); n++)
              EntrevistaCercana(fecha: DateTime(2026, 10, 24 + dia, 9 + n)),
        ];
        await _montar(tester, cercanas: muchas);
        // El día 20 (13/11) y el 40 (3/12) empatan con 5: gana el más próximo.
        expect(find.text('5 entrevistas a menos de 300 m ese día'), findsOneWidget);
        expect(find.textContaining('Viernes 13/11'), findsOneWidget);
      },
    );

    testWidgets(
      'dado el texto al 200 % en un teléfono chico, cuando se ve la sugerencia y la estricta, entonces no desborda y se llega a Agendar',
      (tester) async {
        await _montar(tester, escala: 2, tamano: const Size(320, 568));
        expect(tester.takeException(), isNull);
        expect(find.text('SUGERIDA'), findsOneWidget);
        await _tocar(tester, _interruptor);
        expect(tester.takeException(), isNull);
        expect(_horaAcordada, findsOneWidget);
        await tester.ensureVisible(_boton);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(_boton, findsOneWidget);
      },
    );
  });

  group('lector de pantalla y guías de accesibilidad', () {
    testWidgets(
      'dada la sugerencia, cuando se lee, entonces la tarjeta se anuncia completa y es tocable',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await _montar(tester);
        final datos = tester.getSemantics(_tarjeta).getSemanticsData();
        expect(
          datos.label,
          'Fecha sugerida: Lunes 26/10 · 16:30 a 18:00. 2 entrevistas a menos de 300 m ese día. Tocá para cambiar',
        );
        expect(datos.hasAction(SemanticsAction.tap), isTrue);
        semantica.dispose();
      },
    );

    testWidgets(
      'dada la estricta, cuando se lee, entonces el campo de la hora acordada tiene nombre y acción',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await _montar(tester, cercanas: const []);
        await _tocar(tester, _interruptor);
        final datos = tester.getSemantics(_horaAcordada).getSemanticsData();
        expect(datos.label, 'Hora acordada: 10:00. Tocá para cambiar');
        expect(datos.hasAction(SemanticsAction.tap), isTrue);
        semantica.dispose();
      },
    );

    for (final prendida in [false, true]) {
      testWidgets(
        'dado el formulario ${prendida ? 'con' : 'sin'} la estricta, cuando se miran los toques, entonces cumplen tamaño y nombre',
        (tester) async {
          final semantica = tester.ensureSemantics();
          await _montar(tester);
          if (prendida) await _tocar(tester, _interruptor);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        },
      );
    }
  });
}
