// QA de la pestaña «Cuenta» (vista 33A, HU-CTA-001, #170): lo que el test del implementador no mide.
// Las cuatro guías de accesibilidad de Flutter (toque de Android e iOS, etiqueta, contraste) en cada
// estado de la vista (datos, cuenta nueva, cargando, error), a 360x640 y 412x915 con el texto al
// 100 % y al 200 %, y los casos de reentrada después de un error.
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

/// Cada estado de la vista, listo para montarse: (nombre, cómo se arma el repositorio).
final _estados = <String, RepositorioDeCuentaControlable Function()>{
  '33A·01 datos': () => RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
  '33A·04 cuenta nueva': () => RepositorioDeCuentaControlable(inicial: resumenCuentaNueva),
  '33A·03 cargando': () => RepositorioDeCuentaControlable(),
  '33A·05 error': () => RepositorioDeCuentaControlable()..fallaAlSuscribir = true,
};

void main() {
  group('accesibilidad por estado', () {
    for (final estado in _estados.entries) {
      for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.key} a ${tam.key}, texto $escala: toque, etiqueta y contraste', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            await montarCuenta(tester, estado.value(), tamano: tam.value, escala: escala);
            await tester.pump();

            final falla = tester.takeException();
            expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('reentrada después de un error', () {
    testWidgets(
      'dado que la cuenta falló, cuando vuelvo a la pestaña y la base ya se lee, veo las cifras '
      'sin tocar «Reintentar»',
      (tester) async {
        final repo = RepositorioDeCuentaControlable()..fallaAlSuscribir = true;
        await montarCuenta(tester, repo, activa: false);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cuenta_reintentar')), findsOneWidget);

        repo
          ..fallaAlSuscribir = false
          ..inicial = resumenDelCanvas;
        await cambiarActiva(tester, repo, activa: true);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('cuenta_reintentar')), findsNothing);
        expect(find.text(r'$ 2.400'), findsOneWidget);
        expect(find.text(r'$ 9.700'), findsOneWidget);
      },
    );

    testWidgets('si la base se recupera sola, las cifras reemplazan al error', (tester) async {
      final repo = RepositorioDeCuentaControlable();
      await montarCuenta(tester, repo);
      repo.fallar();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_error_texto')), findsOneWidget);

      repo.emitir(resumenDelCanvas);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cuenta_error_texto')), findsNothing);
      expect(find.text(r'$ 2.400'), findsOneWidget);
    });

    testWidgets('tres «Reintentar» seguidos que fallan: el botón vuelve cada vez y nunca queda un '
        'esqueleto trabado', (tester) async {
      final repo = RepositorioDeCuentaControlable()..fallaAlSuscribir = true;
      await montarCuenta(tester, repo);
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('cuenta_reintentar')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cuenta_reintentar')), findsOneWidget, reason: 'vuelta $i');
        expect(find.byKey(const Key('cuenta_esqueleto_enMano')), findsNothing, reason: 'vuelta $i');
      }
      expect(repo.suscripciones, 4);
    });
  });

  group('datos límite', () {
    testWidgets('«En mano» que quedó en cero después de depositar dice cuánto bajó y no aconseja '
        'depositar', (tester) async {
      final repo = RepositorioDeCuentaControlable(
        inicial: ResumenDeCuenta(enMano: cifra(0, variacion: -2400), porCobrar: cifra(0)),
      );
      await montarCuenta(tester, repo);

      expect(find.text(r'▼ $ 2.400 contra la semana pasada'), findsOneWidget);
      expect(find.textContaining('depositalo'), findsNothing);
    });

    testWidgets('las dos cifras en cero pero con comparación dicen «Igual que la semana pasada», '
        'no «Sin datos»', (tester) async {
      final repo = RepositorioDeCuentaControlable(
        inicial: ResumenDeCuenta(enMano: cifra(0, variacion: 0), porCobrar: cifra(0, variacion: 0)),
      );
      await montarCuenta(tester, repo);

      expect(find.text('Igual que la semana pasada'), findsNWidgets(2));
      expect(find.text('Sin datos de la semana anterior'), findsNothing);
    });
  });
}
