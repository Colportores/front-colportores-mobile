// QA de #273 / PR #640 (vista 04, B·01 y B·02): la tarjeta de la candidata a duplicado con el estado de
// visita y «N espacios». Lo que el test del implementador no mira: las guías de accesibilidad en los dos
// teléfonos del QA, los ocho estados a 200 % sin desborde, el orden de lectura de la tarjeta y los
// casos límite de los datos (sin ciudad, dirección larga, muchas candidatas).
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_duplicado_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:dartz/dartz.dart' show Right;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_317_arnes.dart';

Future<void> _abrirHoja(
  WidgetTester tester,
  List<CandidataDuplicado> candidatas, {
  Size tamano = telefonoChico,
  double escala = 1,
}) async {
  final repo = RepoAltaFalso()
    ..comportamiento = (_) async => Right(AltaConDuplicados(candidatas: candidatas));
  await abrirAlta(tester, repo: repo, tamano: tamano, escala: escala);
  await tocar(tester, find.text('Casa'));
  await tocar(tester, botonRegistrarFijo);
  expect(find.byType(HojaDuplicadoAlta), findsOneWidget);
}

CandidataDuplicado _una([EstadoCasa estado = EstadoCasa.entrevistaAgendada, int espacios = 2]) =>
    candidata('c1', estado: estado, espacios: espacios);

List<CandidataDuplicado> _dos() => [
  candidata('a', metros: 12, estado: EstadoCasa.entrevistaAgendada, espacios: 2),
  candidata('b', metros: 4, numero: '1236', estado: EstadoCasa.sinVisita, espacios: 1),
];

void main() {
  group('guías de accesibilidad de la hoja con la tarjeta ampliada (B·01 y B·02)', () {
    for (final tamano in [telefonoChico, telefonoGrande]) {
      for (final escala in [1.0, 2.0]) {
        for (final (nombre, candidatas) in [
          ('B·01', [_una()]),
          ('B·02', _dos()),
        ]) {
          testWidgets('$nombre a ${tamano.width.toInt()}×${tamano.height.toInt()}, texto $escala', (
            tester,
          ) async {
            final handle = tester.ensureSemantics();
            await _abrirHoja(tester, candidatas, tamano: tamano, escala: escala);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            expect(tester.takeException(), isNull);
            handle.dispose();
          });
        }
      }
    }
  });

  group('los ocho estados a 200 % en el teléfono chico', () {
    for (final estado in EstadoCasa.values) {
      testWidgets('${estado.name}: el rótulo entero queda dentro de la tarjeta, sin desborde', (
        tester,
      ) async {
        await _abrirHoja(tester, [_una(estado, 12)], escala: 2);

        final rotulo = find.text(FormatoListaUbicaciones.estado(estado));
        expect(rotulo, findsOneWidget);
        expect(tester.takeException(), isNull);
        // Entra entero en el ancho de la pantalla (no se corta por la derecha).
        final r = tester.getRect(rotulo);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(telefonoChico.width));
      });
    }

    testWidgets('B·02 con las dos tarjetas y el texto a 200 %: ninguna se pisa con la otra', (
      tester,
    ) async {
      await _abrirHoja(tester, _dos(), escala: 2);

      final a = tester.getRect(find.text('Entrevista agendada'));
      final b = tester.getRect(find.text('Sin visita'));
      expect(a.overlaps(b), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('lector de pantalla', () {
    testWidgets('la tarjeta dice el estado y el resumen, y la insignia no suma un nodo propio', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _abrirHoja(tester, [_una()]);

      expect(find.bySemanticsLabel('Entrevista agendada'), findsOneWidget);
      expect(find.bySemanticsLabel('Casa · 2 espacios · Montevideo'), findsOneWidget);
      // El glifo de la insignia («◷») no se lee como un nodo aparte.
      expect(
        find.bySemanticsLabel(FormatoListaUbicaciones.glifo(EstadoCasa.entrevistaAgendada)),
        findsNothing,
      );
      expect(find.byType(ExcludeSemantics), findsWidgets);
      handle.dispose();
    });

    testWidgets('«Sin visita» (insignia sin glifo) tampoco duplica la lectura', (tester) async {
      final handle = tester.ensureSemantics();
      await _abrirHoja(tester, [_una(EstadoCasa.sinVisita, 0)]);

      expect(find.bySemanticsLabel('Sin visita'), findsOneWidget);
      expect(find.bySemanticsLabel('Casa · sin espacios · Montevideo'), findsOneWidget);
      handle.dispose();
    });
  });

  group('casos límite de los datos', () {
    testWidgets('ciudad desconocida: el resumen no deja un «·» colgando', (tester) async {
      await _abrirHoja(tester, [
        candidata('c1', ciudadId: 'ciu-que-no-existe', estado: EstadoCasa.rechazo, espacios: 3),
      ]);

      // Texto exacto: sin ciudad no queda un «·» colgando al final.
      expect(find.text('Casa · 3 espacios'), findsOneWidget);
    });

    testWidgets('dirección larguísima y 99 espacios a 200 %: sin desborde', (tester) async {
      await _abrirHoja(tester, [
        candidata(
          'c1',
          calle: 'Avenida General Don José Gervasio Artigas y Rivera',
          numero: '123456 bis apto 14B',
          estado: EstadoCasa.cobranzaPendiente,
          espacios: 99,
          tipo: TipoUbicacion.edificio,
        ),
      ], escala: 2);

      expect(find.textContaining('99 deptos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('seis candidatas (muchas): cada una con su estado, sin desborde a 200 %', (
      tester,
    ) async {
      await _abrirHoja(tester, [
        for (var i = 0; i < 6; i++)
          candidata(
            'c$i',
            metros: 3.0 + i,
            numero: '${1230 + i}',
            estado: EstadoCasa.values[i],
            espacios: i,
          ),
      ], escala: 2);

      expect(tester.takeException(), isNull);
      expect(find.byType(InsigniaEstadoCasa), findsNWidgets(6));
    });

    testWidgets('mezcla: una candidata sin dato y otra con dato, la sin dato no inventa estado', (
      tester,
    ) async {
      await _abrirHoja(tester, [
        candidata('sin'),
        candidata('con', metros: 4, numero: '1236', estado: EstadoCasa.rechazo, espacios: 1),
      ]);

      expect(find.byType(InsigniaEstadoCasa), findsOneWidget);
      expect(find.text('Rechazó'), findsOneWidget);
      expect(find.text('Casa · Montevideo'), findsOneWidget);
    });
  });
}
