// Arnés de «Entrevista dada» y «Vender» de «¿Qué pasó?» (vista 39, R·04 → R·05 y venta desde la casa;
// #648): monta «✓ Registrar visita» (`FlujoRegistrarVisita.abrir`) con los dos ganchos enchufados a
// sus flujos reales, como los enchufa `main.dart`, la entrevista en curso en memoria, la venta de verdad
// con fakes y el aviso fijo del mapa.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_entrevista_dada.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_vender_desde_la_casa.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/rotulo_entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/aviso_entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/services/lector_entrevistas_de_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/asi_quedo_la_venta_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/cuando_cobrar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart';
import 'entrevista_falsos.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';
import 'qa_vista39_venta_428_arnes.dart' show AgendaDeTodo428;
import 'venta_ui_falsos.dart';

/// Cuándo fue la última entrevista dada de cada vínculo (`espacio_persona.id`), y si leerla falla.
final class LectorDeEntrevistasFalso implements LectorEntrevistasDePersonas {
  final porVinculo = <String, DateTime>{};
  var falla = false;
  var lecturas = 0;

  @override
  Future<Map<String, DateTime>> ultimaEntrevistaDe(Iterable<String> vinculoIds) async {
    lecturas++;
    if (falla) throw StateError('no se puede leer');
    return {for (final id in vinculoIds) id: ?porVinculo[id]};
  }
}

final class Arnes648 {
  final montaje = MontajeEntrevista();
  final entorno = EntornoDeVenta();
  final agendas = AgendaRepositorioQueAgenda();
  final telefono = Telefono();
  final lector = LectorDeEntrevistasFalso();
  final navegador = GlobalKey<NavigatorState>();
  final jornadas = JornadaLocalDataSourceEnMemoria();

  /// Lo que devolvió cada `FlujoRegistrarVisita.abrir` terminado.
  final resultados = <bool>[];
  Object? errorAlAbrir;

  /// Los contextos que recibieron los ganchos, en orden.
  final entrevistas = <ContextoDeEntrevista>[];
  final ventas = <ContextoDeVenta>[];

  /// Lo que contestan los ganchos reales (lo que devolvieron).
  final salidasDeEntrevista = <Object?>[];
  final salidasDeVenta = <Object?>[];

  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  Future<void> montar(
    WidgetTester tester, {
    List<PersonaDelEspacio>? personas,
    bool conEntrevistaDada = true,
    bool conVender = true,
    double escala = 1,
    Size tamano = const Size(390, 844),
    String? agendaId,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    montaje.agendaPropia = AgendaDeTodo428(montaje.agenda, agendas);
    final repoPersonas = PersonaRepositorioFalso()
      ..sembrar(personas ?? [clienteDePersonas('1', 'Pedro', apellido: 'Gómez')]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...montaje.overrides,
          ...entorno.overrides,
          ...telefono.overrides,
          personaRepositoryProvider.overrideWithValue(repoPersonas),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(casaMataojo()),
          ),
          jornadaLocalDataSourceProvider.overrideWithValue(jornadas),
          lectorEntrevistasDePersonasProvider.overrideWithValue(lector),
          rotuloDelLugarYLaPersonaProvider.overrideWith((ref, clave) async => montaje.rotulo),
          if (conEntrevistaDada)
            entrevistaDadaDesdeLaCasaProvider.overrideWith(
              (ref) => (datos) async {
                entrevistas.add(datos);
                final r = await FlujoEntrevistaDada.abrir(
                  navegador.currentContext!,
                  datos,
                  colportorId: 'col-1',
                );
                salidasDeEntrevista.add(r);
                return r;
              },
            ),
          if (conVender)
            venderDesdeLaCasaProvider.overrideWith(
              (ref) => (datos) async {
                ventas.add(datos);
                final r = await FlujoVenderDesdeLaCasa.abrir(
                  navegador.currentContext!,
                  datos,
                  colportorId: 'col-1',
                );
                salidasDeVenta.add(r);
                return r;
              },
            ),
        ],
        child: MaterialApp(
          navigatorKey: navegador,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  // Como en el mapa: sin entrevista, el aviso sale del árbol.
                  Consumer(
                    builder: (context, ref, _) =>
                        ref.watch(entrevistaEnCursoProvider('col-1').select((e) => e.hayEntrevista))
                        ? const AvisoEntrevistaEnCurso(colportorId: 'col-1')
                        : const SizedBox.shrink(),
                  ),
                  Builder(
                    builder: (context) => ElevatedButton(
                      key: const Key('registrar_visita'),
                      onPressed: () async {
                        try {
                          resultados.add(
                            await FlujoRegistrarVisita.abrir(context, (
                              ubicacionId: 'ub-1',
                              espacioId: 'esp-1',
                              agendaId: agendaId,
                            ), colportorId: 'col-1'),
                          );
                        } on Object catch (e) {
                          errorAlAbrir = e;
                        }
                      },
                      child: const Text('registrar visita'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Son las 14:41 y la entrevista, si empieza, empieza a esa hora salvo que el test mueva el reloj.
    montaje.reloj = () => ahoraEntrevista;
  }

  /// Deja correr las animaciones y los futuros. Con «¿Qué pasó?» abierta (su renglón muestra un
  /// «Guardando…» que gira mientras R·05 está abierta) `pumpAndSettle` nunca termina.
  Future<void> asentar(WidgetTester tester, [int veces = 25]) async {
    for (var i = 0; i < veces; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Toca «✓ Registrar visita» y deja abrir «¿Qué pasó?».
  Future<void> abrirQuePaso(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('registrar_visita')));
    await tester.tap(find.byKey(const Key('registrar_visita')));
    await asentar(tester);
  }

  /// Toca el renglón de [o] de «¿Qué pasó?» y deja correr.
  Future<void> elegir(WidgetTester tester, OpcionQuePaso o) async {
    final renglon = find.byKey(ClavesQuePaso.opcion(o));
    await tester.ensureVisible(renglon);
    await tester.pump();
    await tester.tap(renglon);
    await asentar(tester);
  }

  Future<void> tocarKey(WidgetTester tester, Key clave) async {
    await tester.ensureVisible(find.byKey(clave));
    await tester.tap(find.byKey(clave));
    await asentar(tester);
  }

  /// «Registrar visita» → «Entrevista dada» (con una sola persona no se pregunta «¿Con quién?»).
  Future<void> hastaLaEntrevista(WidgetTester tester) async {
    await abrirQuePaso(tester);
    await elegir(tester, OpcionQuePaso.entrevistaDada);
  }

  /// R·05 → R·06.
  Future<void> hastaLaHoraDeSalida(WidgetTester tester) async {
    await hastaLaEntrevista(tester);
    await tocarKey(tester, ClavesEntrevista.finalizar);
  }

  /// R·06 → «Sí, registrar la venta» → la venta con el pack fijo y el talonario [numero].
  Future<void> hastaLaVenta(WidgetTester tester, {String numero = '0039'}) async {
    await hastaLaHoraDeSalida(tester);
    await tocarKey(tester, ClavesEntrevista.registrarVenta);
    await armarLaVenta(tester, numero: numero);
  }

  /// 27A·01 → 27A·05: un pack fijo ($ 3.000) con el talonario [numero], sin tocar «Registrar».
  Future<void> armarLaVenta(WidgetTester tester, {String numero = '0039'}) async {
    await tocar(tester, find.text('Pack Familia'));
    await tocar(tester, find.text(TextosVenta.armarLaColeccion));
    await tocar(tester, find.text(TextosVenta.agregarALaVenta));
    await escribir(
      tester,
      find.descendant(
        of: find.byKey(const Key('venta_talonario')),
        matching: find.byType(TextField),
      ),
      numero,
    );
  }

  /// Toca «Registrar» y pasa por 27A·14 «Venta registrada» con «Listo».
  Future<void> registrar(WidgetTester tester) async {
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await asentar(tester);
    if (find.byKey(const Key('venta_terminar')).evaluate().isNotEmpty) {
      await tocarKey(tester, const Key('venta_terminar'));
    }
  }

  /// «Registrar» y, sin saldo a la vista, «¿Cuándo volvés a cobrar?» → «Sin fecha» → «Guardar», y
  /// «Volver al mapa» en «Así quedó la venta» (42B·01).
  Future<void> registrarSinFecha(WidgetTester tester) async {
    await registrar(tester);
    await tocarKey(tester, ClavesCuandoCobrar.opcion(CuandoCobrar.sinFecha));
    await tocarKey(tester, ClavesCuandoCobrar.guardar);
    if (find.byKey(ClavesCierreDeVenta.volver).evaluate().isNotEmpty) {
      await tocarKey(tester, ClavesCierreDeVenta.volver);
    }
  }
}
