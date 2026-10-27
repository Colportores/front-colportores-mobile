// Arnés de los tests de «Agendar una visita» (vista 23 A, #408): el repositorio de la agenda que
// registra lo que recibe, y la pantalla montada con un botón que abre `FlujoAgendarVisita.abrir`, con
// el reloj, los recordatorios, el permiso de notificaciones, las preferencias y la casa en memoria.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_agendar_visita.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/hoja_con_quien_arnes.dart' show ObservadorDeRutas;
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';

/// Un `agendar` que le llegó al repositorio.
typedef AgendaRecibida = ({Agenda agenda, NotaDeCampo? nota});

/// [AgendaRepository] que solo sabe agendar: registra lo que recibe, falla cuando el test lo dice,
/// espera cuando hay [compuerta] y es idempotente por `id` (como el real).
final class AgendaRepositorioQueAgenda implements AgendaRepository {
  /// Cada [agendar] toma el siguiente de [fallas] (`null` o sin más: éxito).
  final fallas = <Failure?>[];

  /// Si no es `null`, [agendar] espera a que se complete (un guardado «en curso»).
  Completer<void>? compuerta;

  /// Si no es `null`, el próximo [agendar] lanza esto en vez de devolver un `Either`.
  Object? lanzar;

  final recibidas = <AgendaRecibida>[];
  final guardadas = <String, Agenda>{};

  /// Cuántas agendas distintas quedaron guardadas.
  int get cuantasQuedaron => guardadas.length;

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) async {
    recibidas.add((agenda: agenda, nota: nota));
    await compuerta?.future;
    final error = lanzar;
    if (error != null) {
      lanzar = null;
      throw error;
    }
    final falla = fallas.isEmpty ? null : fallas.removeAt(0);
    if (falla != null) return Left(falla);
    return Right(guardadas.putIfAbsent(agenda.id, () => agenda));
  }

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) =>
      throw UnimplementedError();

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

/// [EspacioRepository] cuya lectura de la casa espera a [compuerta].
final class EspacioRepositorioLento implements EspacioRepository {
  EspacioRepositorioLento(this.contexto, this.compuerta);

  final EspacioConUbicacion? contexto;
  final Completer<void> compuerta;

  /// Cuántas veces se leyó la casa.
  var lecturas = 0;

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) async {
    lecturas += 1;
    await compuerta.future;
    return Right(contexto);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// La casa del canvas de 23A·01: «Mataojo 2044 · Depto 3B».
EspacioConUbicacion casaMataojo({String? depto = '3B'}) =>
    (espacio: espacioDePersonas(numeroDepto: depto, piso: null), ubicacion: ubicacionDePersonas());

/// «María Fernández», con el vínculo `ep-p1` con el espacio `esp-1`.
PersonaDelEspacio get mariaFernandez => clienteDePersonas('p1', 'María', apellido: 'Fernández');

/// El día del canvas: viernes 23/10/2026, 14:35 (hora local del test).
DateTime ahoraDelCanvas() => DateTime(2026, 10, 23, 14, 35);

class ArnesAgendar {
  ArnesAgendar({
    required this.repo,
    required this.telefono,
    required this.rutas,
    required this.ahora,
  });

  final AgendaRepositorioQueAgenda repo;
  final Telefono telefono;
  final ObservadorDeRutas rutas;

  RecordatoriosEnMemoria get recordatorios => telefono.recordatorios;
  PermisoNotificacionesSistemaEnMemoria get sistema => telefono.sistema;
  PreferenciasRecordatoriosRepositoryEnMemoria get preferencias => telefono.preferencias;

  /// El reloj de la pantalla; se mueve cambiando este campo.
  DateTime ahora;

  /// Cada vez que `FlujoAgendarVisita.abrir` terminó: lo que devolvió.
  final resultados = <bool>[];
  Object? errorAlAbrir;
}

/// Monta una pantalla con el botón «abrir agenda» y, si [abrir], lo toca.
Future<ArnesAgendar> montarAgendar(
  WidgetTester tester, {
  AgendaRepositorioQueAgenda? repo,
  List<PersonaDelEspacio>? personas,
  EspacioConUbicacion? casa,
  bool sinCasa = false,
  Failure? fallaDeCasa,
  Completer<void>? casaDemorada,
  String? espacioPersonaId = 'ep-p1',
  String? colportorId = 'col-1',
  TipoAgenda tipo = TipoAgenda.entrevista,
  DateTime? ahora,
  bool permisoConcedido = true,
  EstadoSistemaNotificaciones estadoSistema = EstadoSistemaNotificaciones.activadas,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final arnes = ArnesAgendar(
    repo: repo ?? AgendaRepositorioQueAgenda(),
    telefono: Telefono(estado: estadoSistema)..recordatorios.permisoConcedido = permisoConcedido,
    rutas: ObservadorDeRutas(),
    ahora: ahora ?? ahoraDelCanvas(),
  );
  var n = 0;
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final personasRepo = PersonaRepositorioFalso()..sembrar(personas ?? [mariaFernandez]);
  final lugar = sinCasa ? null : (casa ?? casaMataojo());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(arnes.repo),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(() => arnes.ahora),
        ...arnes.telefono.overrides,
        personaRepositoryProvider.overrideWithValue(personasRepo),
        espacioRepositoryProvider.overrideWithValue(
          casaDemorada != null
              ? EspacioRepositorioLento(lugar, casaDemorada)
              : EspacioRepositorioParaPersonas(lugar, falla: fallaDeCasa),
        ),
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
                onPressed: () async {
                  try {
                    final r = await FlujoAgendarVisita.abrir(
                      context,
                      espacioId: 'esp-1',
                      espacioPersonaId: espacioPersonaId,
                      colportorId: colportorId,
                      tipo: tipo,
                    );
                    arnes.resultados.add(r);
                  } on Object catch (e) {
                    arnes.errorAlAbrir = e;
                  }
                },
                child: const Text('abrir agenda'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirAgendar(tester);
  return arnes;
}

/// Toca el botón de arranque y deja correr la apertura de la pantalla.
Future<void> abrirAgendar(WidgetTester tester) async {
  await tester.tap(find.text('abrir agenda'));
  await asentarAgendar(tester);
}

/// Deja correr los fotogramas que hacen falta (los providers contestan en el turno siguiente y las
/// rutas se animan) sin esperar a los indicadores que giran para siempre.
Future<void> asentarAgendar(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Una agenda de ejemplo para sembrar el repositorio o comparar.
Agenda agendaDeEjemplo({String id = 'a-0'}) => Agenda(
  id: id,
  espacioId: 'esp-1',
  tipo: TipoAgenda.entrevista,
  fechaProgramada: DateTime.utc(2026, 10, 24, 13),
  colportorId: 'col-1',
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
    createdBy: 'col-1',
  ),
);
