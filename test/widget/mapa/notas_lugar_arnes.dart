// Arnés de los tests de las notas de un lugar (vista 39, C·05): monta la pestaña Notas de la hoja
// arriba (sola, o dentro de la `HojaCasa` real con el enganche de `main.dart`) con los dobles de
// `nota_ubicacion_falsos.dart`.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_notas_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/nota_ubicacion_falsos.dart';

/// «Hoy» de los tests: el 22/10/2026 a las 15:00, hora local.
final ahoraDeLugar = DateTime(2026, 10, 22, 15);

/// Deja correr los fotogramas que hacen falta sin esperar a los indicadores que giran para siempre.
Future<void> asentarLugar(WidgetTester tester, [int veces = 12]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Las dos notas del canvas C·05: una de hoy a las 14:20 y una del 05/10.
List<NotaUbicacion> notasDelLugarDelCanvas() => [
  notaDeLugar(
    'hoy',
    'El portón verde no cierra: tocar fuerte.',
    creada: DateTime(2026, 10, 22, 14, 20),
  ),
  notaDeLugar(
    'vieja',
    'Perro en el patio, avisar desde la vereda.',
    creada: DateTime(2026, 10, 5, 9),
  ),
];

List<Override> overridesLugar(
  NotaUbicacionRepositorioFalso repo, {
  List<Override> otros = const [],
}) {
  var contador = 0;
  return [
    notaUbicacionRepositoryProvider.overrideWithValue(repo),
    relojPersonaProvider.overrideWithValue(() => ahoraDeLugar),
    generadorIdPersonaProvider.overrideWithValue(() => 'lugar-nueva-${++contador}'),
    ...otros,
  ];
}

void fijarTamanoLugar(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Monta la pestaña Notas dentro de un `Scaffold` desplazable, como la hoja arriba.
Future<void> montarPestanaLugar(
  WidgetTester tester, {
  NotaUbicacionRepositorioFalso? repo,
  String? colportorId = 'col-1',
  bool soloLectura = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  List<Override> otros = const [],
  List<NavigatorObserver> observadores = const [],
}) async {
  fijarTamanoLugar(tester, tamano);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesLugar(repo ?? NotaUbicacionRepositorioFalso(), otros: otros),
      child: MaterialApp(
        theme: temaClaro(),
        navigatorObservers: observadores,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: PestanaNotasDeLaCasa(
              ubicacionId: 'ubi-1',
              colportorId: colportorId,
              soloLectura: soloLectura,
            ),
          ),
        ),
      ),
    ),
  );
  await asentarLugar(tester);
}

/// Abre la hoja de opciones de la nota [id].
Future<void> abrirOpcionesLugar(WidgetTester tester, String id) async {
  final tarjeta = find.byKey(ClavesNotasDelLugar.nota(id));
  await tester.ensureVisible(tarjeta);
  await tester.tap(tarjeta);
  await asentarLugar(tester);
}

/// Borra la nota [id] por la hoja de opciones, como lo hace la persona.
Future<void> borrarPorMenuLugar(WidgetTester tester, String id) async {
  await abrirOpcionesLugar(tester, id);
  await tester.tap(find.byKey(ClavesNotas.botonBorrar));
  await asentarLugar(tester);
}

/// Escribe [texto] en el formulario y toca «Guardar nota».
Future<void> escribirYGuardarLugar(WidgetTester tester, String texto) async {
  await tester.enterText(find.byKey(ClavesNotas.campo), texto);
  await tester.pump();
  await tester.tap(find.text('Guardar nota'));
  await asentarLugar(tester);
}

/// Cuenta las rutas que se empujan (sin contar la raíz): para probar que un doble toque abre una sola.
final class ContadorDeRutas extends NavigatorObserver {
  var empujadas = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) empujadas += 1;
  }
}
