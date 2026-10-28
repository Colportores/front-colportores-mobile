// Arnés de los tests del detalle y de «Modificar agenda» (vista 23 C, #409): un repositorio de la
// agenda que lee y modifica en memoria (con fallas y esperas a pedido) y la pantalla montada con un
// botón que abre el detalle, con el reloj, los recordatorios, las preferencias y la casa en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/cambios_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/hoja_con_quien_arnes.dart' show ObservadorDeRutas;
import 'agendar_visita_arnes.dart' show casaMataojo, mariaFernandez;
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';

/// El día del canvas: viernes 23/10/2026, 14:35 (hora local del test).
DateTime ahoraDelDetalle() => DateTime(2026, 10, 23, 14, 35);

/// La agenda del canvas 23C·01: entrevista el sáb 24/10 a las 14:30, «Primera tarde», con María.
Agenda agendaDelDetalle({
  String id = 'ag-1',
  EstadoAgenda estado = EstadoAgenda.programada,
  TipoAgenda tipo = TipoAgenda.entrevista,
  DateTime? cuando,
  String? slot = 'early_afternoon',
  String? ventaId,
  String? entregaId,
}) => Agenda(
  id: id,
  ventaId: ventaId,
  entregaId: entregaId,
  espacioId: 'esp-1',
  espacioPersonaId: 'ep-p1',
  tipo: tipo,
  fechaProgramada: (cuando ?? DateTime(2026, 10, 24, 14, 30)).toUtc(),
  slotCodigo: slot,
  estado: estado,
  colportorId: 'col-1',
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
    createdBy: 'col-1',
  ),
);

/// [AgendaRepository] que lee el detalle y modifica en memoria: registra lo que recibe, falla cuando el
/// test lo dice y espera cuando hay compuerta.
final class AgendaRepositorioDetalle implements AgendaRepository {
  AgendaRepositorioDetalle(this.detalle);

  /// Lo que devuelve [obtenerDetalle]; `null` es «esa agenda ya no está».
  DetalleDeAgenda? detalle;

  /// Cada [obtenerDetalle] toma la siguiente de [fallasDeLectura] (`null` o sin más: éxito).
  final fallasDeLectura = <Failure?>[];

  /// Cada [modificar] toma la siguiente de [fallas] (`null` o sin más: éxito).
  final fallas = <Failure?>[];

  /// Si no es `null`, [modificar] espera a que se complete.
  Completer<void>? compuerta;

  /// Si no es `null`, [obtenerDetalle] espera a que se complete (el teléfono todavía no contestó).
  Completer<void>? compuertaDeLectura;

  /// Si no es `null`, el próximo [modificar] lanza esto en vez de devolver un `Either`.
  Object? lanzar;

  /// Cada [cancelar] toma la siguiente de [fallasAlCancelar] (`null` o sin más: éxito).
  final fallasAlCancelar = <Failure?>[];

  /// Si no es `null`, [cancelar] espera a que se complete (una cancelación «en curso»).
  Completer<void>? compuertaAlCancelar;

  /// Si no es `null`, el próximo [cancelar] lanza esto en vez de devolver un `Either`.
  Object? lanzarAlCancelar;

  /// Se llama con la agenda cuando una cancelación sale bien (para que una lista de prueba la vea).
  void Function(Agenda cancelada)? alCancelarAgenda;

  var lecturas = 0;
  final recibidos = <CambiosDeAgenda>[];

  /// Los `agendaId` que llegaron a [cancelar], en orden.
  final canceladas = <String>[];

  @override
  Future<Either<Failure, DetalleDeAgenda?>> obtenerDetalle(String agendaId) async {
    lecturas += 1;
    await compuertaDeLectura?.future;
    final falla = fallasDeLectura.isEmpty ? null : fallasDeLectura.removeAt(0);
    if (falla != null) return Left(falla);
    return Right(detalle);
  }

  @override
  Future<Either<Failure, Agenda>> modificar(
    CambiosDeAgenda cambios, {
    required DateTime ahora,
  }) async {
    recibidos.add(cambios);
    await compuerta?.future;
    final error = lanzar;
    if (error != null) {
      lanzar = null;
      throw error;
    }
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla != null) return Left(falla);
    final actual = detalle!;
    final agenda = Agenda(
      id: actual.agenda.id,
      espacioId: actual.agenda.espacioId,
      espacioPersonaId: actual.agenda.espacioPersonaId,
      tipo: cambios.tipo,
      fechaProgramada: cambios.fechaProgramada,
      slotCodigo: cambios.slotCodigo,
      estado: actual.agenda.estado,
      colportorId: actual.agenda.colportorId,
      auditoria: actual.agenda.auditoria,
    );
    final nota = cambios.nota;
    detalle = DetalleDeAgenda(
      agenda: agenda,
      nota: nota == null ? actual.nota : (nota.trim().isEmpty ? null : nota.trim()),
      visita: actual.visita,
    );
    return Right(agenda);
  }

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) async {
    canceladas.add(agendaId);
    await compuertaAlCancelar?.future;
    final error = lanzarAlCancelar;
    if (error != null) {
      lanzarAlCancelar = null;
      throw error;
    }
    final falla = fallasAlCancelar.isEmpty ? null : fallasAlCancelar.removeAt(0);
    if (falla != null) return Left(falla);
    final actual = detalle!.agenda;
    final cancelada = Agenda(
      id: actual.id,
      espacioId: actual.espacioId,
      espacioPersonaId: actual.espacioPersonaId,
      tipo: actual.tipo,
      fechaProgramada: actual.fechaProgramada,
      slotCodigo: actual.slotCodigo,
      estado: EstadoAgenda.cancelada,
      colportorId: actual.colportorId,
      auditoria: actual.auditoria,
    );
    detalle = DetalleDeAgenda(agenda: cancelada, nota: detalle!.nota, visita: detalle!.visita);
    alCancelarAgenda?.call(cancelada);
    return Right(cancelada);
  }

  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda?>> agendaProgramadaDe(String espacioId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Visita>> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) => throw UnimplementedError();
}

class ArnesDetalle {
  ArnesDetalle({
    required this.repo,
    required this.telefono,
    required this.rutas,
    required this.ahora,
  });

  final AgendaRepositorioDetalle repo;
  final Telefono telefono;
  final ObservadorDeRutas rutas;

  RecordatoriosEnMemoria get recordatorios => telefono.recordatorios;

  /// El reloj de la pantalla; se mueve cambiando este campo.
  DateTime ahora;

  /// Lo que recibió «Registrar resultado» (si el test lo conecta).
  final registros = <ContextoDeVisita>[];
}

/// Monta una pantalla con el botón «abrir detalle» y, si [abrir], lo toca.
Future<ArnesDetalle> montarDetalle(
  WidgetTester tester, {
  DetalleDeAgenda? detalle,
  AgendaRepositorioDetalle? repo,
  EspacioConUbicacion? casa,
  bool sinCasa = false,
  Failure? fallaDeCasa,
  bool conRegistrar = false,
  Completer<void>? registrarDemorado,
  DateTime? ahora,
  bool permisoConcedido = true,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
  List<Override> extra = const [],
}) async {
  final arnes = ArnesDetalle(
    repo: repo ?? AgendaRepositorioDetalle(detalle ?? DetalleDeAgenda(agenda: agendaDelDetalle())),
    telefono: Telefono()..recordatorios.permisoConcedido = permisoConcedido,
    rutas: ObservadorDeRutas(),
    ahora: ahora ?? ahoraDelDetalle(),
  );
  var n = 0;
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final personasRepo = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  final lugar = sinCasa ? null : (casa ?? casaMataojo());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(arnes.repo),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(() => arnes.ahora),
        ...arnes.telefono.overrides,
        ...extra,
        personaRepositoryProvider.overrideWithValue(personasRepo),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(lugar, falla: fallaDeCasa),
        ),
        if (conRegistrar)
          registrarVisitaDesdeLaCasaProvider.overrideWithValue((c) {
            arnes.registros.add(c);
            final espera = registrarDemorado;
            return espera == null ? true : espera.future.then((_) => true);
          }),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: [arnes.rutas],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  DetalleAgendaPage.abrir(context, agendaId: 'ag-1', colportorId: 'col-1'),
                ),
                child: const Text('abrir detalle'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirDetalle(tester);
  return arnes;
}

Future<void> abrirDetalle(WidgetTester tester) async {
  await tester.tap(find.text('abrir detalle'));
  await asentarDetalle(tester);
}

/// Deja correr los fotogramas que hacen falta sin esperar a los indicadores que giran para siempre.
Future<void> asentarDetalle(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// La franja «Primera tarde» (para armar cambios en los tests).
const franjaDelDetalle = FranjaHoraria.primeraTarde;
