// Arnés de la quinta ronda de QA del paso «¿Con quién?» (#449, PR #463, punta 1ce61fc): el modo
// **programar** (C·07 al tocar «Programar entrevista»), que llegó a la rama con el merge de develop
// (#474): título «¿Con quién es la entrevista?», «Seguir» y «Todavía no sé con quién».
//
// Las capturas salen con `capturar449` (solo con `--dart-define=QA_CAPTURAS=true`).
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/eleccion_de_cita.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/saldos_de_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/persona_falsos.dart';
import '../widget/mapa/hoja_con_quien_arnes.dart';
import '../widget/mapa/personas_arnes.dart';
import 'qa_vista39_449_arnes.dart';

/// Lo que la pantalla de arranque recibió del paso al programar.
final class ResultadoProgramar449 {
  EleccionDeCita? eleccion;

  /// Cuántas veces terminó el paso (con o sin elección).
  var cierres = 0;

  final rutas = ObservadorDeRutas();

  /// Las rutas abiertas encima de la pantalla de arranque: la hoja y, si hay, el alta.
  int get abiertas => rutas.aperturas - 1 - rutas.cierres;
}

/// Monta el arnés con un botón «abrir paso» que llama a `mostrarHojaConQuienParaProgramar`.
Future<ResultadoProgramar449> montarProgramar449(
  WidgetTester tester, {
  PersonaRepository? repo,
  SaldosDePersonas? saldos,
  Size tamano = t412x915,
  double escala = 1,
  bool abrir = true,
}) async {
  final resultado = ResultadoProgramar449();
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewInsets();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: raiz449,
      child: ProviderScope(
        overrides: [
          personaRepositoryProvider.overrideWithValue(repo ?? PersonaRepositorioFalso()),
          espacioRepositoryProvider.overrideWithValue(
            EspacioRepositorioParaPersonas(contextoActivo()),
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
                    final e = await mostrarHojaConQuienParaProgramar(
                      context,
                      espacioId: 'esp-1',
                      colportorId: 'col-1',
                    );
                    resultado
                      ..eleccion = e
                      ..cierres += 1;
                  },
                  child: const Text('abrir paso'),
                ),
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

Finder get botonSeguir449 => find.widgetWithText(FilledButton, 'Seguir');
Finder get filaTodaviaNoSe449 => find.byKey(ClavesConQuien.todaviaNoSe);

/// Lo mismo que [Estado449] pero al programar.
enum EstadoProgramar449 { dos, treinta, cargando, errorDeLectura }

Future<ResultadoProgramar449> llegarAProgramar449(
  WidgetTester tester,
  EstadoProgramar449 estado, {
  Size tamano = t412x915,
  double escala = 1,
}) => switch (estado) {
  EstadoProgramar449.dos => montarProgramar449(
    tester,
    repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(2)),
    saldos: SaldosFalsos({'p0': 120000}),
    tamano: tamano,
    escala: escala,
  ),
  EstadoProgramar449.treinta => montarProgramar449(
    tester,
    repo: PersonaRepositorioFalso()
      ..sembrar([
        for (var i = 0; i < 30; i++)
          clienteDePersonas(
            'm$i',
            'María de los Ángeles ${'Nombre' * 3}$i',
            apellido: 'Fernández de la Peña y Gómez-Ibáñez',
            minutos: i,
          ),
      ]),
    tamano: tamano,
    escala: escala,
  ),
  EstadoProgramar449.cargando => montarProgramar449(
    tester,
    repo: PersonaRepositorioTardio(),
    tamano: tamano,
    escala: escala,
  ),
  EstadoProgramar449.errorDeLectura => montarProgramar449(
    tester,
    repo: PersonaRepositorioQueFallaN(99),
    tamano: tamano,
    escala: escala,
  ),
};
