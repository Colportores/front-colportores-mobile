// QA r2 del paso «¿Con quién?» de la vista 39 (#449, PR #463, punta e9b631e): C·07 con nombres
// repetidos. Decisión del orquestador (23/10): SOLO cuando el nombre se repite, la fila suma una
// segunda línea (el teléfono enmascarado de 11·04 o «Cargada el dd/MM») y el lector la lee; con
// nombres distintos la fila queda como el canvas; no se numera.
import 'package:colportores_mobile/features/mapa/domain/entities/persona_del_espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/paso_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_con_quien.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_baja_205_arnes.dart'
    show cargarFuentes205, expectSinTextoFueraDeLosCostados205;
import '../../helpers/qa_vista39_449_arnes.dart';
import '../../helpers/qa_vista39_449_dup_arnes.dart';
import 'hoja_con_quien_arnes.dart';
import 'personas_arnes.dart' show asentar;

String _diaMes(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
}

Future<ResultadoConQuien> _con(
  WidgetTester tester,
  List<PersonaDelEspacio> personas, {
  Map<String, int> saldos = const {},
}) => montar449(
  tester,
  repo: PersonaRepositorioFalso()..sembrar(personas),
  saldos: SaldosFalsos(saldos),
);

void main() {
  group('cuándo hay segunda línea', () {
    testWidgets('nombres distintos: la fila queda como el canvas, aunque tengan teléfono', (
      tester,
    ) async {
      await _con(tester, [
        persona449('a', 'Pedro', apellido: 'Gómez', telefono: '099 123 412'),
        persona449('b', 'Ana', apellido: 'Gómez', telefono: '098 555 777'),
        persona449('c', 'Pedro', apellido: 'Núñez'),
      ]);

      expect(find.textContaining('Tel.'), findsNothing);
      expect(find.textContaining('Cargada el'), findsNothing);
    });

    testWidgets('«Pedro» y «Pedro Gómez» no son el mismo nombre', (tester) async {
      await _con(tester, [persona449('a', 'Pedro'), persona449('b', 'Pedro', apellido: 'Gómez')]);

      expect(find.textContaining('Cargada el'), findsNothing);
    });

    testWidgets('dos con teléfono: cada una muestra el suyo, enmascarado, y no el número entero', (
      tester,
    ) async {
      await _con(tester, personasDup449(EstadoDup449.dosConTelefono));

      expect(find.text('Tel. 099 ••• 412'), findsOneWidget);
      expect(find.text('Tel. 098 ••• 777'), findsOneWidget);
      expect(find.textContaining('123'), findsNothing);
      expect(find.textContaining('555'), findsNothing);
    });

    testWidgets('sin teléfono: «Cargada el dd/MM» de cada una, en hora local', (tester) async {
      await _con(tester, personasDup449(EstadoDup449.tresSinTelefonoConSaldo));

      for (final d in [20, 21, 22]) {
        expect(find.text('Cargada el ${_diaMes(DateTime.utc(2026, 10, d, 15))}'), findsOneWidget);
      }
      // La única «Ana» no lleva segunda línea.
      expect(find.textContaining('Cargada el'), findsNWidgets(3));
    });

    testWidgets('un teléfono de solo espacios cuenta como sin teléfono', (tester) async {
      await _con(tester, [
        persona449('a', 'Pedro', apellido: 'Gómez', telefono: '   '),
        persona449('b', 'Pedro', apellido: 'Gómez', telefono: '099 123 412'),
      ]);

      expect(find.text('Cargada el ${_diaMes(DateTime.utc(2026, 10, 22, 15))}'), findsOneWidget);
      expect(find.text('Tel. 099 ••• 412'), findsOneWidget);
    });

    testWidgets('no distingue mayúsculas ni espacios de más: «PEDRO  gómez» y «Pedro Gómez»', (
      tester,
    ) async {
      await _con(tester, [
        persona449('a', 'PEDRO ', apellido: ' gómez', telefono: '099 123 412'),
        persona449('b', 'Pedro', apellido: 'Gómez', telefono: '098 555 777'),
      ]);

      expect(find.textContaining('Tel.'), findsNWidgets(2));
    });

    testWidgets('dos «Pedro Gómez» y una «Ana»: solo los dos Pedros llevan la línea', (
      tester,
    ) async {
      await _con(tester, [
        persona449('a', 'Pedro', apellido: 'Gómez', telefono: '099 123 412'),
        persona449('b', 'Pedro', apellido: 'Gómez'),
        persona449('c', 'Ana', apellido: 'Gómez', telefono: '091 222 333'),
      ]);

      expect(find.textContaining('Tel.'), findsOneWidget);
      expect(find.textContaining('Cargada el'), findsOneWidget);
      expect(find.text('Tel. 091 ••• 333'), findsNothing);
    });

    testWidgets('la línea no se numera («(1)», «(2)»)', (tester) async {
      await llegarADup449(tester, EstadoDup449.tresSinTelefonoConSaldo);

      expect(find.textContaining('(1)'), findsNothing);
      expect(find.textContaining('(2)'), findsNothing);
    });
  });

  group('elegir y devolver con nombres repetidos', () {
    testWidgets('tocar la segunda línea elige esa fila y «Empezar entrevista» devuelve a esa '
        'persona', (tester) async {
      final p = personasDup449(EstadoDup449.tresSinTelefonoConSaldo);
      final r = await llegarADup449(tester, EstadoDup449.tresSinTelefonoConSaldo);

      await tester.tap(find.text('Cargada el ${_diaMes(DateTime.utc(2026, 10, 22, 15))}'));
      await tester.pump();
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      expect(r.elegida, p[2].aLaEntrevista);
      expect(r.cierres, 1);
    });

    testWidgets('la primera viene elegida (orden de alta) y el lector dice cuál está marcada', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _con(tester, personasDup449(EstadoDup449.dosConTelefono));

      expect(
        tester.getSemantics(find.bySemanticsLabel('Pedro Gómez. Teléfono terminado en 412')),
        isSemantics(
          label: 'Pedro Gómez. Teléfono terminado en 412',
          hasCheckedState: true,
          isChecked: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Pedro Gómez. Teléfono terminado en 777')),
        isSemantics(
          label: 'Pedro Gómez. Teléfono terminado en 777',
          hasCheckedState: true,
          isChecked: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('el lector lee nombre, dato que distingue y saldo, en ese orden', (tester) async {
      final handle = tester.ensureSemantics();
      await llegarADup449(tester, EstadoDup449.tresSinTelefonoConSaldo);

      final dia = _diaMes(DateTime.utc(2026, 10, 20, 15));
      expect(find.bySemanticsLabel('Pedro Gómez. Cargada el $dia. Saldo \$ 1.200'), findsOneWidget);
      // «Ana Gómez» sola: ni dato ni «Cargada».
      expect(find.bySemanticsLabel('Ana Gómez'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('«+ Alguien nuevo» con un nombre que ya está: las dos filas pasan a llevar la '
        'línea y la nueva queda elegida', (tester) async {
      final repo = PersonaRepositorioFalso()
        ..sembrar([
          persona449('a', 'Pedro', apellido: 'Gómez', telefono: '099 123 412'),
          persona449('b', 'Ana', apellido: 'Gómez'),
        ]);
      final r = await montar449(tester, repo: repo);
      expect(find.textContaining('Tel.'), findsNothing);

      await tester.tap(find.text('+ Alguien nuevo'));
      await asentar(tester, 16);
      await tester.enterText(find.byType(TextField).at(0), 'Pedro');
      await tester.enterText(find.byType(TextField).at(1), 'Gómez');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar persona'));
      await asentar(tester, 16);

      expect(find.text('Tel. 099 ••• 412'), findsOneWidget);
      expect(find.textContaining('Cargada el'), findsOneWidget);
      await tester.tap(botonEmpezar449);
      await asentar(tester);
      expect(r.elegida!.personaId, repo.recibidas.single.persona.id);
    });
  });

  group('tamaños y texto grande, fuentes reales', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in EstadoDup449.values) {
          testWidgets('${estado.name} · ${sufijo449(tamano, escala)}: sin overflow, la línea cabe '
              'y la fila se alcanza', (tester) async {
            await cargarFuentes205(tester);
            await llegarADup449(tester, estado, tamano: tamano, escala: escala);

            expect(tester.takeException(), isNull);
            expectSinTextoFueraDeLosCostados205(tester, tamano);
            await capturar449(tester, 'dup_${estado.name}_${sufijo449(tamano, escala)}');

            final linea = find.textContaining(RegExp(r'Tel\.|Cargada el')).first;
            await tester.ensureVisible(linea);
            await tester.pump();
            final r = tester.getRect(linea);
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(tamano.width));
            expect(r.bottom, lessThanOrEqualTo(tamano.height));
            // La fila entera (tocable) mide al menos 48 dp de alto.
            final fila = find.ancestor(of: linea, matching: find.byType(InkWell)).first;
            expect(tester.getRect(fila).height, greaterThanOrEqualTo(48));
            // «Empezar entrevista» se sigue alcanzando.
            await tester.ensureVisible(botonEmpezar449);
            await tester.pump();
            expect(tester.getRect(botonEmpezar449).height, greaterThanOrEqualTo(48));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('texto 2,0 en 360×640 con 30 repetidas: se llega a la última fila y se elige', (
      tester,
    ) async {
      await cargarFuentes205(tester);
      final p = personasDup449(EstadoDup449.treintaRepetidos);
      final r = await llegarADup449(
        tester,
        EstadoDup449.treintaRepetidos,
        tamano: t360x640,
        escala: 2,
      );

      final ultima = find.text('Cargada el ${_diaMes(DateTime.utc(2026, 9, 30, 15))}');
      await tester.scrollUntilVisible(ultima, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(ultima);
      await tester.pump();
      await tester.ensureVisible(botonEmpezar449);
      await tester.tap(botonEmpezar449);
      await asentar(tester);

      expect(r.elegida, p[29].aLaEntrevista);
    });
  });

  group('unidad · TextosConQuien', () {
    final a = persona449('a', 'Pedro', apellido: 'Gómez', telefono: '12');

    test('teléfono muy corto: se oculta sin romper', () {
      expect(TextosConQuien.paraDistinguir(a.persona), 'Tel. ••• 12');
    });

    test('conNombreRepetido ignora a quien tiene un nombre único', () {
      final b = persona449('b', 'Ana');
      expect(TextosConQuien.conNombreRepetido([a, b]), isEmpty);
      expect(TextosConQuien.conNombreRepetido([a, persona449('c', 'pedro', apellido: 'GÓMEZ')]), {
        'a',
        'c',
      });
    });

    test('lista vacía no revienta', () {
      expect(TextosConQuien.conNombreRepetido(const []), isEmpty);
    });
  });
}
