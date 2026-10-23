// Arnés de los tests del paso «¿Con quién?» de la vista 39 (R·04 y C·07): monta una pantalla con un
// botón que abre `mostrarHojaConQuien` y recoge lo que devuelve, con los dobles de `persona_falsos.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_de_la_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/saldos_de_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart';

/// Cuenta las rutas que se abren y se cierran: un doble toque que abre o cierra dos veces se ve acá
/// aunque la segunda ruta quede tapada por la primera.
final class ObservadorDeRutas extends NavigatorObserver {
  var aperturas = 0;
  var cierres = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => aperturas += 1;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => cierres += 1;
}

/// Lo que la pantalla de arranque recibió del paso.
final class ResultadoConQuien {
  PersonaDeLaEntrevista? elegida;

  /// Cuántas veces terminó el paso (con o sin persona).
  var cierres = 0;

  final rutas = ObservadorDeRutas();

  /// Las rutas abiertas encima de la pantalla de arranque: la hoja y, si hay, el alta.
  int get abiertas => rutas.aperturas - 1 - rutas.cierres;
}

/// [SaldosDePersonas] con lo que se le pida; [falla] lo hace lanzar.
final class SaldosFalsos implements SaldosDePersonas {
  SaldosFalsos(this.saldos, {this.falla = false});

  final Map<String, int> saldos;
  final bool falla;

  @override
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds) async {
    if (falla) throw StateError('no se pudo leer el saldo');
    return saldos;
  }
}

/// Repositorio cuya lista llega cuando el test lo dice (tarde, después de la lectura previa).
final class PersonaRepositorioTardio extends PersonaRepositorioFalso {
  final _llegada = StreamController<List<PersonaDelEspacio>>.broadcast();

  void emitir(List<PersonaDelEspacio> personas) => _llegada.add(personas);

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) => _llegada.stream;
}

/// Repositorio cuyas primeras [fallas] lecturas fallan y las siguientes salen bien.
final class PersonaRepositorioQueFallaN extends PersonaRepositorioFalso {
  PersonaRepositorioQueFallaN(this.fallas);

  final int fallas;
  var lecturas = 0;

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) {
    lecturas += 1;
    return lecturas <= fallas
        ? Stream.error(StateError('no se pudo leer'))
        : super.observarDelEspacio(espacioId);
  }
}

/// El personal de una casa con [cantidad] personas, de la más vieja a la más nueva.
List<PersonaDelEspacio> personasDeLaCasa(int cantidad) => [
  for (var i = 0; i < cantidad; i++)
    clienteDePersonas('p$i', 'Persona$i', apellido: 'Gómez', minutos: i),
];

/// Monta una pantalla con un botón «abrir paso» y, si [abrir], lo toca y deja correr la apertura.
Future<ResultadoConQuien> montarConQuien(
  WidgetTester tester, {
  PersonaRepository? repo,
  EspacioConUbicacion? contexto,
  SaldosDePersonas? saldos,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final resultado = ResultadoConQuien();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personaRepositoryProvider.overrideWithValue(repo ?? PersonaRepositorioFalso()),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(contexto ?? contextoActivo()),
        ),
        saldosDePersonasProvider.overrideWithValue(saldos ?? SaldosFalsos(const {})),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: [resultado.rutas],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final e = await mostrarHojaConQuien(
                    context,
                    espacioId: 'esp-1',
                    colportorId: 'col-1',
                  );
                  resultado
                    ..elegida = e
                    ..cierres += 1;
                },
                child: const Text('abrir paso'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirPaso(tester);
  return resultado;
}

/// Toca «abrir paso» y deja correr la lectura previa (250 ms de espera tope) y la animación de la hoja.
Future<void> abrirPaso(WidgetTester tester) async {
  await tester.tap(find.text('abrir paso'));
  await tester.pump();
  await asentar(tester, 16);
}

/// Un [Failure] cualquiera para las altas que fallan.
const fallaDeGuardado = FailureInesperado(causa: 'x');
