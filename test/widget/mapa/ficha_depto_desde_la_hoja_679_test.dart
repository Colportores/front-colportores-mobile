// #679 ítem 5a (decisión §2 del 10/11): la fila de un depto en la hoja del edificio (vista 11·01) y
// «Ver depto N ›» del repetido (11·03) abren la ficha del depto (11·04, `PersonasDelEspacioPage`), con
// «Mostrar bajas» de las personas (32D·04) y, en el encabezado, «Editar» con la edición y la baja del
// depto. Casos límite: doble toque, falla a mitad de reactivar, volver y reentrar, lista larga y texto
// al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/personas_del_espacio_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/bajas_de_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/persona_falsos.dart';
import 'hoja_con_quien_arnes.dart' show SaldosFalsos;
import 'hoja_espacios_arnes.dart';

/// El edificio del canvas: el depto 101 (`esp-1`, el de las personas de `persona_falsos.dart`) y el 102.
final _deptos = [espacioDe('esp-1', '101', piso: '1'), espacioDe('e-102', '102', piso: '1')];

/// Jorge activo y María dada de baja en el 101, que debe $ 1.200.
PersonaRepositorioFalso _conMariaDeBaja() => PersonaRepositorioFalso()
  ..sembrar([
    clienteDePersonas('p1', 'Jorge', apellido: 'Fernández'),
    clienteDeBajaDePersonas('p2', 'María', apellido: 'Fernández', minutos: 1),
  ]);

Future<MontajeHoja> _montar(
  WidgetTester tester, {
  PersonaRepositorioFalso? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) => montarHoja(
  tester,
  espacios: _deptos,
  escala: escala,
  tamano: tamano,
  extras: [
    personaRepositoryProvider.overrideWithValue(repo ?? _conMariaDeBaja()),
    relojPersonaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 25, 9, 30)),
    saldosDePersonasProvider.overrideWithValue(SaldosFalsos({'p2': 120000})),
  ],
);

final _mostrar = find.byKey(ClavesBajasDePersonas.mostrar);
final _reactivarMaria = find.byKey(ClavesBajasDePersonas.reactivar('p2'));

Future<void> _mostrarLasBajas(WidgetTester tester) async {
  await tester.ensureVisible(_mostrar);
  await tester.tap(_mostrar);
  await asentarHoja(tester);
}

void main() {
  group('fila del depto → ficha 11·04', () {
    testWidgets(
      'tocar el depto abre su ficha con sus clientes, «Editar» y «Mostrar bajas» apagado',
      (tester) async {
        await _montar(tester);

        await abrirFichaDepto(tester, 'esp-1');

        expect(fichaDepto, findsOneWidget);
        expect(hojaDepto, findsNothing, reason: 'la fila ya no abre la edición directo');
        expect(find.text('Depto 101'), findsOneWidget);
        expect(find.text('Jorge Fernández'), findsOneWidget);
        expect(botonEditarDepto, findsOneWidget);
        expect(find.text('Editar'), findsOneWidget);
        expect(tester.widget<SwitchListTile>(_mostrar).value, isFalse);
        expect(find.text('María Fernández'), findsNothing);
      },
    );

    testWidgets('«Mostrar bajas» muestra a María en gris con la fecha y el saldo, y «Reactivar» la '
        'vuelve a la lista con el aviso de 32D·05', (tester) async {
      final repo = _conMariaDeBaja();
      await _montar(tester, repo: repo);
      await abrirFichaDepto(tester, 'esp-1');

      await _mostrarLasBajas(tester);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('Baja el 22/10 · saldo \$\u00a01.200'), findsOneWidget);

      await tester.tap(_reactivarMaria);
      await asentarHoja(tester);

      expect(repo.reactivacionesRecibidas, ['p2']);
      expect(find.text('Reactivamos a María.'), findsOneWidget);
      expect(_reactivarMaria, findsNothing);
      expect(find.text('María Fernández'), findsOneWidget, reason: 'ahora entre los clientes');
    });

    testWidgets(
      'volver a la hoja y reentrar: la ficha vuelve a abrir, con «Mostrar bajas» apagado',
      (tester) async {
        await _montar(tester);
        await abrirFichaDepto(tester, 'esp-1');
        await _mostrarLasBajas(tester);

        await volverDeLaFicha(tester);
        expect(fichaDepto, findsNothing);
        expect(hojaUbicacion, findsOneWidget);

        await abrirFichaDepto(tester, 'esp-1');
        expect(fichaDepto, findsOneWidget);
        expect(tester.widget<SwitchListTile>(_mostrar).value, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('«Editar» en el encabezado de 11·04', () {
    testWidgets(
      'abre la edición con el depto cargado; al guardar la ficha sigue con el número nuevo '
      'y, al volver, la hoja también lo tiene',
      (tester) async {
        final m = await _montar(tester);
        await abrirEdicionDepto(tester, 'esp-1');

        expect(hojaDepto, findsOneWidget);
        expect(textoDe(tester, campoNumero), '101');
        await escribir(tester, campoNumero, '105');
        await tester.tap(botonGuardarDepto);
        await asentarHoja(tester);

        expect(hojaDepto, findsNothing);
        expect(fichaDepto, findsOneWidget, reason: 'guardar vuelve a la ficha, no a la hoja');
        expect(find.text('Depto 105'), findsOneWidget);
        expect(m.repo.espacios.firstWhere((e) => e.id == 'esp-1').numeroDepto, '105');

        await volverDeLaFicha(tester);
        expect(filaDepto('esp-1'), findsOneWidget);
        expect(find.text('Depto 105'), findsOneWidget);
      },
    );

    testWidgets('dar de baja el depto desde «Editar» cierra la ficha y la hoja ya no lo muestra', (
      tester,
    ) async {
      final m = await _montar(tester);
      await abrirEdicionDepto(tester, 'esp-1');

      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      await tester.tap(find.byKey(ClavesHojaDepto.confirmarBaja));
      await asentarHoja(tester);

      expect(hojaDepto, findsNothing);
      expect(fichaDepto, findsNothing);
      expect(hojaUbicacion, findsOneWidget);
      expect(filaDepto('esp-1'), findsNothing);
      expect(m.repo.espacios.firstWhere((e) => e.id == 'esp-1').estaBorrada, isTrue);
    });

    testWidgets('«Ver depto 102 ›» desde la edición cierra esta ficha y abre la del 102', (
      tester,
    ) async {
      await _montar(tester);
      await abrirEdicionDepto(tester, 'esp-1');
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonGuardarDepto);
      await asentarHoja(tester);
      expect(avisoRepetido, findsOneWidget);

      await tester.tap(enlaceVerRepetido);
      await asentarHoja(tester, 16);

      expect(hojaDepto, findsNothing);
      expect(fichaDepto, findsOneWidget, reason: 'una sola ficha, no una encima de otra');
      expect(tester.widget<PersonasDelEspacioPage>(fichaDepto).espacioId, 'e-102');
      expect(find.text('Depto 102'), findsOneWidget);
    });

    testWidgets(
      'cerrar la edición sin guardar deja la ficha como estaba y «Editar» vuelve a abrir',
      (tester) async {
        await _montar(tester);
        await abrirEdicionDepto(tester, 'esp-1');
        Navigator.of(tester.element(hojaDepto)).pop();
        await asentarHoja(tester);

        expect(fichaDepto, findsOneWidget);
        expect(find.text('Depto 101'), findsOneWidget);
        await tester.tap(botonEditarDepto);
        await asentarHoja(tester);
        expect(hojaDepto, findsOneWidget);
      },
    );
  });

  group('casos límite', () {
    testWidgets('doble toque en «Reactivar» de la ficha: se reactiva una sola vez', (tester) async {
      final repo = _conMariaDeBaja()..compuertaReactivar = Completer<void>();
      await _montar(tester, repo: repo);
      await abrirFichaDepto(tester, 'esp-1');
      await _mostrarLasBajas(tester);

      await tester.tap(_reactivarMaria);
      await tester.pump();
      // Mientras se escribe, «Reactivar» deja lugar a la ruedita: el segundo toque cae en la fila.
      expect(_reactivarMaria, findsNothing);
      await tester.tap(find.byKey(ClavesBajasDePersonas.fila('p2')), warnIfMissed: false);
      repo.compuertaReactivar!.complete();
      await asentarHoja(tester);

      expect(repo.reactivacionesRecibidas, ['p2']);
    });

    testWidgets('falla a mitad de reactivar: avisa, nada queda trabado y reintentar la reactiva', (
      tester,
    ) async {
      final repo = _conMariaDeBaja()..resultadosReactivar.add(const FailureInesperado());
      await _montar(tester, repo: repo);
      await abrirFichaDepto(tester, 'esp-1');
      await _mostrarLasBajas(tester);

      await tester.tap(_reactivarMaria);
      await asentarHoja(tester);

      expect(find.text('No pudimos reactivar a María. Probá de nuevo.'), findsOneWidget);
      expect(_reactivarMaria, findsOneWidget, reason: 'el botón vuelve a poder tocarse');

      await tester.tap(_reactivarMaria);
      await asentarHoja(tester);
      expect(repo.reactivacionesRecibidas, ['p2', 'p2']);
      expect(find.text('Reactivamos a María.'), findsOneWidget);
    });

    testWidgets('con 40 bajas la lista se desplaza hasta la última', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          clienteDePersonas('p1', 'Jorge'),
          for (var i = 0; i < 40; i++) clienteDeBajaDePersonas('b$i', 'Baja$i', minutos: i),
        ]);
      await _montar(tester, repo: repo);
      await abrirFichaDepto(tester, 'esp-1');
      await _mostrarLasBajas(tester);

      final ultima = find.byKey(ClavesBajasDePersonas.fila('b39'));
      await tester.scrollUntilVisible(ultima, 200, scrollable: find.byType(Scrollable).last);
      expect(ultima, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 320 × 568 con el texto al 200 % la ficha, «Editar» y las bajas no desbordan', (
      tester,
    ) async {
      await _montar(tester, escala: 2, tamano: const Size(320, 568));
      await tester.dragUntilVisible(
        filaDepto('esp-1'),
        find.byType(Scrollable).last,
        const Offset(0, -80),
      );
      await tester.pump();
      await abrirFichaDepto(tester, 'esp-1');

      expect(fichaDepto, findsOneWidget);
      expect(botonEditarDepto.hitTestable(), findsOneWidget);
      // A 2× la lista es perezosa: se baja hasta el interruptor y después hasta «Reactivar».
      final listaDeLaFicha = find.descendant(of: fichaDepto, matching: find.byType(Scrollable));
      await tester.dragUntilVisible(_mostrar, listaDeLaFicha.first, const Offset(0, -80));
      await tester.pump();
      await tester.tap(_mostrar);
      await asentarHoja(tester);
      await tester.dragUntilVisible(_reactivarMaria, listaDeLaFicha.first, const Offset(0, -80));
      await tester.pump();
      expect(_reactivarMaria.hitTestable(), findsOneWidget);
      expect(tester.getRect(_reactivarMaria).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });
  });
}
