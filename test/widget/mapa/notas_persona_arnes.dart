// Arnés de los tests de las pantallas de notas de una persona (HU-UBI-012, vista 32E): monta una
// pantalla de arranque con un botón que abre la que se prueba, con los dobles de
// `nota_persona_falsos.dart`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/nota_persona_form_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/notas_de_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_persona_falsos.dart';

/// «Hoy» de los tests: el 22/10/2026 a las 15:00, hora local.
final ahoraDePrueba = DateTime(2026, 10, 22, 15);

/// Deja correr los fotogramas que hacen falta (los providers contestan en el turno siguiente y las
/// rutas se animan) sin esperar a los indicadores que giran para siempre.
Future<void> asentar(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Las dos notas del canvas 32E·01: una de hoy a las 14:20 y una del 05/10.
List<NotaPersona> notasDelCanvas() => [
  notaDePrueba(
    'hoy',
    'Pidió volver el sábado con el esposo. Le interesa Nuestros Hijos.',
    creada: DateTime(2026, 10, 22, 14, 20),
  ),
  notaDePrueba(
    'vieja',
    'Trabaja en la farmacia de Av. Italia de 9 a 13.',
    creada: DateTime(2026, 10, 5, 9),
  ),
];

/// Lo que el arranque recibió al volver del formulario.
final class ResultadoFormulario {
  NotaGuardada? guardada;
  var cierres = 0;
}

void fijarTamano(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

List<Override> overridesNotas(NotaPersonaRepositorioFalso repo, {List<Override> otros = const []}) {
  var contador = 0;
  return [
    notaPersonaRepositorioProviderOverride(repo),
    relojPersonaProvider.overrideWithValue(() => ahoraDePrueba),
    generadorIdPersonaProvider.overrideWithValue(() => 'nota-nueva-${++contador}'),
    ...otros,
  ];
}

Override notaPersonaRepositorioProviderOverride(NotaPersonaRepositorioFalso repo) =>
    notaPersonaRepositoryProvider.overrideWithValue(repo);

/// Monta un arranque con «abrir notas» y, si [abrir], lo toca: queda [NotasDePersonaPage] a la vista.
Future<void> montarNotas(
  WidgetTester tester, {
  NotaPersonaRepositorioFalso? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
  bool lector = false,
  List<Override> otros = const [],
}) async {
  fijarTamano(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesNotas(repo ?? NotaPersonaRepositorioFalso(), otros: otros),
      child: _App(
        escala: escala,
        lector: lector,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    NotasDePersonaPage.abrir(context, personaId: 'per-1', colportorId: 'col-1'),
                child: const Text('abrir notas'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.text('abrir notas'));
    await asentar(tester);
  }
}

/// Monta un arranque con «abrir formulario» y lo toca: queda [NotaPersonaFormPage] a la vista.
Future<ResultadoFormulario> montarFormulario(
  WidgetTester tester, {
  NotaPersonaRepositorioFalso? repo,
  NotaPersona? nota,
  double escala = 1,
  bool lector = false,
  Size tamano = const Size(390, 844),
}) async {
  final resultado = ResultadoFormulario();
  fijarTamano(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesNotas(repo ?? NotaPersonaRepositorioFalso()),
      child: _App(
        escala: escala,
        lector: lector,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final g = await NotaPersonaFormPage.abrir(
                    context,
                    personaId: 'per-1',
                    colportorId: 'col-1',
                    nota: nota,
                  );
                  resultado
                    ..guardada = g
                    ..cierres += 1;
                },
                child: const Text('abrir formulario'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir formulario'));
  await asentar(tester);
  return resultado;
}

/// Abre la hoja de opciones de la nota [id] (32E·03).
Future<void> abrirOpciones(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('nota_$id')));
  await asentar(tester);
}

/// Toca la opción [clave] de la hoja de opciones.
Future<void> elegirOpcion(WidgetTester tester, Key clave) async {
  await tester.tap(find.byKey(clave));
  await asentar(tester);
}

/// Borra la nota [id] por la hoja de opciones, como lo hace la persona.
Future<void> borrarPorMenu(WidgetTester tester, String id) async {
  await abrirOpciones(tester, id);
  await elegirOpcion(tester, ClavesNotas.botonBorrar);
}

class _App extends StatelessWidget {
  const _App({required this.escala, required this.lector, required this.home});

  final double escala;
  final bool lector;
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: temaClaro(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
      child: child!,
    ),
    home: home,
  );
}
