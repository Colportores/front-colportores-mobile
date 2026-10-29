// Arnés de los tests de las pantallas de cuotas (vista 30 A, HU-COB-004, #166): un plan en memoria
// con las reglas del real y la pantalla montada con un botón que la abre. Las tres pantallas
// (armar el plan, la lista de cuotas y modificar) se prueban con el mismo.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/pages/cuotas_de_la_venta_page.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/pages/modificar_cuotas_page.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/pages/plan_de_cuotas_page.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'persona_falsos.dart';
import 'plan_de_cuotas_arnes.dart';

/// El sábado 26/10/2026 a las 9:00 en Montevideo: el hoy del canvas de la vista 30.
final hoyDeLasCuotas = DateTime(2026, 10, 26, 9);

enum PantallaDeCuotas { plan, lista, modificar }

class ArnesCuotas {
  ArnesCuotas({required this.plan, required this.agendas, required this.telefono});

  final PlanDeCuotasEnMemoria plan;
  final AgendaRepositorioQueAgenda agendas;
  final Telefono telefono;
  DateTime ahora = hoyDeLasCuotas;

  /// Los ids de cita que se generaron, en orden.
  final ids = <String>[];

  /// Lo que devolvió la pantalla cada vez que se cerró.
  final resultados = <bool>[];
}

/// Monta [pantalla] con un botón «abrir cuotas» y, si [abrir], lo toca.
Future<ArnesCuotas> montarCuotas(
  WidgetTester tester, {
  PantallaDeCuotas pantalla = PantallaDeCuotas.plan,
  PlanDeCuotasEnMemoria? plan,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  final arnes = ArnesCuotas(
    plan: plan ?? PlanDeCuotasEnMemoria(),
    agendas: AgendaRepositorioQueAgenda(),
    telefono: Telefono(),
  );
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(arnes.plan.cerrar);
  final personasRepo = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planDeCuotasRepositoryProvider.overrideWithValue(arnes.plan),
        generadorIdCobroProvider.overrideWithValue(() {
          final id = 'cita-${arnes.ids.length + 1}';
          arnes.ids.add(id);
          return id;
        }),
        relojCobroProvider.overrideWithValue(() => arnes.ahora),
        agendaRepositoryProvider.overrideWithValue(arnes.agendas),
        ...arnes.telefono.overrides,
        personaRepositoryProvider.overrideWithValue(personasRepo),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaMataojo())),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final r = switch (pantalla) {
                    PantallaDeCuotas.plan => await PlanDeCuotasPage.abrir(
                      context,
                      ventaId: 'v-1',
                      colportorId: 'col-1',
                      espacioId: 'esp-1',
                      espacioPersonaId: 'ep-p1',
                    ),
                    PantallaDeCuotas.lista => await CuotasDeLaVentaPage.abrir(
                      context,
                      ventaId: 'v-1',
                      colportorId: 'col-1',
                      espacioId: 'esp-1',
                      espacioPersonaId: 'ep-p1',
                    ),
                    PantallaDeCuotas.modificar => await ModificarCuotasPage.abrir(
                      context,
                      ventaId: 'v-1',
                      espacioId: 'esp-1',
                      espacioPersonaId: 'ep-p1',
                    ),
                  };
                  arnes.resultados.add(r);
                },
                child: const Text('abrir cuotas'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirCuotas(tester);
  return arnes;
}

Future<void> abrirCuotas(WidgetTester tester) async {
  await tester.tap(find.text('abrir cuotas'));
  await asentarAgendar(tester);
}

final paginaPlan = find.byKey(const Key('cuotas_plan_pagina'));
final paginaLista = find.byKey(const Key('cuotas_lista_pagina'));
final paginaModificar = find.byKey(const Key('cuotas_modificar_pagina'));
final botonPrincipal = find.byKey(const Key('venta_cta'));
final volverDeCuotas = find.byKey(const Key('venta_atras'));

/// El campo de monto de la cuota en el lugar [i] (desde 0) del plan.
Finder campoDeCuota(int i) =>
    find.descendant(of: find.byKey(Key('cuotas_fila_$i')), matching: find.byType(TextField));

/// El campo de monto de la cuota número [n] (desde 1) en «Modificar cuotas».
Finder campoDeCuotaNumero(int n) => campoDeCuota(n);

/// El botón principal de abajo, como `FilledButton`.
FilledButton elBotonPrincipal(WidgetTester tester) => tester.widget<FilledButton>(botonPrincipal);

/// Trae [f] a la vista: la lista es perezosa y con letra grande el widget puede no estar armado.
Future<void> traerCuotaAlAlcance(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 100, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
}

Future<void> escribirCuota(WidgetTester tester, int i, String texto) async {
  final campo = campoDeCuota(i);
  await traerCuotaAlAlcance(tester, campo);
  await tester.enterText(campo, texto);
  await asentarAgendar(tester, 3);
}

Future<void> tocarEnCuotas(WidgetTester tester, Finder f) async {
  await traerCuotaAlAlcance(tester, f);
  await tester.tap(f.first);
  await asentarAgendar(tester);
}

/// Lo que dice el campo de monto del lugar [i].
String textoDeCuota(WidgetTester tester, int i) =>
    tester.widget<TextField>(campoDeCuota(i)).controller!.text;
