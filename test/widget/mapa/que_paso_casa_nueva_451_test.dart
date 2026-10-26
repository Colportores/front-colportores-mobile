// HU-VIS-005 · vista 39 (#451): N·03 «Casa o negocio: ¿qué pasó?», la hoja de «¿Qué pasó?» de una casa
// que se acaba de registrar. Es la misma hoja de C·06 (#411), que dice «Casa nueva» junto a la dirección
// y se sale con «Volver». El aviso «Guardado» nombra la dirección sola.
import 'dart:async';

import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/persona_falsos.dart';
import 'personas_arnes.dart' show asentar;
import 'registrar_visita_arnes.dart';

Finder get _volver => find.byKey(ClavesQuePaso.cancelar);

void main() {
  group('N·03 · ¿Qué pasó? de la casa recién registrada', () {
    testWidgets('dice «Casa nueva» junto a la dirección y se sale con «Volver»', (tester) async {
      await montarQuePaso(tester, casaNueva: true);

      expect(find.text('¿Qué pasó?'), findsOneWidget);
      expect(find.text('Grecia 3307 · Casa nueva'), findsOneWidget);
      expect(find.text('Volver'), findsOneWidget);
      expect(find.text('Cancelar'), findsNothing);
      // Los resultados son los de siempre.
      expect(find.text('No contestó'), findsOneWidget);
      expect(find.text('Rechazo'), findsOneWidget);
    });

    testWidgets('una casa que no es nueva sigue diciendo «Cancelar»', (tester) async {
      await montarQuePaso(tester);

      expect(find.text('Grecia 3307'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Volver'), findsNothing);
    });

    testWidgets(
      '«Volver» cierra sin guardar nada y devuelve false (la casa queda registrada, sin visita)',
      (tester) async {
        final repo = AgendaRepositorioFalso();
        final arnes = await montarQuePaso(tester, casaNueva: true, repo: repo);

        await tester.tap(_volver);
        await asentar(tester);

        expect(find.byKey(ClavesQuePaso.hoja), findsNothing);
        expect(arnes.resultados, [false]);
        expect(repo.recibidas, isEmpty);
      },
    );

    testWidgets('«No contestó» guarda de un toque y el aviso nombra la dirección sola', (
      tester,
    ) async {
      final repo = AgendaRepositorioFalso();
      final arnes = await montarQuePaso(tester, casaNueva: true, repo: repo);

      await elegir(tester, OpcionQuePaso.noContesto);

      expect(arnes.resultados, [true]);
      expect(repo.recibidas, hasLength(1));
      expect(find.text('Guardado. Grecia 3307 quedó como «No contestó».'), findsOneWidget);
      expect(find.text('Casa nueva'), findsNothing);
    });

    testWidgets('mientras guarda, «Volver» está apagado', (tester) async {
      final repo = AgendaRepositorioFalso()..compuerta = Completer<void>();
      await montarQuePaso(tester, casaNueva: true, repo: repo);

      await elegir(tester, OpcionQuePaso.rechazo);

      expect(tester.widget<OutlinedButton>(_volver).onPressed, isNull);
      expect(find.text('Guardando…'), findsOneWidget);
      repo.compuerta!.complete();
      await asentar(tester);
      expect(find.byKey(ClavesQuePaso.hoja), findsNothing);
    });

    testWidgets('una dirección larguísima y el texto al 200 % en 360×640 no desbordan', (
      tester,
    ) async {
      await montarQuePaso(
        tester,
        casaNueva: true,
        escala: 2,
        tamano: const Size(360, 640),
        casa: (
          espacio: espacioDePersonas(numeroDepto: null, piso: null),
          ubicacion: ubicacionDePersonas(
            tipo: TipoUbicacion.casa,
            calle: 'Avenida de los Treinta y Tres Orientales y Doctor Luis Alberto de Herrera',
            numero: '12345678901234567890',
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('· Casa nueva'), findsOneWidget);
      await tester.ensureVisible(_volver);
      await tester.pump();
      expect(tester.getRect(_volver).bottom, lessThanOrEqualTo(640.5));
    });
  });
}
