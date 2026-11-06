// «PRÓXIMA VISITA» de la ficha de la persona (vista 23, 23A·05, y vista 32B, #405): la visita agendada
// que viene, «+ Agendar» desde la ficha y la vuelta a la ficha con la tarjeta. Con los casos límite de
// cada flujo: doble toque, falla a mitad de la acción, dos acciones seguidas, volver atrás y reentrar, y
// datos límite (vacío, visitas pasadas, textos largos, textScaler 2.0).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/agendar_visita_arnes.dart' show AgendaRepositorioQueAgenda;
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import 'ficha_persona_arnes.dart';

final _tarjeta = find.byKey(ClavesFicha.tarjetaProximaVisita);
final _agendar = find.byKey(ClavesFicha.botonAgendar);

/// La visita del canvas 23A·05: una entrevista a las 14:30 de la «Primera tarde». Hoy en la ficha es
/// el 22/10 a las 15:00, así que el 24/10 es dentro de dos días.
ItemAgenda _entrevista({
  String id = 'a1',
  DateTime? cuando,
  String? slot = 'early_afternoon',
  TipoAgenda tipo = TipoAgenda.entrevista,
  DireccionDeAgenda? alternativa,
}) => itemAgenda(
  id,
  cuando ?? DateTime(2026, 10, 24, 14, 30),
  tipo: tipo,
  slotCodigo: slot,
  espacioPersonaId: 'ep-per-1',
  nombre: 'María',
  apellido: 'Pérez',
  alternativa: alternativa,
);

MundoFicha _mundo({List<ItemAgenda> visitas = const [], bool conHistorial = true}) {
  final mundo = MundoFicha(historial: conHistorial ? historialDelCanvas() : const []);
  mundo.agendas.items = visitas;
  mundo.personas.sembrar([clienteDePersonas('per-1', 'María', apellido: 'Pérez')]);
  return mundo;
}

void main() {
  group('23A·05 · PRÓXIMA VISITA', () {
    testWidgets(
      'dada una entrevista agendada, entonces la tarjeta dice cuándo, la franja y el aviso',
      (tester) async {
        final mundo = _mundo(visitas: [_entrevista()]);
        await montarFicha(tester, mundo);

        expect(find.text('PRÓXIMA VISITA'), findsOneWidget);
        expect(find.text('Entrevista · sáb 24/10 · 14:30'), findsOneWidget);
        expect(find.text('Primera tarde · te avisamos a las 14:00'), findsOneWidget);
        expect(mundo.agendas.pedidosDeLaPersona, [(colportorId: 'col-1', personaId: 'per-1')]);
        // Y la sección de las notas y el historial siguen donde estaban.
        expect(find.byKey(ClavesFicha.notas), findsOneWidget);
        expect(find.byKey(ClavesFicha.historial), findsOneWidget);
      },
    );

    testWidgets('dado el orden de la ficha, entonces la visita va entre la cuenta y las notas', (
      tester,
    ) async {
      final mundo = _mundo(visitas: [_entrevista()]);
      await montarFicha(tester, mundo);

      // Sin ventas la cuenta es «Sin movimientos aún», en el lugar de la tarjeta.
      final yCuenta = tester.getTopLeft(find.byKey(ClavesFicha.sinMovimientos)).dy;
      final yVisita = tester.getTopLeft(find.byKey(ClavesFicha.proximaVisita)).dy;
      final yNotas = tester.getTopLeft(find.byKey(ClavesFicha.notas)).dy;
      expect(yCuenta, lessThan(yVisita));
      expect(yVisita, lessThan(yNotas));
    });

    testWidgets(
      'dada una cobranza en otra dirección, entonces dice dónde y no inventa una franja',
      (tester) async {
        final mundo = _mundo(
          visitas: [
            _entrevista(
              tipo: TipoAgenda.cobranza,
              slot: null,
              alternativa: const DireccionDeAgenda(
                ubicacionId: 'ub-9',
                tipo: TipoUbicacion.casa,
                calle: 'Av. Italia',
                numero: '2810',
              ),
            ),
          ],
        );
        await montarFicha(tester, mundo);

        expect(find.text('Cobranza · sáb 24/10 · 14:30'), findsOneWidget);
        expect(find.text('en Av. Italia 2810 · te avisamos a las 14:00'), findsOneWidget);
      },
    );

    testWidgets('dadas varias visitas, entonces muestra la más próxima que no pasó', (
      tester,
    ) async {
      final mundo = _mundo(
        visitas: [
          _entrevista(id: 'tarde', cuando: DateTime(2026, 10, 30, 11)),
          _entrevista(id: 'ayer', cuando: DateTime(2026, 10, 21, 10)),
          _entrevista(id: 'proxima', cuando: DateTime(2026, 10, 25, 9)),
        ],
      );
      await montarFicha(tester, mundo);

      expect(find.text('Entrevista · dom 25/10 · 09:00'), findsOneWidget);
      expect(find.textContaining('30/10'), findsNothing);
      expect(find.textContaining('21/10'), findsNothing);
    });

    testWidgets(
      'dada una visita que ya pasó de hora, entonces la muestra y pide registrar qué pasó',
      (tester) async {
        final mundo = _mundo(visitas: [_entrevista(cuando: DateTime(2026, 10, 21, 10))]);
        await montarFicha(tester, mundo);

        expect(find.text('Entrevista · mié 21/10 · 10:00'), findsOneWidget);
        expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
        // Ya no tiene sentido decir cuándo avisa.
        expect(find.textContaining('te avisamos'), findsNothing);
      },
    );

    testWidgets('dada una visita sin franja, entonces el aviso va solo', (tester) async {
      final mundo = _mundo(visitas: [_entrevista(slot: null)]);
      await montarFicha(tester, mundo);

      expect(find.text('te avisamos a las 14:00'), findsOneWidget);
    });

    testWidgets('dada una franja que la app no conoce, entonces no la muestra', (tester) async {
      final mundo = _mundo(visitas: [_entrevista(slot: 'madrugada')]);
      await montarFicha(tester, mundo);

      expect(find.text('te avisamos a las 14:00'), findsOneWidget);
      expect(find.textContaining('madrugada'), findsNothing);
    });

    testWidgets('dada otra anticipación, entonces el aviso se calcula con ella', (tester) async {
      final mundo = _mundo(visitas: [_entrevista()])
        ..preferencias = const PreferenciasRecordatorios(activados: true, anticipacionMinutos: 60);
      await montarFicha(tester, mundo);

      expect(find.text('Primera tarde · te avisamos a las 13:30'), findsOneWidget);
    });

    testWidgets('dado un aviso que cae el día anterior, entonces dice el día', (tester) async {
      final mundo = _mundo(visitas: [_entrevista(cuando: DateTime(2026, 10, 24, 0, 10))]);
      await montarFicha(tester, mundo);

      expect(find.text('Primera tarde · te avisamos el vie 23/10 a las 23:40'), findsOneWidget);
    });

    testWidgets('dados los recordatorios apagados, entonces lo dice en vez de prometer un aviso', (
      tester,
    ) async {
      final mundo = _mundo(visitas: [_entrevista()])
        ..preferencias = const PreferenciasRecordatorios(activados: false, anticipacionMinutos: 30);
      await montarFicha(tester, mundo);

      expect(find.text('Primera tarde · recordatorios apagados'), findsOneWidget);
      expect(find.textContaining('te avisamos'), findsNothing);
    });

    testWidgets('dado un aviso que ya pasó, entonces la tarjeta no lo menciona', (tester) async {
      // Son las 15:00 y la visita es a las 15:10: el aviso de las 14:40 ya pasó.
      final mundo = _mundo(visitas: [_entrevista(cuando: DateTime(2026, 10, 22, 15, 10))]);
      await montarFicha(tester, mundo);

      expect(find.text('Entrevista · jue 22/10 · 15:10'), findsOneWidget);
      expect(find.text('Primera tarde'), findsOneWidget);
      expect(find.textContaining('te avisamos'), findsNothing);
    });

    testWidgets('dada una visita de otra persona, entonces no aparece', (tester) async {
      final mundo = _mundo(
        visitas: [itemAgenda('otra', DateTime(2026, 10, 24, 14, 30), espacioPersonaId: 'ep-otra')],
      );
      await montarFicha(tester, mundo);

      expect(_tarjeta, findsNothing);
      expect(find.text('Todavía no hay una visita agendada.'), findsOneWidget);
    });

    testWidgets(
      'dado que se agenda o se cancela con la ficha abierta, entonces se actualiza sola',
      (tester) async {
        final mundo = _mundo();
        await montarFicha(tester, mundo);
        expect(_tarjeta, findsNothing);

        mundo.agendas.emitir([_entrevista()]);
        await asentar(tester);
        expect(_tarjeta, findsOneWidget);
        expect(find.text('Todavía no hay una visita agendada.'), findsNothing);

        mundo.agendas.emitir(const []);
        await asentar(tester);
        expect(_tarjeta, findsNothing);
        expect(find.text('Todavía no hay una visita agendada.'), findsOneWidget);
      },
    );
  });

  group('Sin visita, ficha vacía y solo lectura', () {
    testWidgets('dada una persona con historial y sin visita, entonces ofrece «+ Agendar»', (
      tester,
    ) async {
      final mundo = _mundo();
      await montarFicha(tester, mundo);

      expect(find.text('PRÓXIMA VISITA'), findsOneWidget);
      expect(find.text('Todavía no hay una visita agendada.'), findsOneWidget);
      expect(find.descendant(of: _agendar, matching: find.text('+ Agendar')), findsOneWidget);
    });

    testWidgets('dada la ficha vacía (32B·05), entonces no ofrece agendar ni dibuja la sección', (
      tester,
    ) async {
      final mundo = _mundo(conHistorial: false);
      await montarFicha(tester, mundo);

      expect(find.byKey(ClavesFicha.hero), findsOneWidget);
      expect(find.byKey(ClavesFicha.proximaVisita), findsNothing);
      expect(_agendar, findsNothing);
    });

    testWidgets(
      'dada la ficha vacía con una visita ya agendada, entonces la muestra sin «+ Agendar»',
      (tester) async {
        final mundo = _mundo(visitas: [_entrevista()], conHistorial: false);
        await montarFicha(tester, mundo);

        expect(_tarjeta, findsOneWidget);
        expect(find.text('Entrevista · sáb 24/10 · 14:30'), findsOneWidget);
      },
    );

    testWidgets('dada la persona de baja (32B·04), entonces ve su visita pero no puede agendar', (
      tester,
    ) async {
      final mundo = MundoFicha(
        persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
        historial: historialDelCanvas(),
        contexto: contextoBajaDesde22(),
      );
      mundo.agendas.items = [_entrevista()];
      await montarFicha(tester, mundo);

      expect(_tarjeta, findsOneWidget);
      expect(_agendar, findsNothing);
    });

    testWidgets('dada la persona de baja y sin visita, entonces no dibuja la sección', (
      tester,
    ) async {
      final mundo = MundoFicha(
        persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
        historial: historialDelCanvas(),
        contexto: contextoBajaDesde22(),
      );
      await montarFicha(tester, mundo);

      expect(find.byKey(ClavesFicha.proximaVisita), findsNothing);
    });

    testWidgets('dado el depto de baja (32B·08), entonces no puede agendar', (tester) async {
      final mundo = MundoFicha(historial: historialDelCanvas(), contexto: contextoDeptoDeBaja);
      await montarFicha(tester, mundo);

      expect(_agendar, findsNothing);
      expect(find.byKey(ClavesFicha.proximaVisita), findsNothing);
    });
  });

  group('Leer la agenda', () {
    testWidgets('dada la agenda cargando, entonces la sección no ocupa lugar', (tester) async {
      final mundo = _mundo(visitas: [_entrevista()])..agendas.congelada = true;
      await montarFicha(tester, mundo);

      expect(find.byKey(ClavesFicha.proximaVisita), findsNothing);
      expect(find.byKey(ClavesFicha.notas), findsOneWidget);
    });

    testWidgets('dada una falla al leer la agenda, entonces la ficha sigue y dice qué hacer', (
      tester,
    ) async {
      final mundo = _mundo(visitas: [_entrevista()])..agendas.error = StateError('sin base');
      await montarFicha(tester, mundo);

      expect(find.byKey(ClavesFicha.errorProximaVisita), findsOneWidget);
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      // El resto de la ficha se ve igual.
      expect(find.byKey(ClavesFicha.historial), findsOneWidget);

      mundo.agendas.error = null;
      await tester.tap(find.text('Reintentar'));
      await asentar(tester);
      expect(find.byKey(ClavesFicha.errorProximaVisita), findsNothing);
      expect(_tarjeta, findsOneWidget);
    });

    testWidgets('dado un error que llega con datos ya leídos, entonces lo dice', (tester) async {
      final mundo = _mundo(visitas: [_entrevista()]);
      await montarFicha(tester, mundo);
      expect(_tarjeta, findsOneWidget);

      mundo.agendas.emitirError(StateError('se cayó'));
      await asentar(tester);

      expect(find.byKey(ClavesFicha.errorProximaVisita), findsOneWidget);
    });
  });

  group('Tocar la tarjeta', () {
    testWidgets('dado el destino, cuando se toca, entonces abre el detalle de esa agenda', (
      tester,
    ) async {
      final mundo = _mundo(visitas: [_entrevista()])..conDetalleDeAgenda = true;
      await montarFicha(tester, mundo);

      await tester.tap(_tarjeta);
      await asentar(tester);

      expect(mundo.detallesAbiertos, ['a1']);
      expect(find.text('›'), findsWidgets);
    });

    testWidgets('dado un doble toque, entonces abre una sola vez', (tester) async {
      final compuerta = Completer<void>();
      final mundo = _mundo(visitas: [_entrevista()])
        ..conDetalleDeAgenda = true
        ..compuertaDetalle = compuerta;
      await montarFicha(tester, mundo);

      await tester.tap(_tarjeta);
      await tester.tap(_tarjeta);
      await tester.pump();
      expect(mundo.detallesAbiertos, ['a1']);

      compuerta.complete();
      await asentar(tester);
      // Ya volvió: se puede abrir de nuevo.
      await tester.tap(_tarjeta);
      await asentar(tester);
      expect(mundo.detallesAbiertos, ['a1', 'a1']);
    });

    testWidgets('dada una falla al abrir, entonces avisa y la tarjeta vuelve a poder tocarse', (
      tester,
    ) async {
      final mundo = _mundo(visitas: [_entrevista()])
        ..conDetalleDeAgenda = true
        ..fallaDelDetalle = StateError('no abre');
      await montarFicha(tester, mundo);

      await tester.tap(_tarjeta);
      await asentar(tester);
      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOneWidget);

      mundo.fallaDelDetalle = null;
      await tester.tap(_tarjeta);
      await asentar(tester);
      expect(mundo.detallesAbiertos, ['a1', 'a1']);
    });

    testWidgets('dado que no hay destino, entonces la tarjeta no se toca y no lleva «›»', (
      tester,
    ) async {
      final mundo = _mundo(visitas: [_entrevista()]);
      await montarFicha(tester, mundo);

      expect(find.descendant(of: _tarjeta, matching: find.text('›')), findsNothing);
      final semantica = tester.getSemantics(_tarjeta);
      expect(semantica.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });

    testWidgets('dado el lector de pantalla, entonces la tarjeta se anuncia como botón con todo', (
      tester,
    ) async {
      final mundo = _mundo(visitas: [_entrevista()])..conDetalleDeAgenda = true;
      final semantica = tester.ensureSemantics();
      await montarFicha(tester, mundo, lector: true);

      final datos = tester.getSemantics(_tarjeta).getSemanticsData();
      expect(datos.hasAction(SemanticsAction.tap), isTrue);
      expect(datos.label, contains('Entrevista · sáb 24/10 · 14:30'));
      expect(datos.label, contains('Primera tarde · te avisamos a las 14:00'));
      semantica.dispose();
    });

    testWidgets('dado volver atrás y reentrar, entonces la tarjeta sigue ahí', (tester) async {
      final mundo = _mundo(visitas: [_entrevista()])..conDetalleDeAgenda = true;
      await montarFicha(tester, mundo);
      expect(_tarjeta, findsOneWidget);

      await volverAtras(tester);
      expect(_tarjeta, findsNothing);
      await tester.tap(find.text('abrir ficha'));
      await asentar(tester);

      expect(_tarjeta, findsOneWidget);
      expect(find.text('Entrevista · sáb 24/10 · 14:30'), findsOneWidget);
    });
  });

  group('Agendar desde la ficha', () {
    late AgendaRepositorioQueAgenda repo;
    late Telefono telefono;

    MundoFicha conAgendar({List<ItemAgenda> visitas = const []}) {
      repo = AgendaRepositorioQueAgenda();
      telefono = Telefono()..recordatorios.permisoConcedido = true;
      var n = 0;
      return _mundo(visitas: visitas)
        ..extra = [
          agendaRepositoryProvider.overrideWithValue(repo),
          generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
          relojVisitaProvider.overrideWithValue(() => ahoraFicha),
          ...telefono.overrides,
        ];
    }

    testWidgets('dado «+ Agendar», cuando se agenda, entonces vuelve a la ficha con la tarjeta', (
      tester,
    ) async {
      final mundo = conAgendar();
      await montarFicha(tester, mundo);

      await tester.tap(_agendar);
      await asentar(tester);
      // «Agendar visita» con la casa y la persona puestas.
      expect(find.text('Agendar visita'), findsOneWidget);
      expect(find.text('María Pérez'), findsWidgets);

      await tester.tap(find.text('Agendar'));
      await asentar(tester);

      final recibida = repo.recibidas.single.agenda;
      expect(recibida.espacioId, 'esp-1');
      expect(recibida.espacioPersonaId, 'ep-per-1');
      expect(recibida.tipo, TipoAgenda.entrevista);
      expect(recibida.colportorId, 'col-1');
      // De vuelta en la ficha, con el aviso de éxito de 23A·05.
      expect(find.text('Agendar visita'), findsNothing);
      expect(find.byKey(ClavesFicha.proximaVisita), findsOneWidget);
      expect(find.text('Agendada. La casa queda como «Entrevista agendada».'), findsOneWidget);

      // Y la tarjeta aparece cuando la agenda se lee de nuevo.
      mundo.agendas.emitir([
        _entrevista(id: recibida.id, cuando: DateTime(2026, 10, 23, 10), slot: 'mid_morning'),
      ]);
      await asentar(tester);
      expect(find.text('PRÓXIMA VISITA'), findsOneWidget);
      expect(find.text('Entrevista · vie 23/10 · 10:00'), findsOneWidget);
      expect(find.text('Media mañana · te avisamos a las 09:30'), findsOneWidget);
    });

    testWidgets('dado cerrar «Agendar visita» sin guardar, entonces la ficha queda igual', (
      tester,
    ) async {
      final mundo = conAgendar();
      await montarFicha(tester, mundo);

      await tester.tap(_agendar);
      await asentar(tester);
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);

      expect(repo.recibidas, isEmpty);
      expect(find.text('Agendar visita'), findsNothing);
      expect(find.byKey(ClavesFicha.proximaVisita), findsOneWidget);
      expect(find.text('Agendada. La casa queda como «Entrevista agendada».'), findsNothing);
      // «+ Agendar» sigue tocable.
      await tester.tap(_agendar);
      await asentar(tester);
      expect(find.text('Agendar visita'), findsOneWidget);
    });

    testWidgets('dado un doble toque en «+ Agendar», entonces abre una sola pantalla', (
      tester,
    ) async {
      final mundo = conAgendar();
      await montarFicha(tester, mundo);

      await tester.tap(_agendar);
      await tester.tap(_agendar, warnIfMissed: false);
      await asentar(tester);

      expect(find.text('Agendar visita'), findsOneWidget);
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      // Una sola pantalla encima: al cerrarla estamos en la ficha, no en otra «Agendar visita».
      expect(find.text('Agendar visita'), findsNothing);
      expect(find.byKey(ClavesFicha.proximaVisita), findsOneWidget);
    });

    testWidgets(
      'dada una falla al guardar, entonces el formulario sigue con «Reintentar» y la ficha no cambia',
      (tester) async {
        final mundo = conAgendar();
        await montarFicha(tester, mundo);
        repo.fallas.add(const FailureInesperado());

        await tester.tap(_agendar);
        await asentar(tester);
        await tester.tap(find.text('Agendar'));
        await asentar(tester);

        expect(find.text('Agendar visita'), findsOneWidget);
        expect(find.text('Reintentar'), findsWidgets);

        // El segundo intento guarda: una sola agenda, no dos.
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(find.text('Agendar visita'), findsNothing);
        expect(repo.cuantasQuedaron, 1);
      },
    );

    testWidgets(
      'dada una persona que ya no está en ese depto, entonces avisa y se puede volver a intentar',
      (tester) async {
        final mundo = conAgendar();
        // Sin el vínculo de la persona con el depto no hay de qué colgar la agenda.
        final sinVinculo = MundoFicha(historial: historialDelCanvas())
          ..extra = mundo.extra
          ..agendas.items = const [];
        await montarFicha(tester, sinVinculo);

        await tester.tap(_agendar);
        await asentar(tester);

        expect(find.text('No pudimos abrir esa pantalla. Probá de nuevo.'), findsOneWidget);
        expect(find.text('Agendar visita'), findsNothing);
        expect(repo.recibidas, isEmpty);

        sinVinculo.personas.sembrar([clienteDePersonas('per-1', 'María', apellido: 'Pérez')]);
        await tester.tap(_agendar);
        await asentar(tester);
        expect(find.text('Agendar visita'), findsOneWidget);
      },
    );

    testWidgets('dadas dos acciones seguidas (agendar y abrir el detalle), entonces no se pisan', (
      tester,
    ) async {
      final mundo = conAgendar(visitas: [_entrevista()])..conDetalleDeAgenda = true;
      await montarFicha(tester, mundo);

      await tester.tap(_agendar);
      await asentar(tester);
      await tester.tap(find.byTooltip('Cerrar'));
      await asentar(tester);
      await tester.tap(_tarjeta);
      await asentar(tester);

      expect(mundo.detallesAbiertos, ['a1']);
      expect(find.text('Agendar visita'), findsNothing);
    });
  });

  group('Datos límite', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('dado un depto con calle larguísima y textScaler $escala, entonces no desborda', (
        tester,
      ) async {
        final larga = 'Avenida General Don José Gervasio Artigas y Rivera ' * 3;
        final mundo = _mundo(
          visitas: [
            _entrevista(
              tipo: TipoAgenda.cobranza,
              alternativa: DireccionDeAgenda(
                ubicacionId: 'ub-9',
                tipo: TipoUbicacion.casa,
                calle: larga,
                numero: '2810',
              ),
            ),
          ],
        )..conDetalleDeAgenda = true;
        await montarFicha(tester, mundo, escala: escala, tamano: const Size(320, 568));

        await tester.scrollUntilVisible(_tarjeta, 120, scrollable: find.byType(Scrollable).first);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(_tarjeta, findsOneWidget);
        // El botón sigue por encima de los 48 px que pide AA.
        expect(tester.getSize(_tarjeta).height, greaterThanOrEqualTo(64));
      });

      testWidgets(
        'dada la sección vacía con textScaler $escala, entonces «+ Agendar» no desborda',
        (tester) async {
          final mundo = _mundo();
          await montarFicha(tester, mundo, escala: escala, tamano: const Size(320, 568));

          await tester.scrollUntilVisible(_agendar, 120, scrollable: find.byType(Scrollable).first);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(_agendar).height, greaterThanOrEqualTo(48));
        },
      );
    }

    testWidgets('dadas 200 visitas agendadas, entonces muestra solo la más próxima', (
      tester,
    ) async {
      final mundo = _mundo(
        visitas: [
          for (var i = 0; i < 200; i++)
            _entrevista(
              id: 'v$i',
              cuando: DateTime(2026, 11, 1).add(Duration(hours: i)),
            ),
          _entrevista(id: 'la-proxima', cuando: DateTime(2026, 10, 23, 9)),
        ],
      );
      await montarFicha(tester, mundo);

      expect(_tarjeta, findsOneWidget);
      expect(find.text('Entrevista · vie 23/10 · 09:00'), findsOneWidget);
    });
  });
}
