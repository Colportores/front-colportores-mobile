// Arnés de QA de #428 («Sí, registrar la venta», vista 39 R·06 / R·07 / R·08 → vista 27): monta el
// recorrido entero (aviso fijo → R·05 → R·06 → venta → «¿Cuándo volvés a cobrar?») con la venta de
// verdad y fakes en memoria. Es una copia chica del montaje del implementador con lo que el QA
// necesita: tamaño, escala, reloj y las compuertas de las fallas.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/aviso_entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/flujo_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_termino_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart';
import 'entrevista_falsos.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';
import 'venta_ui_falsos.dart';

/// La visita sale de [MontajeEntrevista.agenda]; la cobranza, de [agendas].
final class AgendaDeTodo428 implements AgendaRepository {
  AgendaDeTodo428(this.visitas, this.agendas);

  final AgendaFalsa visitas;
  final AgendaRepositorioQueAgenda agendas;

  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) => visitas.registrarVisita(visita, agendaId: agendaId, nota: nota);

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) =>
      agendas.agendar(agenda, nota: nota);

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda>> modificar(CambiosDeAgenda cambios, {required DateTime ahora}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, DetalleDeAgenda?>> obtenerDetalle(String agendaId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Visita>> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) => throw UnimplementedError();
}

final class Arnes428 {
  final montaje = MontajeEntrevista();
  final entorno = EntornoDeVenta();
  final agendas = AgendaRepositorioQueAgenda();
  final telefono = Telefono();
  SalidaTerminoEntrevista? salida;
  var devolvio = false;

  /// La letra de la app, mutable: se arma la venta con letra normal y se agranda para la pregunta.
  final escala = ValueNotifier<double>(1);

  /// El contenedor de Riverpod del árbol montado.
  ProviderContainer contenedor(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  Future<void> montar(
    WidgetTester tester, {
    double escala = 1,
    bool conEntrevista = true,
    Size tamano = const Size(390, 844),
    String persona = 'Pedro',
    String apellido = 'Gómez',
    GlobalKey? raiz,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    this.escala.value = escala;
    montaje.agendaPropia = AgendaDeTodo428(montaje.agenda, agendas);
    montaje.rotulo = (direccion: 'Grecia 3307', persona: '$persona $apellido'.trim());
    final personas = PersonaRepositorioFalso()
      ..sembrar([clienteDePersonas('1', persona, apellido: apellido)]);
    Future<void> corre(Future<SalidaTerminoEntrevista?> Function() flujo) async {
      devolvio = false;
      salida = await flujo();
      devolvio = true;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...montaje.overrides,
          ...entorno.overrides,
          ...telefono.overrides,
          personaRepositoryProvider.overrideWithValue(personas),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(casaMataojo()),
          ),
        ],
        child: RepaintBoundary(
          key: raiz,
          child: MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: this.escala,
              builder: (context, e, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(e)),
                child: child!,
              ),
            ),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => SingleChildScrollView(
                  child: Column(
                    children: [
                      const AvisoEntrevistaEnCurso(colportorId: 'col-1'),
                      ElevatedButton(
                        key: const Key('abrir'),
                        onPressed: () =>
                            corre(() => FlujoEntrevista.abrir(context, ref, colportorId: 'col-1')),
                        child: const Text('abrir'),
                      ),
                      ElevatedButton(
                        key: const Key('jornada'),
                        onPressed: () => corre(
                          () => FlujoEntrevista.terminar(
                            context,
                            ref,
                            colportorId: 'col-1',
                            pedirSalida: true,
                            desdeLaJornada: true,
                          ),
                        ),
                        child: const Text('jornada'),
                      ),
                      ElevatedButton(
                        key: const Key('sin-inicio'),
                        onPressed: () => corre(
                          () => FlujoEntrevista.terminarSinInicio(
                            context,
                            ref,
                            colportorId: 'col-1',
                            espacioId: 'esp-1',
                            espacioPersonaId: 'ep-1',
                            direccion: 'Grecia 3307',
                            persona: '$persona $apellido'.trim(),
                          ),
                        ),
                        child: const Text('sin inicio'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (!conEntrevista) return;
    // Empezó en esta sesión, a las 14:23, y ahora son las 14:41 (no se pide la salida).
    montaje.reloj = () => inicioEntrevista;
    await contenedor(tester)
        .read(entrevistaEnCursoProvider('col-1').notifier)
        .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
    montaje.reloj = () => ahoraEntrevista;
    await tester.pumpAndSettle();
  }

  Future<void> tocarKey(WidgetTester tester, Key clave) async {
    await tester.ensureVisible(find.byKey(clave));
    await tester.tap(find.byKey(clave));
    await tester.pumpAndSettle();
  }

  /// R·05 → R·06 → «Sí, registrar la venta».
  Future<void> hastaLaVenta(WidgetTester tester) async {
    await tocarKey(tester, const Key('abrir'));
    await tocarKey(tester, ClavesEntrevista.finalizar);
    await tocarKey(tester, ClavesEntrevista.registrarVenta);
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

  /// Registra la venta y pasa por 27A·14 «Venta registrada» con «Listo», que lleva a la pregunta.
  Future<void> registrar(WidgetTester tester) async {
    await tocar(tester, find.byKey(const Key('venta_cta')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('venta_terminar')).evaluate().isNotEmpty) {
      await tocarKey(tester, const Key('venta_terminar'));
    }
  }

  Future<void> hastaLaPregunta(WidgetTester tester, {Size? tamano, double? letra}) async {
    await hastaLaVenta(tester);
    await armarLaVenta(tester);
    if (tamano != null) tester.view.physicalSize = tamano;
    if (letra != null) escala.value = letra;
    await tester.pumpAndSettle();
    await registrar(tester);
  }
}
