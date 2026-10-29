// QA de #570 («+ Agendar» de la hoja de la casa abre «Agendar visita» con la casa puesta, 23B·10 →
// 23A, HU-VIS-002). El implementador probó el botón contra un destino falso; acá el destino es el de
// verdad (`FlujoAgendarVisita.abrir`, como lo engancha `main.dart`) y la pantalla «Agendar visita» es
// la real, con la casa y la agenda en memoria: se ve qué casa lleva, qué se guarda, cómo se vuelve y
// qué pasa con los casos límite (doble toque, volver sin guardar, reentrada, edificio sin depto).
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_agendar_visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agendar_visita_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart'
    show ClavesHojaCasa;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/persona_falsos.dart';

/// `--dart-define=QA_HALLAZGOS=true` corre los tests de los hallazgos (salen del skip al arreglarlos).
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

final _agendar = find.byKey(ClavesHojaCasa.agendar);
final _registrar = find.byKey(ClavesHojaCasa.registrarVisita);
final _formulario = find.byType(AgendarVisitaPage);
final _avisoEdificio = find.text(TextosRegistrarVisita.edificioSinDepto);
final _guardar = find.byKey(ClavesAgendarVisita.botonAgendar);

final class _Montaje {
  _Montaje(this.repo, this.telefono);
  final AgendaRepositorioQueAgenda repo;
  final Telefono telefono;
  final cierres = <int>[];
  final destinos = <ContextoDeCita>[];
}

/// La hoja de la casa con el destino de «+ Agendar» enganchado igual que en `main.dart`
/// (`programarEntrevistaDesdeLaCasaProvider` → `FlujoAgendarVisita.abrir` con la sesión), sobre una
/// `MaterialApp` con `navigatorKey` como la de la app.
Future<_Montaje> _montar(
  WidgetTester tester, {
  TipoUbicacion tipo = TipoUbicacion.casa,
  ContextoDeLaCasa? contexto,
  String? colportorSesion = 'col-1',
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final m = _Montaje(
    AgendaRepositorioQueAgenda(),
    Telefono(estado: EstadoSistemaNotificaciones.activadas)..recordatorios.permisoConcedido = true,
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final llave = GlobalKey<NavigatorState>();
  var n = 0;
  final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  final overrides = <Override>[
    ...overridesHojaCasa(
      lectura: contexto == null ? null : (_) => Stream.value(contexto),
      registrarVisita: (_) {},
    ),
    agendaRepositoryProvider.overrideWithValue(m.repo),
    generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
    relojVisitaProvider.overrideWithValue(ahoraDelCanvas),
    ...m.telefono.overrides,
    personaRepositoryProvider.overrideWithValue(personas),
    espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaMataojo())),
    programarEntrevistaDesdeLaCasaProvider.overrideWithValue((cita) {
      m.destinos.add(cita);
      final contexto = llave.currentContext;
      if (contexto == null) return false;
      return FlujoAgendarVisita.abrir(
        contexto,
        espacioId: cita.espacioId,
        espacioPersonaId: cita.espacioPersonaId,
        colportorId: colportorSesion,
      );
    }),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        navigatorKey: llave,
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: HojaCasa(
            item: itemDeLaHoja(calle: 'Mataojo', numero: '2044', tipo: tipo),
            ahora: ahoraDelCanvas(),
            alCerrar: () => m.cierres.add(1),
            colportorId: 'col-1',
          ),
        ),
      ),
    ),
  );
  await asentarAgendar(tester);
  return m;
}

Future<void> _tocarAgendar(WidgetTester tester) async {
  await tester.ensureVisible(_agendar);
  await tester.pump();
  await tester.tap(_agendar);
  await asentarAgendar(tester);
}

void main() {
  group('«+ Agendar» con el formulario real', () {
    testWidgets(
      'dado la hoja de una casa, cuando toco «+ Agendar», se abre «Agendar visita» con ESA casa',
      (tester) async {
        final m = await _montar(tester);

        await _tocarAgendar(tester);

        expect(_formulario, findsOneWidget);
        expect(find.text('Agendar visita'), findsOneWidget);
        expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
        expect(m.destinos.single.espacioId, 'esp-1');
        expect(m.destinos.single.ubicacionId, 'u-1');
      },
    );

    testWidgets('al guardar, la cita queda en la casa, vuelve a la hoja y avisa', (tester) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);

      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);

      final recibida = m.repo.recibidas.single;
      expect(recibida.agenda.espacioId, 'esp-1');
      expect(recibida.agenda.tipo, TipoAgenda.entrevista);
      expect(recibida.agenda.colportorId, 'col-1');
      expect(_formulario, findsNothing);
      // Al volver, la hoja sigue abierta (no se cerró) y el aviso de éxito se ve.
      expect(m.cierres, isEmpty);
      expect(_agendar, findsOneWidget);
      expect(find.text('Agendada. La casa queda como «Entrevista agendada».'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('volver sin guardar no agenda nada y el botón sirve otra vez (reentrada)', (
      tester,
    ) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);

      await tester.tap(find.byKey(ClavesAgendarVisita.cerrar));
      await asentarAgendar(tester);

      expect(_formulario, findsNothing);
      expect(m.repo.recibidas, isEmpty);
      expect(find.textContaining('Agendada'), findsNothing);

      await _tocarAgendar(tester);
      expect(_formulario, findsOneWidget);
      expect(m.destinos, hasLength(2));
    });

    testWidgets('un doble toque rápido abre UN formulario, no dos apilados', (tester) async {
      final m = await _montar(tester);
      await tester.ensureVisible(_agendar);
      await tester.pump();

      await tester.tap(_agendar);
      await tester.tap(_agendar, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(_formulario, findsOneWidget);
      expect(m.destinos, hasLength(1));
      await tester.tap(find.byKey(ClavesAgendarVisita.cerrar));
      await asentarAgendar(tester);
      // Si hubiera dos apilados, queda uno abierto tapando la hoja.
      expect(_formulario, findsNothing);
    });

    testWidgets('dos veces seguidas: agendar, volver y agendar otra vez no pisa la primera', (
      tester,
    ) async {
      final m = await _montar(tester);
      for (var i = 0; i < 2; i++) {
        await _tocarAgendar(tester);
        await tester.ensureVisible(_guardar);
        await tester.tap(_guardar);
        await asentarAgendar(tester);
      }
      expect(m.repo.cuantasQuedaron, 2);
      expect(_agendar, findsOneWidget);
    });
  });

  group('edificio', () {
    testWidgets('con el depto elegido, el formulario se abre con ese espacio', (tester) async {
      final m = await _montar(
        tester,
        tipo: TipoUbicacion.edificio,
        contexto: const ContextoDeLaCasa(espacioId: 'esp-3B', personas: []),
      );

      await _tocarAgendar(tester);

      expect(_formulario, findsOneWidget);
      expect(m.destinos.single.espacioId, 'esp-3B');
    });

    testWidgets('sin depto elegido no hay «+ Agendar» pero sí «Registrar visita»', (tester) async {
      await _montar(
        tester,
        tipo: TipoUbicacion.edificio,
        contexto: const ContextoDeLaCasa(personas: []),
      );

      expect(_agendar, findsNothing);
      expect(_registrar, findsOneWidget);
    });
  });

  // Decisiones de la revisión del 29/10 (#491 P1 y P2, mapa §2) que #570 todavía no aplica: los tests
  // están escritos con el comportamiento decidido y salen del `skip` cuando el implementador lo arregle.
  group('decisiones de la revisión sin aplicar', () {
    testWidgets(
      'edificio sin depto elegido: «+ Agendar» se ve y al tocarlo avisa, sin abrir el formulario',
      (tester) async {
        final m = await _montar(
          tester,
          tipo: TipoUbicacion.edificio,
          contexto: const ContextoDeLaCasa(personas: []),
        );

        expect(_agendar, findsOneWidget);
        await tester.tap(_agendar);
        await asentarAgendar(tester);

        expect(_avisoEdificio, findsOneWidget);
        expect(_formulario, findsNothing);
        expect(m.destinos, isEmpty);
      },
      skip:
          !_verHallazgos, // QA #570: edificio sin depto esconde «+ Agendar» sin decir nada (decidido: se ve y avisa)
    );

    testWidgets(
      'una sola persona activa: la cita se agenda CON ella (no «Sin persona»)',
      (tester) async {
        final m = await _montar(
          tester,
          contexto: ContextoDeLaCasa(espacioId: 'esp-1', personas: [mariaFernandez]),
        );

        await _tocarAgendar(tester);

        expect(m.destinos.single.espacioPersonaId, 'ep-p1');
        expect(find.text('Sin persona'), findsNothing);
      },
      skip:
          !_verHallazgos, // QA #570: la cita siempre queda «Sin persona» aunque la casa tenga una persona (decidido: va con ella)
    );

    testWidgets(
      'varias personas: pregunta con quién antes de abrir el formulario',
      (tester) async {
        final m = await _montar(
          tester,
          contexto: ContextoDeLaCasa(
            espacioId: 'esp-1',
            personas: [
              mariaFernandez,
              clienteDePersonas('p2', 'Pedro', apellido: 'Gómez'),
            ],
          ),
        );

        await tester.ensureVisible(_agendar);
        await tester.pump();
        await tester.tap(_agendar);
        await asentarAgendar(tester);

        expect(m.destinos, isEmpty);
        expect(find.textContaining('Pedro Gómez'), findsWidgets);
        expect(find.textContaining('María Fernández'), findsWidgets);
      },
      skip:
          !_verHallazgos, // QA #570: con varias personas no pregunta con quién (decidido: mismo selector de R·02)
    );

    testWidgets('sin personas: la cita queda «Sin persona» y el formulario lo dice', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        contexto: const ContextoDeLaCasa(espacioId: 'esp-1', personas: []),
      );

      await _tocarAgendar(tester);

      expect(m.destinos.single.espacioPersonaId, isNull);
      expect(find.text('Sin persona'), findsOneWidget);
    });
  });

  group('tamaños', () {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets(
          '${tamano.width.toInt()}×${tamano.height.toInt()} a $escala×: la hoja y el formulario sin overflow',
          (tester) async {
            await _montar(tester, tamano: tamano, escala: escala);
            expect(tester.takeException(), isNull);
            expect(_agendar, findsOneWidget);

            await _tocarAgendar(tester);

            expect(_formulario, findsOneWidget);
            expect(find.text('Mataojo 2044 · Depto 3B'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
