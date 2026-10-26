// Arnés de los tests de las pantallas de personas (HU-UBI-008: alta 32A y clientes del depto 11·04):
// monta una pantalla que abre la que se prueba, con los dobles de `persona_falsos.dart`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/espacio_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_otra_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/personas_del_espacio_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';

/// El contexto de un espacio de edificio, activo, como lo lee la pantalla.
EspacioConUbicacion contextoActivo({
  String? numeroDepto = '101',
  String? piso = '1',
  DateTime? espacioDeBaja,
}) => (
  espacio: espacioDePersonas(numeroDepto: numeroDepto, piso: piso, deletedAt: espacioDeBaja),
  ubicacion: ubicacionDePersonas(),
);

/// Deja correr los fotogramas que hacen falta (los providers contestan en el turno siguiente y las
/// rutas se animan) sin esperar a los indicadores que giran para siempre.
Future<void> asentar(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Lo que la pantalla de arranque recibió al volver del alta.
final class ResultadoAlta {
  Persona? persona;
  var cierres = 0;
}

/// Monta una pantalla con un botón «abrir alta» que abre [AltaPersonaPage], y la abre.
Future<ResultadoAlta> montarAlta(
  WidgetTester tester, {
  PersonaRepository? repo,
  EspacioConUbicacion? contexto,
  Failure? fallaDeContexto,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final resultado = ResultadoAlta();
  _fijarTamano(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        repo ?? PersonaRepositorioFalso(),
        contexto ?? contextoActivo(),
        falla: fallaDeContexto,
      ),
      child: _App(
        escala: escala,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final p = await AltaPersonaPage.abrir(
                    context,
                    espacioId: 'esp-1',
                    colportorId: 'col-1',
                  );
                  resultado
                    ..persona = p
                    ..cierres += 1;
                },
                child: const Text('abrir alta'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('abrir alta'));
    await asentar(tester);
  }
  return resultado;
}

/// Lo que la pantalla de arranque recibió al volver de la edición de una persona.
final class ResultadoEdicion {
  ResultadoEdicionPersona? resultado;
  var cierres = 0;
}

/// La hora de los tests de la edición: la que el caso de uso le pasa al repositorio.
final relojDeEdicion = DateTime.utc(2026, 10, 26, 12);

/// Un criterio de «¿es otra persona?» que contesta siempre lo mismo (o lo que diga [decide]).
final class CriterioOtraPersonaFijo implements CriterioOtraPersona {
  CriterioOtraPersonaFijo({this.respuesta = true});

  bool respuesta;
  var consultas = 0;

  @override
  bool pareceOtraPersona(Persona antes, DatosDePersona despues) {
    consultas += 1;
    return respuesta;
  }
}

/// Monta una pantalla con un botón «abrir edición» que abre [ModificarPersonaPage] para `per-1`, y la
/// abre. `repo.contextos['per-1']` es la persona (por defecto, [contextoDeEdicion]).
Future<ResultadoEdicion> montarEdicion(
  WidgetTester tester, {
  PersonaRepositorioFalso? repo,
  CriterioOtraPersona? criterio,
  DateTime? ahora,
  EspacioConUbicacion? contexto,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final resultado = ResultadoEdicion();
  final repositorio = repo ?? PersonaRepositorioFalso();
  repositorio.contextos.putIfAbsent('per-1', contextoDeEdicion);
  _fijarTamano(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._overrides(repositorio, contexto ?? contextoActivo()),
        if (criterio != null) criterioOtraPersonaProvider.overrideWithValue(criterio),
        relojPersonaProvider.overrideWithValue(() => ahora ?? relojDeEdicion),
      ],
      child: _App(
        escala: escala,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = await ModificarPersonaPage.abrir(context, personaId: 'per-1');
                  resultado
                    ..resultado = r
                    ..cierres += 1;
                },
                child: const Text('abrir edición'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('abrir edición'));
    await asentar(tester);
  }
  return resultado;
}

/// Monta [PersonasDelEspacioPage] sobre una pantalla de arranque (para poder volver atrás).
Future<void> montarClientes(
  WidgetTester tester, {
  PersonaRepository? repo,
  EspacioConUbicacion? contexto,
  bool contextoNulo = false,
  Failure? fallaDeContexto,
  double escala = 1,
  Size tamano = const Size(390, 844),
  List<Override> otrosOverrides = const [],
}) async {
  _fijarTamano(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        repo ?? PersonaRepositorioFalso(),
        contextoNulo ? null : (contexto ?? contextoActivo()),
        falla: fallaDeContexto,
      )..addAll(otrosOverrides),
      child: _App(
        escala: escala,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    PersonasDelEspacioPage.abrir(context, espacioId: 'esp-1', colportorId: 'col-1'),
                child: const Text('abrir clientes'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir clientes'));
  await asentar(tester);
}

void _fijarTamano(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<Override> _overrides(
  PersonaRepository repo,
  EspacioConUbicacion? contexto, {
  Failure? falla,
}) => [
  personaRepositoryProvider.overrideWithValue(repo),
  espacioRepositoryProvider.overrideWithValue(
    EspacioRepositorioParaPersonas(contexto, falla: falla),
  ),
];

class _App extends StatelessWidget {
  const _App({required this.escala, required this.home});

  final double escala;
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: temaClaro(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
      child: child!,
    ),
    home: home,
  );
}

/// Repositorio cuya lista de clientes nunca llega (el estado «cargando»).
final class PersonaRepositorioCargando extends PersonaRepositorioFalso {
  final _nunca = StreamController<List<PersonaDelEspacio>>();

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) => _nunca.stream;
}

/// Repositorio cuya primera lectura falla y la segunda sale bien (el «Reintentar» de la lista).
final class PersonaRepositorioQueFallaUnaVez extends PersonaRepositorioFalso {
  var lecturas = 0;

  @override
  Stream<List<PersonaDelEspacio>> observarDelEspacio(String espacioId) {
    lecturas += 1;
    return lecturas == 1
        ? Stream.error(StateError('no se pudo leer'))
        : super.observarDelEspacio(espacioId);
  }
}
