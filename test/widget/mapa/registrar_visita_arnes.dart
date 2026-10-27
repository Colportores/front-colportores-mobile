// Arnés de los tests de «Registrar visita» (vista 39, #411): monta una pantalla con un botón que abre
// `FlujoRegistrarVisita.abrir` y recoge lo que devuelve, con los dobles de la agenda y de las personas.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/persona_falsos.dart';
import 'hoja_con_quien_arnes.dart';
import 'personas_arnes.dart';

/// Lo que recibió el hook de «Programar entrevista», «Entrevista dada» o «Cobranza».
final class EnganchesRecibidos {
  final citas = <ContextoDeCita>[];
  final entrevistas = <ContextoDeEntrevista>[];
  final cobros = <ContextoDeCobro>[];

  /// Lo que contestan los hooks (`true` = se hizo). Si [compuerta] no es `null` esperan a que se complete.
  var citaHecha = true;
  var entrevistaHecha = true;
  var cobroHecho = true;
  Object? falla;
  Completer<void>? compuerta;
}

final class ArnesQuePaso {
  ArnesQuePaso(this.repo, this.enganches, this.rutas);

  final AgendaRepositorioFalso repo;
  final EnganchesRecibidos enganches;
  final ObservadorDeRutas rutas;

  /// Cada vez que `abrir` terminó: lo que devolvió.
  final resultados = <bool>[];
  Object? errorAlAbrir;
}

/// La casa del canvas de C·06 y R·01 (la dirección de los avisos): «Grecia 3307».
EspacioConUbicacion casaGrecia({bool baja = false}) => (
  espacio: espacioDePersonas(numeroDepto: null, piso: null),
  ubicacion: ubicacionDePersonas(
    tipo: TipoUbicacion.casa,
    calle: 'Grecia',
    numero: '3307',
    deletedAt: baja ? DateTime.utc(2026, 10, 24) : null,
  ),
);

/// Monta la pantalla con el botón «registrar visita» y, si [abrir], lo toca.
///
/// [personas] siembra las personas de la casa; [saldos] lo que deben; [programar], [entrevistaDada] y
/// [cobrar] activan los hooks de esas opciones (sin ellos la opción no se ofrece). [jornadas] son las
/// jornadas locales de la colportora (sin ellas, ninguna abierta).
Future<ArnesQuePaso> montarQuePaso(
  WidgetTester tester, {
  AgendaRepositorioFalso? repo,
  List<PersonaDelEspacio> personas = const [],
  Map<String, int> saldos = const {},
  EspacioConUbicacion? casa,
  bool sinCasa = false,
  Failure? fallaDeCasa,
  bool programar = false,
  bool entrevistaDada = false,
  bool cobrar = false,
  JornadaLocalDataSource? jornadas,
  String? espacioId = 'esp-1',
  String? colportorId = 'col-1',
  double escala = 1,
  bool lector = false,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final agenda = repo ?? AgendaRepositorioFalso();
  final enganches = EnganchesRecibidos();
  final rutas = ObservadorDeRutas();
  final arnes = ArnesQuePaso(agenda, enganches, rutas);
  var n = 0;
  var minutos = 0;

  Future<Object?> esperar(Object? valor) async {
    await enganches.compuerta?.future;
    if (enganches.falla != null) throw enganches.falla!;
    return valor;
  }

  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final personasRepo = PersonaRepositorioFalso()..sembrar(personas);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agendaRepositoryProvider.overrideWithValue(agenda),
        generadorIdVisitaProvider.overrideWithValue(() => 'id-${++n}'),
        relojVisitaProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 25, 15).add(Duration(minutes: minutos++)),
        ),
        personaRepositoryProvider.overrideWithValue(personasRepo),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(
            sinCasa ? null : (casa ?? casaGrecia()),
            falla: fallaDeCasa,
          ),
        ),
        saldosDePersonasProvider.overrideWithValue(SaldosFalsos(saldos)),
        jornadaLocalDataSourceProvider.overrideWithValue(
          jornadas ?? JornadaLocalDataSourceEnMemoria(),
        ),
        if (programar)
          programarEntrevistaDesdeLaCasaProvider.overrideWithValue((c) async {
            enganches.citas.add(c);
            return esperar(enganches.citaHecha);
          }),
        if (entrevistaDada)
          entrevistaDadaDesdeLaCasaProvider.overrideWithValue((c) async {
            enganches.entrevistas.add(c);
            return esperar(enganches.entrevistaHecha);
          }),
        if (cobrar)
          cobrarDesdeLaCasaProvider.overrideWithValue((c) async {
            enganches.cobros.add(c);
            return esperar(enganches.cobroHecho);
          }),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: [rutas],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  try {
                    final r = await FlujoRegistrarVisita.abrir(context, (
                      ubicacionId: 'ub-1',
                      espacioId: espacioId,
                    ), colportorId: colportorId);
                    arnes.resultados.add(r);
                  } on Object catch (e) {
                    arnes.errorAlAbrir = e;
                  }
                },
                child: const Text('registrar visita'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirQuePaso(tester);
  return arnes;
}

/// Toca el botón de arranque y deja correr la apertura de la hoja.
Future<void> abrirQuePaso(WidgetTester tester) async {
  await tester.tap(find.text('registrar visita'));
  await asentar(tester);
}

/// El renglón de [o] en «¿Qué pasó?».
Finder renglon(OpcionQuePaso o) => find.byKey(ClavesQuePaso.opcion(o));

/// Toca el renglón de [o] y deja correr.
Future<void> elegir(WidgetTester tester, OpcionQuePaso o) async {
  await tester.ensureVisible(renglon(o));
  await tester.pump();
  await tester.tap(renglon(o));
  await asentar(tester);
}
