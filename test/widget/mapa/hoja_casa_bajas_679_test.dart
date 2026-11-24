// #679 ítem 5a (decisión §2 del 10/11): la pestaña «Personas» de la hoja de la casa (vista 39, C·02)
// con «Mostrar bajas» (32D·04) y «Reactivar» (32D·05), las mismas piezas que la ficha del depto
// (`bajas_de_personas.dart`). Casos límite: sin bajas, doble toque, falla a mitad de reactivar, casa de
// baja (solo ver), error al leer, lista larga, texto al 200 % y volver a abrir la hoja.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/bajas_de_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;
import '../../helpers/persona_falsos.dart';
import 'hoja_con_quien_arnes.dart' show SaldosFalsos;

/// Pedro activo en la casa (el contexto de la hoja).
final _contexto = ContextoDeLaCasa(espacioId: 'esp-1', personas: [pedroGomez]);

/// Pedro activo y María dada de baja el 22/10, que debe $ 1.200.
PersonaRepositorioFalso _conMariaDeBaja() =>
    PersonaRepositorioFalso()
      ..sembrar([pedroGomez, clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández')]);

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _montar(
  WidgetTester tester, {
  PersonaRepository? repo,
  ItemListaUbicacion? item,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        ...overridesHojaCasa(lectura: (_) => Stream.value(_contexto)),
        personaRepositoryProvider.overrideWithValue(repo ?? _conMariaDeBaja()),
        saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'p2': 120000})),
        fichaDePersonaDesdeLaCasaProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HojaCasa(
              item: item ?? itemDeLaHoja(),
              ahora: ahoraLista,
              alCerrar: () {},
              arriba: true,
              colportorId: 'col-1',
            ),
          ),
        ),
      ),
    ),
  );
  await _asentar(tester);
}

final _mostrar = find.byKey(ClavesBajasDePersonas.mostrar);
final _reactivarMaria = find.byKey(ClavesBajasDePersonas.reactivar('p2'));
final _aviso = find.byKey(ClavesHojaCasa.personaGuardada);

Future<void> _mostrarLasBajas(WidgetTester tester) async {
  await tester.ensureVisible(_mostrar);
  await tester.tap(_mostrar);
  await _asentar(tester);
}

void main() {
  testWidgets('sin personas dadas de baja no aparece «Mostrar bajas»', (tester) async {
    await _montar(tester, repo: PersonaRepositorioFalso()..sembrar([pedroGomez]));

    expect(find.text('Pedro Gómez'), findsOneWidget);
    expect(_mostrar, findsNothing);
    expect(find.text('Mostrar bajas'), findsNothing);
  });

  testWidgets('con una baja, «Mostrar bajas» va apagado debajo de «+ Agregar persona»; prendido '
      'muestra a María en gris con la fecha, el saldo y «Reactivar»', (tester) async {
    await _montar(tester);

    expect(tester.widget<SwitchListTile>(_mostrar).value, isFalse);
    expect(find.text('María Fernández'), findsNothing);
    expect(
      tester.getTopLeft(_mostrar).dy,
      greaterThan(tester.getTopLeft(find.byKey(ClavesHojaCasa.agregarPersona)).dy),
    );

    await _mostrarLasBajas(tester);

    expect(find.text('María Fernández'), findsOneWidget);
    expect(find.text('Baja el 22/10 · saldo \$\u00a01.200'), findsOneWidget);
    expect(find.text('MF'), findsOneWidget);
    expect(_reactivarMaria, findsOneWidget);
  });

  testWidgets('«Reactivar» la reactiva y avisa dentro de la hoja «Reactivamos a María.»', (
    tester,
  ) async {
    final repo = _conMariaDeBaja();
    await _montar(tester, repo: repo);
    await _mostrarLasBajas(tester);

    await tester.tap(_reactivarMaria);
    await _asentar(tester);

    expect(repo.reactivacionesRecibidas, ['p2']);
    expect(
      find.descendant(of: _aviso, matching: find.text('Reactivamos a María.')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(_reactivarMaria, findsNothing, reason: 'ya no está entre las bajas');
    expect(_mostrar, findsNothing, reason: 'sin bajas el interruptor se va');
  });

  testWidgets('doble toque en «Reactivar»: una sola reactivación', (tester) async {
    final repo = _conMariaDeBaja()..compuertaReactivar = Completer<void>();
    await _montar(tester, repo: repo);
    await _mostrarLasBajas(tester);

    await tester.tap(_reactivarMaria);
    await tester.pump();
    // Mientras se escribe, «Reactivar» deja lugar a la ruedita: el segundo toque cae en la fila.
    expect(_reactivarMaria, findsNothing);
    await tester.tap(find.byKey(ClavesBajasDePersonas.fila('p2')), warnIfMissed: false);
    repo.compuertaReactivar!.complete();
    await _asentar(tester);

    expect(repo.reactivacionesRecibidas, ['p2']);
  });

  testWidgets('falla a mitad de reactivar: el aviso lo dice en la hoja, nada queda trabado y '
      'reintentar la reactiva', (tester) async {
    final repo = _conMariaDeBaja()..resultadosReactivar.add(const FailureInesperado());
    await _montar(tester, repo: repo);
    await _mostrarLasBajas(tester);

    await tester.tap(_reactivarMaria);
    await _asentar(tester);

    expect(find.text('No pudimos reactivar a María. Probá de nuevo.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(_reactivarMaria, findsOneWidget, reason: 'el botón vuelve a poder tocarse');

    await tester.tap(_reactivarMaria);
    await _asentar(tester);

    expect(repo.reactivacionesRecibidas, ['p2', 'p2']);
    expect(find.text('No pudimos reactivar a María. Probá de nuevo.'), findsNothing);
    expect(find.text('Reactivamos a María.'), findsOneWidget);
  });

  testWidgets('con la casa dada de baja las bajas se ven y no se reactivan', (tester) async {
    await _montar(tester, item: itemDeLaHoja(baja: DateTime.utc(2026, 10, 1)));

    await _mostrarLasBajas(tester);

    expect(find.text('María Fernández'), findsOneWidget);
    expect(_reactivarMaria, findsNothing);
    expect(find.text('Reactivar'), findsNothing);
  });

  testWidgets('si las bajas no se pueden leer, lo dice con «Reintentar»', (tester) async {
    await _montar(tester, repo: PersonaRepositorioQueNoLee());

    expect(find.text('No pudimos leer las bajas en tu teléfono.'), findsOneWidget);
    expect(find.byKey(ClavesBajasDePersonas.error), findsOneWidget);
  });

  testWidgets('con 30 bajas la hoja se desplaza hasta la última', (tester) async {
    final repo = PersonaRepositorioFalso()
      ..sembrar([
        pedroGomez,
        for (var i = 0; i < 30; i++) clienteDeBajaDePersonas('b$i', 'Baja$i', minutos: i),
      ]);
    await _montar(tester, repo: repo);
    await _mostrarLasBajas(tester);

    final ultima = find.byKey(ClavesBajasDePersonas.fila('b29'));
    await tester.ensureVisible(ultima);
    await tester.pump();
    expect(ultima.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 320 × 640 con el texto al 200 % la baja y «Reactivar» entran sin desbordar', (
    tester,
  ) async {
    await _montar(tester, escala: 2, tamano: const Size(320, 640));
    await _mostrarLasBajas(tester);

    await tester.ensureVisible(_reactivarMaria);
    await tester.pump();
    expect(tester.getRect(_reactivarMaria).right, lessThanOrEqualTo(320));
    expect(tester.getRect(find.text('María Fernández')).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cerrar la hoja y volver a abrirla: «Mostrar bajas» vuelve apagado', (tester) async {
    await _montar(tester);
    await _mostrarLasBajas(tester);
    expect(find.text('María Fernández'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _montar(tester);

    expect(tester.widget<SwitchListTile>(_mostrar).value, isFalse);
    expect(find.text('María Fernández'), findsNothing);
  });
}
