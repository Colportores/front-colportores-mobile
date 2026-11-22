// QA de #612 (decisiones de #509: el texto de la segunda confirmación de la baja, 32D·03, cuando hay
// entregas pendientes). El artboard 32D·03 del canvas solo dibuja la deuda; la decisión del 03/11 (P2,
// comentario de #604) fija las frases con entregas. Los estados ya cubiertos por la matriz de #604
// (`qa_vista32_509_test.dart`) no se repiten: acá van los que combinan lo nuevo con lo extremo (deuda de
// siete cifras + varias entregas + nombre largo, 320×568) y el texto literal de la decisión.
//
// (El plural sin número, hallado en la primera pasada, ya lo arregló el PR.)
// Capturas: `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`, nunca al repo).
import 'package:colportores_mobile/features/mapa/domain/services/cuenta_de_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_baja_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notas_persona_arnes.dart' show asentar;
import 'qa_vista32_509_arnes.dart';

ResumenCuentaPersona _cuenta({required int saldo, required int pendientes}) => ResumenCuentaPersona(
  compradoCentavos: saldo + 500000,
  pagadoCentavos: 500000,
  saldoCentavos: saldo,
  entregasHechas: 0,
  entregasTotales: pendientes,
);

const _tamanos = [Size(320, 568), Size(360, 640), Size(412, 915)];

void main() {
  group('32D·03 · el texto de la decisión del 03/11 (P2)', () {
    test('dada solo 1 entrega: «La entrega pendiente no se cancela: queda registrada…»', () {
      expect(
        TextosBajaPersona.segundaConfirmacion('Jorge', _cuenta(saldo: 0, pendientes: 1)),
        'La entrega pendiente no se cancela: queda registrada aunque Jorge esté de baja.',
      );
    });

    test('dada solo deuda: el texto del canvas, sin cambios', () {
      expect(
        TextosBajaPersona.segundaConfirmacion(
          'María',
          const ResumenCuentaPersona(
            compradoCentavos: 450000,
            pagadoCentavos: 330000,
            saldoCentavos: 120000,
            entregasHechas: 2,
            entregasTotales: 2,
          ),
        ),
        'La deuda de ${FormatoBajaPersona.monto(120000)} sigue en tu cuenta aunque María esté de baja.',
      );
    });

    test('dada deuda y 1 entrega: las dos frases, primero la de la deuda', () {
      expect(
        TextosBajaPersona.segundaConfirmacion('Jorge', _cuenta(saldo: 120000, pendientes: 1)),
        'La deuda de ${FormatoBajaPersona.monto(120000)} sigue en tu cuenta aunque Jorge esté de baja. '
        'La entrega pendiente no se cancela: queda registrada aunque Jorge esté de baja.',
      );
    });

    test('dada una cuenta sin saldo ni entregas, la segunda confirmación no inventa texto', () {
      expect(
        TextosBajaPersona.segundaConfirmacion('Jorge', _cuenta(saldo: 0, pendientes: 0)),
        isEmpty,
      );
    });

    // La decisión de #604 (comentario del 03/11, P2) dice, textual: «en plural: «Las 2 entregas
    // pendientes no se cancelan: quedan registradas aunque Jorge esté de baja.»». El PR lo escribió sin
    // el número («Las entregas pendientes no se cancelan…»).
    test(
      'dadas 2 entregas, el plural lleva el número, como en la decisión: «Las 2 entregas pendientes…»',
      () {
        expect(
          TextosBajaPersona.segundaConfirmacion('Jorge', _cuenta(saldo: 0, pendientes: 2)),
          'Las 2 entregas pendientes no se cancelan: quedan registradas aunque Jorge esté de baja.',
        );
      },
    );

    test('dado cualquier texto con entregas, no habla de dónde se ve la entrega ni la cancela', () {
      for (final n in [1, 2, 3, 12]) {
        final t = TextosBajaPersona.segundaConfirmacion('Jorge', _cuenta(saldo: 0, pendientes: n));
        expect(t, contains('no se cancel'));
        expect(t, contains('registrad'));
        expect(t, isNot(contains('null')));
        expect(t, isNot(contains('\$')));
      }
    });
  });

  group('32D·03 · lo extremo con el texto nuevo', () {
    // Deuda de siete cifras + 3 entregas: la frase más larga que arma la segunda confirmación.
    final larga = _cuenta(saldo: 123456700, pendientes: 3);
    for (final tamano in _tamanos) {
      for (final escala in [1.0, 1.5, 2.0]) {
        final id = '${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala';

        testWidgets('dada deuda de \$ 1.234.567 y 3 entregas, entra y se alcanza · $id', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await hojaConCuenta(tester, larga, segunda: true, tamano: tamano, escala: escala);
          expect(tester.takeException(), isNull);
          expect(find.text('¿Seguro?'), findsOneWidget);
          final cuerpo = TextosBajaPersona.segundaConfirmacion('Jorge', larga);
          expect(find.text(cuerpo), findsOneWidget);
          await verEnPantalla(tester, find.text('Sí, dar de baja'));
          dentroDeLaPantalla(tester, find.text('Sí, dar de baja'));
          dentroDeLaPantalla(tester, find.text('No, volver'));
          sinTextoCortado(tester);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await capturar(tester, '612_D03_larga_${tamano.width.toInt()}_x${(escala * 10).toInt()}');
          semantica.dispose();
        });

        testWidgets('dado un nombre larguísimo con deuda y entregas, se lee entera · $id', (
          tester,
        ) async {
          await hojaConCuenta(
            tester,
            larga,
            segunda: true,
            tamano: tamano,
            escala: escala,
            nombre: 'Maximiliano Alejandro',
            apellido: 'Fernández de la Cruz y Albarracín',
          );
          expect(tester.takeException(), isNull);
          expect(find.text('¿Seguro?'), findsOneWidget);
          final cuerpo = TextosBajaPersona.segundaConfirmacion('Maximiliano Alejandro', larga);
          await verEnPantalla(tester, find.text(cuerpo));
          expect(find.text(cuerpo), findsOneWidget);
          await verEnPantalla(tester, find.text('Sí, dar de baja'));
          dentroDeLaPantalla(tester, find.text('Sí, dar de baja'));
          sinTextoCortado(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('dado un lector de pantalla, el cuerpo de «¿Seguro?» es un solo nodo legible', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final cuenta = _cuenta(saldo: 120000, pendientes: 1);
      await hojaConCuenta(tester, cuenta, segunda: true);
      final cuerpo = TextosBajaPersona.segundaConfirmacion('Jorge', cuenta);
      expect(find.bySemanticsLabel(cuerpo), findsOneWidget);
      semantica.dispose();
    });
  });

  group('32D·03 · el flujo con el texto nuevo', () {
    testWidgets(
      'dado «No, volver» con deuda y 2 entregas, vuelve al resumen y no escribe; se puede '
      'reconfirmar',
      (tester) async {
        final e = await hojaConCuenta(tester, _cuenta(saldo: 120000, pendientes: 2), segunda: true);
        await tester.tap(find.text('No, volver'));
        await asentar(tester);
        expect(find.text('¿Seguro?'), findsNothing);
        expect(find.text('Dar de baja igual'), findsOneWidget);
        expect(e.repo.bajasRecibidas, isEmpty);

        await tester.tap(find.text('Dar de baja igual'));
        await asentar(tester);
        expect(find.text('¿Seguro?'), findsOneWidget);
        await tester.tap(find.text('Sí, dar de baja'));
        await asentar(tester);
        expect(e.repo.bajasRecibidas, hasLength(1));
        expect(e.resultado.cierres, 1);
      },
    );
  });
}
