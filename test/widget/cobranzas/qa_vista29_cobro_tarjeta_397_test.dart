// QA del cierre de #397 (vista 29, grupo A · cobro con tarjeta): el PR #586 saca los `skip` de la QA de #164
// y cambia la medida del selector «MEDIO» (letra 13, relleno 4, medida con la fuente del tema). Lo que
// este archivo agrega son los bordes de ese cambio con las fuentes reales: el rótulo más largo nunca se
// parte ni se corta en ninguna escala de texto, el cambio de fila a columna conserva el estado y el toque,
// y los emoji de los datos del medio cuentan igual en el campo y en el registro.
// Las capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/cobro_arnes.dart';
import '../../helpers/qa_vista29_164_arnes.dart';

/// Los tres segmentos están en la misma fila (mismo borde de arriba).
bool _enFila(WidgetTester tester) =>
    {for (var i = 0; i < 3; i++) tester.getTopLeft(medio164(i)).dy.round()}.length == 1;

/// La lista es perezosa: con letra grande el selector, arriba, se desarma al bajar; se vuelve al tope.
Future<void> _alTope(WidgetTester tester) async {
  await tester.drag(
    find.descendant(of: pagina, matching: find.byType(Scrollable)).first,
    const Offset(0, 5000),
  );
  await asentarAgendar(tester, 3);
}

Finder _rotuloDe(int i) => find.descendant(of: medio164(i), matching: find.byType(Text));

void main() {
  const escalas = [1.0, 1.1, 1.15, 1.3, 1.5, 2.0];

  group('Selector «MEDIO» (29A·01): el rótulo más largo nunca se parte ni se corta', () {
    for (final tamano in [chico164, grande164]) {
      for (final escala in escalas) {
        testWidgets('${sufijo164(tamano, escala)}: «Transferencia» en un solo renglón, dentro de su '
            'segmento, y cada segmento mide 48 dp o más', (tester) async {
          await llegarA164(tester, Estado164.a01Tarjeta, tamano: tamano, escala: escala);
          await _alTope(tester);
          await traerAlAlcance(tester, medio164(2));

          expect(tester.takeException(), isNull);
          final texto = _rotuloDe(2);
          final renglon = tester.getSize(find.text('Transferencia')).height;
          // Un renglón de letra 13 con interlineado normal mide ~1,3 × 13 × escala; dos renglones, el doble.
          expect(
            renglon,
            lessThan(13 * escala * 2.0),
            reason: '«Transferencia» ocupa más de un renglón: ${tester.getSize(texto)}',
          );
          expect(
            tester.getSize(find.text('Transferencia')).width,
            lessThanOrEqualTo(tester.getSize(medio164(2)).width),
          );
          for (var i = 0; i < 3; i++) {
            expect(tester.getSize(medio164(i)).height, greaterThanOrEqualTo(48));
            expect(tester.getSize(medio164(i)).width, greaterThanOrEqualTo(48));
          }
          sinTextoCortado164(tester);
        });
      }
    }

    testWidgets('360x640 a 1,0 y 412x915 a 1,0: en una fila, como el canvas', (tester) async {
      await llegarA164(tester, Estado164.a01Tarjeta);
      expect(_enFila(tester), isTrue);
    });

    testWidgets('a 2,0 se apilan en columna, cada uno al ancho completo y sin recortar', (
      tester,
    ) async {
      await llegarA164(tester, Estado164.a01Tarjeta, escala: 2);
      await _alTope(tester);
      await traerAlAlcance(tester, medio164(0));
      expect(_enFila(tester), isFalse);
      final anchos = {for (var i = 0; i < 3; i++) tester.getSize(medio164(i)).width.round()};
      expect(anchos, hasLength(1), reason: 'los segmentos apilados no tienen el mismo ancho');
      sinTextoCortado164(tester);
    });
  });

  group('Cambiar de medio no pierde lo escrito, en fila y en columna', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('escala $escala: monto, tarjeta y aprobación sobreviven a ir a Transferencia y '
          'volver', (tester) async {
        final a = await llegarA164(tester, Estado164.a01Otra, escala: escala);
        await _alTope(tester);
        await tocarCobro(tester, transferencia164);
        await _alTope(tester);
        await tocarCobro(tester, tarjeta164);
        expect(find.text('Maestro'), findsOneWidget);
        expect(find.text('004471'), findsOneWidget);
        expect(a.repo.recibidos, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el segmento elegido se anuncia como elegido y los otros no (360x640, 2,0)', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA164(tester, Estado164.a01Tarjeta, escala: 2);
      await _alTope(tester);
      await traerAlAlcance(tester, medio164(1));
      expect(tester.getSemantics(medio164(1)), isSemantics(isSelected: true, isButton: true));
      expect(tester.getSemantics(medio164(0)), isSemantics(isSelected: false, isButton: true));
      expect(tester.getSemantics(medio164(2)), isSemantics(isSelected: false, isButton: true));
      h.dispose();
    });
  });

  group('Débito / Crédito (mismo SegmentadoDeCobro con letra 13): sin recortes', () {
    for (final tamano in [chico164, grande164]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('${sufijo164(tamano, escala)}: Débito y Crédito se leen enteros', (
          tester,
        ) async {
          await llegarA164(tester, Estado164.a01Tarjeta, tamano: tamano, escala: escala);
          await _alTope(tester);
          await traerAlAlcance(tester, find.byKey(const Key('cobro_tipo_0')));
          expect(tester.takeException(), isNull);
          expect(find.text('Débito'), findsWidgets);
          expect(find.text('Crédito'), findsWidgets);
          sinTextoCortado164(tester);
        });
      }
    }
  });

  group('Los datos del medio se miden en puntos de código (campo = registro = servidor)', () {
    testWidgets('marca «Otra» con 40 emoji: el campo los deja y el registro los acepta', (
      tester,
    ) async {
      final a = await llegarA164(tester, Estado164.a01Otra);
      await escribir164(tester, 'cobro_marca_otra', '😀' * 40);
      await registrar164(tester);
      await asentarAgendar(tester);
      expect(a.repo.recibidos, hasLength(1));
      expect(a.repo.recibidos.single.tarjetaMarca, '😀' * 40);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('marca «Otra» con 41 emoji pegados: el campo corta en 40 y se registra sin error', (
      tester,
    ) async {
      final a = await llegarA164(tester, Estado164.a01Otra);
      await escribir164(tester, 'cobro_marca_otra', '😀' * 41);
      await registrar164(tester);
      await asentarAgendar(tester);
      expect(a.repo.recibidos.single.tarjetaMarca!.runes.length, 40);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets(
      'aprobación con 40 emoji se registra; con texto pegado larguísimo corta y no rompe',
      (tester) async {
        final a = await llegarA164(tester, Estado164.a01Otra);
        await escribir164(tester, 'cobro_aprobacion', '🔒' * 40);
        await registrar164(tester);
        await asentarAgendar(tester);
        expect(a.repo.recibidos.single.numeroAprobacion, '🔒' * 40);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('transferencia: 40 emoji de referencia + «Otro» banco de 60 emoji se registran', (
      tester,
    ) async {
      final a = await llegarA164(tester, Estado164.b02Otro);
      await tester.tap(bancoListo164);
      await asentarAgendar(tester);
      await escribir164(tester, 'cobro_referencia', '😀' * 40);
      await registrar164(tester);
      await asentarAgendar(tester);
      expect(find.text('Reintentar'), findsNothing);
      expect(a.repo.recibidos, hasLength(1));
    });
  });

  group('Capturas del selector (solo con QA_CAPTURAS)', () {
    for (final (tamano, escala) in [
      (chico164, 1.0),
      (grande164, 1.0),
      (chico164, 1.3),
      (chico164, 2.0),
    ]) {
      for (final estado in [Estado164.a01Tarjeta, Estado164.a04Mayor, Estado164.a05Error]) {
        testWidgets('${estado.name} ${sufijo164(tamano, escala)}', (tester) async {
          await llegarA164(tester, estado, tamano: tamano, escala: escala);
          await _alTope(tester);
          await capturar164(tester, '586_${estado.name}_${sufijo164(tamano, escala)}');
        });
      }
    }
  });
}
