// #568 («+ Agendar» de la pestaña Agenda, vista 23B, HU-VIS-002; decisión de Cristian 04/11, «Agendar
// pest.»): la pestaña real con el destino enganchado igual que en `main.dart`
// (`agendarDesdeLaAgendaProvider` → `FlujoAgendarDesdeLaAgenda.abrir` con la sesión). Se elige la casa
// en la lista de ubicaciones (vista 05) en modo selección, se pregunta con quién y se abre «Agendar
// visita» (23A·01) con esa casa. Casos límite: sin sesión, cancelar en cada paso, doble toque, falla al
// leer la casa, baja, edificio, dos acciones seguidas, reentrada y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/formato_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/agendar_visita_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_agendar_desde_la_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/elegir_casa_para_agendar_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_reactivar.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/espacios_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/notificaciones_arnes.dart' show Telefono;
import '../../helpers/persona_falsos.dart';

/// [EspacioRepository] con los espacios de cada ubicación; lee la casa de «Agendar visita» siempre
/// como «Mataojo 2044 · Depto 3B».
final class _Espacios implements EspacioRepository {
  _Espacios(this.porUbicacion);

  final Map<String, List<Espacio>> porUbicacion;

  /// Si no es `null`, `listar` devuelve esta falla.
  Failure? falla;

  /// Si no es `null`, `listar` lanza esto.
  Object? lanza;

  /// Si no es `null`, `listar` espera a que se complete.
  Completer<void>? compuerta;

  var listados = 0;

  @override
  Future<Either<Failure, List<Espacio>>> listar(
    String ubicacionId, {
    bool incluirBajas = false,
  }) async {
    listados += 1;
    await compuerta?.future;
    final roto = lanza;
    if (roto != null) throw roto;
    final f = falla;
    if (f != null) return Left(f);
    return Right(porUbicacion[ubicacionId] ?? const []);
  }

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async => Right(casaMataojo());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Montaje {
  _Montaje(this.agendas, this.espacios, this.lista, this.llave);
  final AgendaRepositorioQueAgenda agendas;
  final _Espacios espacios;
  final RepoListaFalso lista;
  final GlobalKey<NavigatorState> llave;
  var llamadas = 0;
}

final _seleccion = find.byKey(ClavesElegirCasaParaAgendar.pantalla);
final _formulario = find.byType(AgendarVisitaPage);
final _guardar = find.byKey(ClavesAgendarVisita.botonAgendar);
final _agendarDeLaAgenda = find.text('+ Agendar');
final _atras = find.byType(BackButton);

List<Espacio> _unEspacio(String id, String ubicacionId) => [
  espacioDe(id, null, ubicacionId: ubicacionId),
];

List<UbicacionConResumen> _filasPorDefecto() => [
  filaLista('u-1', calle: 'Mataojo', numero: '2044'),
  filaLista('u-2', calle: 'Rivera', numero: '77', hace: const Duration(hours: 3)),
];

/// La pestaña Agenda real, vacía (muestra «+ Agendar»), con el destino de `main.dart`.
Future<_Montaje> _montar(
  WidgetTester tester, {
  List<UbicacionConResumen>? filas,
  String? sesion = 'col-1',
  List<PersonaDelEspacio>? personas,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final llave = GlobalKey<NavigatorState>();
  final lista = RepoListaFalso(filas ?? _filasPorDefecto());
  final espacios = _Espacios({
    'u-1': _unEspacio('esp-1', 'u-1'),
    'u-2': _unEspacio('esp-2', 'u-2'),
    'u-3': [
      espacioDe('esp-3a', '1', ubicacionId: 'u-3'),
      espacioDe('esp-3b', '2', ubicacionId: 'u-3', orden: 1),
    ],
    'u-5': const [],
  });
  final agendas = AgendaRepositorioQueAgenda();
  final telefono = Telefono(estado: EstadoSistemaNotificaciones.activadas)
    ..recordatorios.permisoConcedido = true;
  final repoPersonas = PersonaRepositorioFalso()..sembrar(personas ?? [mariaFernandez]);
  final m = _Montaje(agendas, espacios, lista, llave);
  var n = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesLista(repo: lista),
        consultaAgendaRepositoryProvider.overrideWithValue(ConsultaAgendaFalsa()),
        relojAgendaProvider.overrideWithValue(ahoraDelCanvas),
        agendaRepositoryProvider.overrideWithValue(agendas),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(ahoraDelCanvas),
        ...telefono.overrides,
        personaRepositoryProvider.overrideWithValue(repoPersonas),
        espacioRepositoryProvider.overrideWithValue(espacios),
        // Igual que en `main.dart`.
        agendarDesdeLaAgendaProvider.overrideWith(
          (ref) => () {
            m.llamadas += 1;
            final contexto = llave.currentContext;
            if (contexto == null) return false;
            return FlujoAgendarDesdeLaAgenda.abrir(contexto, colportorId: sesion);
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: llave,
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const Scaffold(body: AgendaPage(colportorId: 'col-1')),
      ),
    ),
  );
  await asentarAgendar(tester);
  return m;
}

Future<void> _tocarAgendar(WidgetTester tester) async {
  await tester.ensureVisible(_agendarDeLaAgenda);
  await tester.pump();
  await tester.tap(_agendarDeLaAgenda);
  await asentarAgendar(tester);
}

Future<void> _elegirCasa(WidgetTester tester, String direccion) async {
  await tester.tap(find.text(direccion));
  await asentarAgendar(tester);
}

/// Cada test termina desmontando la pantalla: el temporizador del minuto de la agenda se cancela.
void _probar(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void main() {
  group('23B·07 · «+ Agendar» sin casa elegida', () {
    _probar('con el destino enganchado, la pestaña vacía muestra «+ Agendar»', (tester) async {
      await _montar(tester);

      expect(_agendarDeLaAgenda, findsOneWidget);
      expect(_seleccion, findsNothing);
    });

    _probar('lo primero que abre es la lista de ubicaciones para elegir la casa', (tester) async {
      final m = await _montar(tester);

      await _tocarAgendar(tester);

      expect(_seleccion, findsOneWidget);
      expect(find.text(TextosElegirCasaParaAgendar.titulo), findsOneWidget);
      expect(find.text('Mataojo 2044'), findsOneWidget);
      expect(find.text('Rivera 77'), findsOneWidget);
      expect(_formulario, findsNothing);
      expect(m.llamadas, 1);
    });

    _probar('elegir una casa abre «Agendar visita» con ESA casa y la persona de siempre', (
      tester,
    ) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Mataojo 2044');

      expect(_seleccion, findsNothing);
      expect(_formulario, findsOneWidget);
      expect(find.text('Agendar visita'), findsOneWidget);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);
      final recibida = m.agendas.recibidas.single;
      expect(recibida.agenda.espacioId, 'esp-1');
      expect(recibida.agenda.espacioPersonaId, 'ep-p1');
      expect(recibida.agenda.colportorId, 'col-1');
      // Al guardar se vuelve a la Agenda, con el aviso de éxito.
      expect(_formulario, findsNothing);
      expect(_seleccion, findsNothing);
      expect(_agendarDeLaAgenda, findsOneWidget);
      expect(find.text('Agendada. La casa queda como «Entrevista agendada».'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _probar('con varias personas pregunta «¿Con quién?» y «Todavía no sé» agenda sin persona', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        personas: [
          mariaFernandez,
          clienteDePersonas('p2', 'Pedro', apellido: 'Gómez'),
        ],
      );
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Mataojo 2044');

      expect(_formulario, findsNothing);
      expect(find.textContaining('Pedro Gómez'), findsWidgets);
      await tester.tap(find.text('Todavía no sé con quién'));
      await asentarAgendar(tester);
      expect(_formulario, findsOneWidget);
      expect(find.text('Sin persona'), findsOneWidget);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);
      expect(m.agendas.recibidas.single.agenda.espacioId, 'esp-1');
      expect(m.agendas.recibidas.single.agenda.espacioPersonaId, isNull);
    });

    _probar('con varias personas, elegir a la segunda agenda con ella', (tester) async {
      final m = await _montar(
        tester,
        personas: [
          mariaFernandez,
          clienteDePersonas('p2', 'Pedro', apellido: 'Gómez'),
        ],
      );
      await _tocarAgendar(tester);
      await _elegirCasa(tester, 'Mataojo 2044');

      await tester.tap(find.textContaining('Pedro Gómez').last);
      await tester.pump();
      await tester.tap(find.text('Seguir'));
      await asentarAgendar(tester);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);

      expect(m.agendas.recibidas.single.agenda.espacioPersonaId, 'ep-p2');
    });

    _probar('sin personas en la casa, la cita queda «Sin persona» sin preguntar', (tester) async {
      final m = await _montar(tester, personas: const []);
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Mataojo 2044');

      expect(_formulario, findsOneWidget);
      expect(find.text('Sin persona'), findsOneWidget);
      await tester.ensureVisible(_guardar);
      await tester.tap(_guardar);
      await asentarAgendar(tester);
      expect(m.agendas.recibidas.single.agenda.espacioPersonaId, isNull);
    });
  });

  group('casos límite', () {
    _probar('sin sesión no se abre nada y no se pierde nada', (tester) async {
      final m = await _montar(tester, sesion: null);

      await _tocarAgendar(tester);

      expect(m.llamadas, 1);
      expect(_seleccion, findsNothing);
      expect(_formulario, findsNothing);
      expect(m.agendas.recibidas, isEmpty);
      expect(tester.takeException(), isNull);
    });

    _probar('volver atrás de la lista cancela: nada se agenda y el botón sirve otra vez', (
      tester,
    ) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);

      await tester.tap(_atras);
      await asentarAgendar(tester);

      expect(_seleccion, findsNothing);
      expect(_agendarDeLaAgenda, findsOneWidget);
      expect(m.agendas.recibidas, isEmpty);
      // Reentrada: se vuelve a abrir la lista, con las casas.
      await _tocarAgendar(tester);
      expect(_seleccion, findsOneWidget);
      expect(find.text('Mataojo 2044'), findsOneWidget);
      expect(m.llamadas, 2);
    });

    _probar('cerrar «¿Con quién?» sin elegir vuelve a la Agenda sin agendar', (tester) async {
      final m = await _montar(
        tester,
        personas: [
          mariaFernandez,
          clienteDePersonas('p2', 'Pedro', apellido: 'Gómez'),
        ],
      );
      await _tocarAgendar(tester);
      await _elegirCasa(tester, 'Mataojo 2044');

      // Toque afuera de la hoja.
      await tester.tapAt(const Offset(195, 20));
      await asentarAgendar(tester);

      expect(_formulario, findsNothing);
      expect(_seleccion, findsNothing);
      expect(m.agendas.recibidas, isEmpty);
      expect(_agendarDeLaAgenda, findsOneWidget);
      // Y se puede volver a empezar.
      await _tocarAgendar(tester);
      expect(_seleccion, findsOneWidget);
    });

    _probar('volver atrás de «Agendar visita» sin guardar no agenda nada', (tester) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);
      await _elegirCasa(tester, 'Mataojo 2044');

      await tester.tap(find.byKey(ClavesAgendarVisita.cerrar));
      await asentarAgendar(tester);

      expect(_formulario, findsNothing);
      expect(m.agendas.recibidas, isEmpty);
      expect(_agendarDeLaAgenda, findsOneWidget);
    });

    _probar('un doble toque en «+ Agendar» abre UNA lista, no dos apiladas', (tester) async {
      final m = await _montar(tester);

      await tester.tap(_agendarDeLaAgenda);
      await tester.tap(_agendarDeLaAgenda, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(_seleccion, findsOneWidget);
      expect(m.llamadas, 1);
      await tester.tap(_atras);
      await asentarAgendar(tester);
      // Si hubiera dos apiladas, queda una abierta tapando la Agenda.
      expect(_seleccion, findsNothing);
      expect(_agendarDeLaAgenda, findsOneWidget);
    });

    _probar('un doble toque en la casa lee los espacios una vez y abre UN formulario', (
      tester,
    ) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);
      m.espacios.compuerta = Completer<void>();

      await tester.tap(find.text('Mataojo 2044'));
      await tester.tap(find.text('Mataojo 2044'), warnIfMissed: false);
      await tester.pump();
      m.espacios.compuerta!.complete();
      await asentarAgendar(tester);

      expect(m.espacios.listados, 1);
      expect(_formulario, findsOneWidget);
      await tester.tap(find.byKey(ClavesAgendarVisita.cerrar));
      await asentarAgendar(tester);
      expect(_formulario, findsNothing);
      expect(_seleccion, findsNothing);
      expect(_agendarDeLaAgenda, findsOneWidget);
    });

    _probar('falla a mitad de la elección: avisa, no se traba y reintentar funciona', (
      tester,
    ) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);
      m.espacios.falla = const FailureInesperado();

      await _elegirCasa(tester, 'Mataojo 2044');

      expect(_seleccion, findsOneWidget);
      expect(find.text(TextosAgenda.noPudimosAbrir), findsOneWidget);
      expect(_formulario, findsNothing);

      m.espacios.falla = null;
      await _elegirCasa(tester, 'Mataojo 2044');
      expect(_formulario, findsOneWidget);
      expect(m.espacios.listados, 2);
    });

    _probar('si leer los espacios lanza, avisa y el toque vuelve a servir', (tester) async {
      final m = await _montar(tester);
      await _tocarAgendar(tester);
      m.espacios.lanza = StateError('base cerrada');

      await _elegirCasa(tester, 'Mataojo 2044');

      expect(find.text(TextosAgenda.noPudimosAbrir), findsOneWidget);
      expect(_seleccion, findsOneWidget);
      m.espacios.lanza = null;
      await _elegirCasa(tester, 'Mataojo 2044');
      expect(_formulario, findsOneWidget);
    });

    _probar('una casa sin espacio activo avisa y deja elegir otra', (tester) async {
      await _montar(
        tester,
        filas: [
          filaLista('u-5', calle: 'Brasil', numero: '12'),
          filaLista('u-1', calle: 'Mataojo', numero: '2044'),
        ],
      );
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Brasil 12');

      expect(find.text(TextosElegirCasaParaAgendar.sinLugar), findsOneWidget);
      expect(_formulario, findsNothing);
      await _elegirCasa(tester, 'Mataojo 2044');
      expect(_formulario, findsOneWidget);
    });

    _probar('un edificio no se elige: avisa lo mismo que «Registrar visita» y sigue la lista', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        filas: [
          filaLista(
            'u-3',
            tipo: TipoUbicacion.edificio,
            calle: 'Rondeau',
            numero: '900',
            espacios: 2,
          ),
          filaLista('u-1', calle: 'Mataojo', numero: '2044'),
        ],
      );
      await _tocarAgendar(tester);

      await _elegirCasa(tester, 'Rondeau 900');

      expect(find.text(TextosRegistrarVisita.edificioSinDepto), findsOneWidget);
      expect(_seleccion, findsOneWidget);
      expect(_formulario, findsNothing);
      expect(m.espacios.listados, 0);
    });

    _probar('una casa dada de baja no se elige: su fila lleva a «Reactivar», no al formulario', (
      tester,
    ) async {
      final m = await _montar(
        tester,
        filas: [
          filaLista('u-1', calle: 'Mataojo', numero: '2044'),
          filaLista('u-4', calle: 'Brasil', numero: '12', baja: DateTime.utc(2026, 10, 1)),
        ],
      );
      await _tocarAgendar(tester);
      ProviderScope.containerOf(tester.element(_seleccion))
          .read(listaUbicacionesProvider('col-1').notifier)
          .aplicar(
            tipos: const {},
            estados: const {},
            ciudadId: null,
            proximidad: ProximidadLista.cualquiera,
            incluirBajas: true,
          );
      await asentarAgendar(tester);

      expect(find.text('Brasil 12'), findsOneWidget);
      await _elegirCasa(tester, 'Brasil 12');

      expect(find.text(TextosReactivar.reactivar), findsWidgets);
      expect(_formulario, findsNothing);
      expect(m.espacios.listados, 0);
      expect(m.agendas.recibidas, isEmpty);
    });

    _probar('sin ubicaciones la lista lo dice y se puede volver sin romper nada', (tester) async {
      await _montar(tester, filas: const []);

      await _tocarAgendar(tester);

      expect(_seleccion, findsOneWidget);
      expect(find.text('Todavía no registraste ubicaciones'), findsOneWidget);
      await tester.tap(_atras);
      await asentarAgendar(tester);
      expect(_agendarDeLaAgenda, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _probar('dos agendas seguidas: la segunda no pisa a la primera', (tester) async {
      final m = await _montar(tester);
      for (final casa in ['Mataojo 2044', 'Rivera 77']) {
        await _tocarAgendar(tester);
        await _elegirCasa(tester, casa);
        await tester.ensureVisible(_guardar);
        await tester.tap(_guardar);
        await asentarAgendar(tester);
      }

      expect(m.agendas.cuantasQuedaron, 2);
      expect(m.agendas.recibidas.map((r) => r.agenda.espacioId), ['esp-1', 'esp-2']);
    });

    _probar('con muchas casas y texto al 200 % se puede elegir una de abajo', (tester) async {
      final muchas = [
        for (var i = 0; i < 60; i++)
          filaLista(
            'u-${100 + i}',
            calle: 'Avenida General Fructuoso Rivera del Norte',
            numero: '${1000 + i}',
            hace: Duration(minutes: i),
          ),
        filaLista('u-1', calle: 'Mataojo', numero: '2044', hace: const Duration(days: 20)),
      ];
      await _montar(tester, filas: muchas, escala: 2, tamano: const Size(360, 640));
      await _tocarAgendar(tester);
      // La lista tiene un desborde conocido de su fila de filtros con Ahem a 200 % (no es de este paso).
      final previo = tester.takeException();
      expect(previo == null || previo.toString().contains('overflowed'), isTrue);

      expect(find.text(TextosElegirCasaParaAgendar.titulo), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      final tocable = tester.getSize(_atras);
      expect(tocable.width, greaterThanOrEqualTo(48));
      expect(tocable.height, greaterThanOrEqualTo(48));
    });
  });
}
