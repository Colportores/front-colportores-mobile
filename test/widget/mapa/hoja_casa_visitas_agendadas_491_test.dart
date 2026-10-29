// Vista 23, artboard 23B·10 «En el mapa: tocar la casa» (HU-VIS-002, #491): la hoja de la casa suma la
// lista «VISITAS AGENDADAS» —la entrevista del jueves, la cobranza del sábado—, con «Registrar visita»
// y «+ Agendar». Un test por estado del artboard y por caso límite de cada flujo: doble toque, falla a
// mitad, dos acciones seguidas, volver y reentrar, datos límite y texto al 200 y 300 %.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/visitas_agendadas_de_la_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/persona_falsos.dart';

final _ana = clienteDePersonas('p-ana', 'Ana', apellido: 'Gómez');

/// Jueves 8/10/2026 y sábado 10/10/2026 (la hoja se monta el martes 6/10).
final _jueves = DateTime(2026, 10, 8, 14, 30);
final _sabado = DateTime(2026, 10, 10, 12, 30);

ItemAgenda _entrevista(String id, DateTime cuando, {String ub = 'u-1', String? nombre}) =>
    itemAgenda(
      id,
      cuando,
      nombre: nombre ?? 'María',
      apellido: nombre == null ? 'Fernández' : null,
      ubicacionId: ub,
    );

ItemAgenda _cobranza(String id, DateTime cuando, {String ub = 'u-1'}) => itemAgenda(
  id,
  cuando,
  tipo: TipoAgenda.cobranza,
  nombre: 'María',
  apellido: 'Fernández',
  ubicacionId: ub,
);

/// Lo que un test necesita después de montar la hoja.
final class _Montaje {
  final detalles = <String>[];
  final visitas = <ContextoDeVisita>[];
  final citas = <ContextoDeCita>[];
  int get agendar => citas.length;
  final cierres = <int>[];
}

Future<_Montaje> _montar(
  WidgetTester tester,
  ConsultaAgendaFalsa repo, {
  bool arriba = false,
  ItemListaUbicacion? item,
  String? colportorId = 'col-1',
  bool conDetalle = true,
  bool conAgendar = true,
  FutureOr<Object?> Function(String agendaId)? detalle,
  FutureOr<Object?> Function(ContextoDeCita)? agendar,
  ContextoDeLaCasa? contexto,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final m = _Montaje();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final overrides = <Override>[
    ...overridesHojaCasa(
      registrarVisita: m.visitas.add,
      agendas: repo,
      lectura: contexto == null ? null : (_) => Stream.value(contexto),
      // El repositorio de personas dice lo mismo que el contexto de la hoja.
      personas: PersonaRepositorioFalso()..sembrar(contexto?.personas ?? const []),
    ),
    abrirDetalleDeAgendaProvider.overrideWithValue(
      conDetalle
          ? (id) async {
              m.detalles.add(id);
              return detalle?.call(id);
            }
          : null,
    ),
    // «+ Agendar» abre «Agendar visita» con la casa puesta: el mismo destino de «Programar entrevista».
    programarEntrevistaDesdeLaCasaProvider.overrideWithValue(
      conAgendar
          ? (cita) async {
              m.citas.add(cita);
              return agendar?.call(cita);
            }
          : null,
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: item ?? itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () => m.cierres.add(m.cierres.length),
              arriba: arriba,
              colportorId: colportorId,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return m;
}

void _probar(String descripcion, Future<void> Function(WidgetTester tester) cuerpo) {
  testWidgets(descripcion, (tester) async {
    await cuerpo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Finder get _seccion => find.byKey(ClavesVisitasAgendadas.seccion);
Finder get _filas => find.byType(FilaVisitaAgendada);
Finder get _registrar => find.byKey(ClavesHojaCasa.registrarVisita);
Finder get _agendar => find.byKey(ClavesHojaCasa.agendar);
Finder _fila(String id) => find.byKey(ClavesVisitasAgendadas.fila(id));

void main() {
  group('23B·10 · Visitas agendadas de la casa', () {
    _probar('muestra el rótulo y las visitas de la casa, las dos, en orden, con sus datos', (
      tester,
    ) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_cobranza('cob', _sabado), _entrevista('ent', _jueves)]),
      );

      expect(find.text('VISITAS AGENDADAS'), findsOneWidget);
      expect(_filas, findsNWidgets(2));
      expect(find.text('JUE 08/10 · 14:30'), findsOneWidget);
      expect(find.text('SÁB 10/10 · 12:30'), findsOneWidget);
      expect(find.text('Entrevista'), findsOneWidget);
      expect(find.text('Cobranza'), findsOneWidget);
      expect(find.text('María Fernández'), findsNWidgets(2));
      // La entrevista del jueves arriba de la cobranza del sábado.
      expect(tester.getTopLeft(_fila('ent')).dy, lessThan(tester.getTopLeft(_fila('cob')).dy));
    });

    _probar('va entre la persona y «Registrar visita», con «+ Agendar» debajo', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([_entrevista('ent', _jueves)]));

      final rotulo = tester.getTopLeft(find.byKey(ClavesVisitasAgendadas.rotulo)).dy;
      final fila = tester.getTopLeft(_filas).dy;
      expect(rotulo, lessThan(fila));
      expect(fila, lessThan(tester.getTopLeft(_registrar).dy));
      expect(tester.getTopLeft(_registrar).dy, lessThan(tester.getTopLeft(_agendar).dy));
      expect(find.text('+ Agendar'), findsOneWidget);
    });

    _probar('una cobranza en otra dirección dice «en» esa dirección', (tester) async {
      final alternativa = _cobranza('cob', _sabado);
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          ItemAgenda(
            agenda: alternativa.agenda,
            personaNombre: 'María',
            personaApellido: 'Fernández',
            casa: alternativa.casa,
            alternativa: const DireccionDeAgenda(
              ubicacionId: 'alt',
              tipo: TipoUbicacion.casa,
              calle: 'Av. Italia',
              numero: '2810',
            ),
          ),
        ]),
      );

      expect(find.text('María Fernández · en Av. Italia 2810'), findsOneWidget);
    });

    _probar('en un edificio, la visita dice el depto', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          itemAgenda(
            'ent',
            _jueves,
            nombre: null,
            apellido: null,
            tipoUbicacion: TipoUbicacion.edificio,
            numeroDepto: '3B',
            ubicacionId: 'u-1',
          ),
        ]),
        item: itemDeLaHoja(tipo: TipoUbicacion.edificio),
      );

      expect(find.text('Depto 3B'), findsOneWidget);
    });

    _probar('solo las de esta casa y solo las programadas', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          _entrevista('mia', _jueves),
          _entrevista('otra-casa', _jueves, ub: 'u-2'),
          itemAgenda('cumplida', _jueves, estado: EstadoAgenda.cumplida, ubicacionId: 'u-1'),
          itemAgenda('cancelada', _jueves, estado: EstadoAgenda.cancelada, ubicacionId: 'u-1'),
          itemAgenda('ajena', _jueves, colportorId: 'col-2', ubicacionId: 'u-1'),
        ]),
      );

      expect(_filas, findsOneWidget);
      expect(_fila('mia'), findsOneWidget);
    });

    _probar('sin visitas agendadas la lista no ocupa lugar y los botones siguen', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa());

      expect(_seccion, findsNothing);
      expect(find.text('VISITAS AGENDADAS'), findsNothing);
      expect(_registrar, findsOneWidget);
      expect(_agendar, findsOneWidget);
    });

    _probar('con la casa de baja no hay lista ni «+ Agendar»', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('ent', _jueves)]),
        item: itemDeLaHoja(baja: DateTime.utc(2026, 10, 1)),
      );

      expect(_seccion, findsNothing);
      expect(_agendar, findsNothing);
      expect(_registrar, findsNothing);
    });

    _probar('sin colportor con la sesión no se lee la agenda de la casa', (tester) async {
      final repo = ConsultaAgendaFalsa([_entrevista('ent', _jueves)]);
      await _montar(tester, repo, colportorId: null);

      expect(_seccion, findsNothing);
      expect(repo.pedidosDeLaCasa, isEmpty);
    });

    _probar('lee la agenda de esta casa con el colportor de la sesión', (tester) async {
      final repo = ConsultaAgendaFalsa([_entrevista('ent', _jueves)]);
      await _montar(tester, repo);

      expect(repo.pedidosDeLaCasa, [(colportorId: 'col-1', ubicacionId: 'u-1')]);
    });

    _probar('con la hoja arriba va en el mismo orden que el resumen: lista, botones y pestañas', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa([_entrevista('ent', _jueves)]), arriba: true);

      expect(_filas, findsOneWidget);
      final lista = tester.getTopLeft(_filas).dy;
      final registrar = tester.getTopLeft(_registrar).dy;
      final agendar = tester.getTopLeft(_agendar).dy;
      final pestanas = tester.getTopLeft(find.byKey(ClavesHojaCasa.pestanas)).dy;
      expect(lista, lessThan(registrar));
      expect(registrar, lessThan(agendar));
      expect(agendar, lessThan(pestanas));
    });

    _probar('una visita cuya hora ya pasó lo dice', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('vencida', DateTime(2026, 10, 5, 9))]),
      );

      expect(find.text('Pasó la hora · registrá qué pasó'), findsOneWidget);
    });

    _probar('se actualiza sola cuando se agenda o se cancela una visita', (tester) async {
      final repo = ConsultaAgendaFalsa([_entrevista('ent', _jueves)]);
      await _montar(tester, repo);
      expect(_filas, findsOneWidget);

      repo.emitir([_entrevista('ent', _jueves), _cobranza('cob', _sabado)]);
      await tester.pump();
      expect(_filas, findsNWidgets(2));

      repo.emitir([]);
      await tester.pump();
      expect(_seccion, findsNothing);
    });

    _probar('el lector de pantalla dice cuándo, qué y con quién', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, ConsultaAgendaFalsa([_entrevista('ent', _jueves)]));

      expect(
        find.bySemanticsLabel('JUE 08/10 · 14:30. Entrevista. María Fernández'),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });

  group('Tocar una visita abre su detalle (23C·01)', () {
    _probar('abre el detalle de la visita tocada', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('ent', _jueves), _cobranza('cob', _sabado)]),
      );

      await tester.tap(_fila('cob'));
      await tester.pump();

      expect(m.detalles, ['cob']);
      expect(find.text('›'), findsNWidgets(2));
    });

    _probar('sin destino las filas no se tocan y no llevan «›»', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('ent', _jueves)]),
        conDetalle: false,
      );

      await tester.tap(_fila('ent'));
      await tester.pump();

      expect(m.detalles, isEmpty);
      expect(find.text('›'), findsNothing);
    });

    _probar('un doble toque abre un solo detalle', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('ent', _jueves)]),
        detalle: (_) => Future<void>.delayed(const Duration(seconds: 1)),
      );

      await tester.tap(_fila('ent'));
      await tester.tap(_fila('ent'));
      await tester.pump(const Duration(seconds: 2));

      expect(m.detalles, ['ent']);
    });

    _probar('dos filas seguidas: mientras la primera está abierta la segunda no abre otra', (
      tester,
    ) async {
      final cierre = Completer<void>();
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('ent', _jueves), _cobranza('cob', _sabado)]),
        detalle: (_) => cierre.future,
      );

      await tester.tap(_fila('ent'));
      await tester.tap(_fila('cob'));
      await tester.pump();
      expect(m.detalles, ['ent']);

      cierre.complete();
      await tester.pump();
      await tester.tap(_fila('cob'));
      await tester.pump();
      expect(m.detalles, ['ent', 'cob']);
    });

    _probar('si el detalle falla avisa y las filas vuelven a poder tocarse', (tester) async {
      var falla = true;
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa([_entrevista('ent', _jueves)]),
        detalle: (_) {
          if (falla) throw StateError('no abre');
          return null;
        },
      );

      await tester.tap(_fila('ent'));
      await tester.pump();
      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOneWidget);

      falla = false;
      await tester.tap(_fila('ent'));
      await tester.pump();
      expect(m.detalles, ['ent', 'ent']);
    });

    _probar('volver a la hoja y reentrar vuelve a leer y a mostrar la lista', (tester) async {
      final repo = ConsultaAgendaFalsa([_entrevista('ent', _jueves)]);
      await _montar(tester, repo);
      expect(_filas, findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await _montar(tester, repo);

      expect(_filas, findsOneWidget);
      expect(repo.pedidosDeLaCasa, hasLength(2));
    });
  });

  group('«+ Agendar»', () {
    _probar('abre «Agendar visita» con la casa y su espacio ya puestos', (tester) async {
      final m = await _montar(tester, ConsultaAgendaFalsa([_entrevista('ent', _jueves)]));

      await tester.tap(_agendar);
      await tester.pump();

      expect(m.citas, [
        (ubicacionId: 'u-1', espacioId: 'esp-1', espacioPersonaId: null, personaId: null),
      ]);
    });

    _probar('en un edificio con el depto elegido lleva ese espacio', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa(),
        item: itemDeLaHoja(tipo: TipoUbicacion.edificio),
        contexto: const ContextoDeLaCasa(espacioId: 'esp-3B', personas: []),
      );

      await tester.tap(_agendar);
      await tester.pump();

      expect(m.citas.single.espacioId, 'esp-3B');
      expect(m.citas.single.ubicacionId, 'u-1');
    });

    _probar(
      'en un edificio sin depto elegido se ve y al tocarlo avisa que el depto se elige antes',
      (tester) async {
        final m = await _montar(
          tester,
          ConsultaAgendaFalsa(),
          item: itemDeLaHoja(tipo: TipoUbicacion.edificio),
          contexto: const ContextoDeLaCasa(personas: []),
        );

        expect(_agendar, findsOneWidget);
        await tester.tap(_agendar);
        await tester.pump();

        expect(find.text(TextosRegistrarVisita.edificioSinDepto), findsOneWidget);
        expect(m.citas, isEmpty);
      },
    );

    _probar('con una sola persona la cita va con ella, sin preguntar', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa(),
        contexto: ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez]),
      );

      await tester.tap(_agendar);
      await tester.pumpAndSettle();

      expect(m.citas.single.espacioPersonaId, pedroGomez.vinculo.id);
      expect(m.citas.single.personaId, pedroGomez.persona.id);
      expect(find.byType(HojaConQuien), findsNothing);
    });

    _probar('con varias personas pregunta con quién antes de abrir el formulario', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa(),
        contexto: ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez, _ana]),
      );

      await tester.tap(_agendar);
      await tester.pumpAndSettle();
      expect(m.citas, isEmpty);
      expect(find.byType(HojaConQuien), findsOneWidget);

      await tester.tap(find.textContaining('Ana Gómez').first);
      await tester.pump();
      await tester.tap(find.text('Seguir'));
      await tester.pumpAndSettle();

      expect(m.citas.single.personaId, _ana.persona.id);
    });

    _probar('con varias personas, «Volver» no abre el formulario', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa(),
        contexto: ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez, _ana]),
      );

      await tester.tap(_agendar);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();

      expect(m.citas, isEmpty);
      expect(find.byType(HojaConQuien), findsNothing);
    });

    _probar('sin personas la cita queda sin persona y sin preguntar', (tester) async {
      final m = await _montar(tester, ConsultaAgendaFalsa());

      await tester.tap(_agendar);
      await tester.pumpAndSettle();

      expect(m.citas.single.espacioPersonaId, isNull);
      expect(m.citas.single.personaId, isNull);
      expect(find.byType(HojaConQuien), findsNothing);
    });

    _probar('un doble toque con varias personas abre una sola pregunta', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa(),
        contexto: ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez, _ana]),
      );

      await tester.tap(_agendar);
      await tester.tap(_agendar, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(HojaConQuien), findsOneWidget);
    });

    _probar('sin destino no se muestra, como «Registrar visita»', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([_entrevista('ent', _jueves)]), conAgendar: false);

      expect(_agendar, findsNothing);
      expect(find.text('+ Agendar'), findsNothing);
    });

    _probar('un doble toque abre una sola vez', (tester) async {
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa(),
        agendar: (_) => Future<void>.delayed(const Duration(seconds: 1)),
      );

      await tester.tap(_agendar);
      await tester.tap(_agendar, warnIfMissed: false);
      await tester.pump(const Duration(seconds: 2));

      expect(m.agendar, 1);
    });

    _probar('si falla avisa y el botón vuelve a poder tocarse', (tester) async {
      var falla = true;
      final m = await _montar(
        tester,
        ConsultaAgendaFalsa(),
        agendar: (_) {
          if (falla) throw StateError('no abre');
          return null;
        },
      );

      await tester.tap(_agendar);
      await tester.pump();
      expect(find.text('No pudimos abrir eso. Probá de nuevo.'), findsOneWidget);

      falla = false;
      await tester.tap(_agendar);
      await tester.pump();
      expect(m.agendar, 2);
    });

    _probar('mientras se abre, «Registrar visita» no abre otro destino a la vez', (tester) async {
      final cierre = Completer<void>();
      final m = await _montar(tester, ConsultaAgendaFalsa(), agendar: (_) => cierre.future);

      await tester.tap(_agendar);
      await tester.pump();
      await tester.tap(_registrar, warnIfMissed: false);
      await tester.pump();
      expect(m.agendar, 1);
      expect(m.visitas, isEmpty);

      cierre.complete();
      await tester.pump();
    });
  });

  group('Error de lectura', () {
    _probar('«No pudimos leer tu agenda.» con «Reintentar», y los botones de la hoja siguen', (
      tester,
    ) async {
      final repo = ConsultaAgendaFalsa()..error = StateError('disco');
      await _montar(tester, repo);

      expect(find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeerAgendas), findsOneWidget);
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      expect(_registrar, findsOneWidget);
      expect(_seccion, findsNothing);
    });

    _probar(
      'el aviso va arriba de la persona y se ve sin desplazar a 360×640, en el resumen y arriba',
      (tester) async {
        for (final arriba in [false, true]) {
          final repo = ConsultaAgendaFalsa()..error = StateError('disco');
          await _montar(tester, repo, arriba: arriba, tamano: const Size(360, 640));

          final aviso = find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeerAgendas);
          expect(aviso, findsOneWidget);
          final caja = tester.getRect(aviso);
          expect(caja.top, greaterThanOrEqualTo(0));
          expect(caja.bottom, lessThanOrEqualTo(640));
          if (!arriba) {
            expect(caja.top, lessThan(tester.getTopLeft(find.byKey(ClavesHojaCasa.persona)).dy));
          }
          expect(find.text('Reintentar').hitTestable(), findsOneWidget);
        }
      },
    );

    _probar('se anuncia una sola vez, como mensaje de estado (región viva del propio aviso)', (
      tester,
    ) async {
      await _montar(tester, ConsultaAgendaFalsa()..error = StateError('disco'));

      final regiones = find.descendant(
        of: find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeerAgendas),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(regiones, findsOneWidget);
    });

    _probar('«Reintentar» vuelve a leer y, si ahora anda, muestra la lista', (tester) async {
      final repo = ConsultaAgendaFalsa([_entrevista('ent', _jueves)])..error = StateError('disco');
      await _montar(tester, repo);
      expect(repo.pedidosDeLaCasa, hasLength(1));

      repo.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(repo.pedidosDeLaCasa, hasLength(2));
      expect(find.text('No pudimos leer tu agenda.'), findsNothing);
      expect(_filas, findsOneWidget);
    });

    _probar('un error que llega después de los primeros datos también se dice', (tester) async {
      final repo = ConsultaAgendaFalsa([_entrevista('ent', _jueves)]);
      await _montar(tester, repo);
      expect(_filas, findsOneWidget);

      repo.emitirError(StateError('disco'));
      await tester.pump();
      await tester.pump();

      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
    });

    _probar('mientras lee no ocupa lugar', (tester) async {
      final repo = ConsultaAgendaFalsa([_entrevista('ent', _jueves)])..congelada = true;
      await _montar(tester, repo);

      expect(_seccion, findsNothing);
      expect(find.byKey(ClavesEstadosHojaCasa.avisoErrorAlLeerAgendas), findsNothing);
      expect(_registrar, findsOneWidget);
    });
  });

  group('Datos límite y texto grande', () {
    for (final escala in [1.0, 2.0, 3.0]) {
      _probar('texto al ${(escala * 100).round()} %: sin desbordes y con el botón alcanzable', (
        tester,
      ) async {
        await _montar(
          tester,
          ConsultaAgendaFalsa([
            _entrevista(
              'ent',
              _jueves,
              nombre: 'Maria de los Angeles Fernandez de la Torre y Casal',
            ),
            _cobranza('cob', _sabado),
          ]),
          escala: escala,
          tamano: const Size(360, 640),
        );

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_registrar);
        expect(_registrar.hitTestable(), findsOneWidget);
        final fila = tester.getSize(_fila('ent'));
        expect(fila.height, greaterThanOrEqualTo(64));
      });
    }

    _probar('muchas visitas: la hoja se desplaza y «Registrar visita» se alcanza', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          for (var i = 0; i < 30; i++)
            _entrevista('v$i', DateTime(2026, 10, 8, 9).add(Duration(hours: i))),
        ]),
        tamano: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_registrar);
      await tester.pump();
      expect(_registrar.hitTestable(), findsOneWidget);
    });

    _probar('una visita sin persona ni depto muestra solo cuándo y el tipo', (tester) async {
      await _montar(
        tester,
        ConsultaAgendaFalsa([
          itemAgenda('ent', _jueves, nombre: null, apellido: null, ubicacionId: 'u-1'),
        ]),
      );

      expect(find.text('JUE 08/10 · 14:30'), findsOneWidget);
      expect(find.text('Entrevista'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    _probar('una visita de otro año lleva el año', (tester) async {
      await _montar(tester, ConsultaAgendaFalsa([_entrevista('ent', DateTime(2027, 1, 7, 10))]));

      expect(find.text('JUE 07/01/2027 · 10:00'), findsOneWidget);
    });
  });
}
