// La línea «Alquiler» de Mi Cuenta (vista 33A·01, HU-CTA-007, #389): aparece solo si alguna campaña del
// colportor cobra alquiler, dice lo que falta pagar, se actualiza sola y abre «Mi alquiler». Y la nota
// de la deuda con la casa editora (33B) que dice de dónde viene el descuento del alquiler pagado de más.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/alquiler_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alquiler_arnes.dart';
import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deuda_casa_arnes.dart';

Future<RepositorioDeAlquilerControlable> _cuenta(
  WidgetTester tester,
  RepositorioDeAlquilerControlable alquiler, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  await montarCuenta(
    tester,
    RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
    tamano: tamano,
    escala: escala,
    overrides: overridesDeAlquiler(alquiler),
  );
  await tester.pump();
  return alquiler;
}

void main() {
  group('33A·01 · La línea «Alquiler»', () {
    testWidgets('dado que mi campaña no cobra alquiler, cuando abro «Mi cuenta», no veo ninguna '
        'línea de alquiler', (tester) async {
      await _cuenta(tester, RepositorioDeAlquilerControlable(inicial: AlquilerDelColportor.vacio));

      expect(find.byKey(const Key('cuenta_fila_alquiler')), findsNothing);
      expect(find.textContaining('Alquiler'), findsNothing);
    });

    testWidgets('dado que debo alquiler, la línea dice cuánto falta pagar', (tester) async {
      await _cuenta(tester, RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas));

      expect(find.text('Alquiler'), findsOneWidget);
      expect(find.text(r'$ 12.500 por pagar'), findsOneWidget);
    });

    testWidgets('dado que no debo nada, la línea dice «Al día» en verde', (tester) async {
      await _cuenta(tester, RepositorioDeAlquilerControlable(inicial: alquilerPagado));

      final valor = tester.widget<Text>(find.byKey(const Key('cuenta_fila_alquiler_valor')));
      expect(valor.data, 'Al día');
      expect(valor.style?.color, const Color(0xFF1F6E3A));
    });

    testWidgets('con dos campañas suma lo que falta de las dos', (tester) async {
      await _cuenta(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon([
            campaniaCon(id: 'c-1', pagos: [pagoDe(6000)]),
            campaniaCon(id: 'c-2', monto: 10000),
          ]),
        ),
      );

      expect(find.text(r'$ 22.500 por pagar'), findsOneWidget);
    });

    testWidgets('no es parte de «Deuda»: la deuda con la casa editora no se mueve y la línea va '
        'aparte, después de las acciones', (tester) async {
      await _cuenta(tester, RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas));

      final acciones = tester.getTopLeft(find.text('Registrar depósito')).dy;
      final fila = tester.getTopLeft(find.byKey(const Key('cuenta_fila_alquiler'))).dy;
      expect(fila, greaterThan(acciones));
      expect(find.byKey(const Key('cuenta_deuda')), findsOneWidget);
    });

    testWidgets('el lector de pantalla la lee como un botón con lo que falta', (tester) async {
      final manejador = tester.ensureSemantics();
      await _cuenta(tester, RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas));

      final nodo = tester.getSemantics(find.byKey(const Key('cuenta_fila_alquiler')));
      expect(nodo.label, r'Alquiler, $ 12.500 por pagar');
      expect(nodo.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        tester.getSize(find.byKey(const Key('cuenta_fila_alquiler'))).height,
        greaterThanOrEqualTo(48),
      );
      manejador.dispose();
    });

    testWidgets('mientras se arma o si falla, no hay línea (y Mi Cuenta sigue entera)', (
      tester,
    ) async {
      final cargando = await _cuenta(tester, RepositorioDeAlquilerControlable());
      expect(find.byKey(const Key('cuenta_fila_alquiler')), findsNothing);
      expect(find.text(r'$ 2.400'), findsOneWidget);

      cargando.fallar();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_fila_alquiler')), findsNothing);
      expect(find.text(r'$ 2.400'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'se actualiza sola: aparece cuando una campaña pasa a cobrar y cambia cuando baja un '
      'pago',
      (tester) async {
        final repo = await _cuenta(
          tester,
          RepositorioDeAlquilerControlable(inicial: AlquilerDelColportor.vacio),
        );
        expect(find.byKey(const Key('cuenta_fila_alquiler')), findsNothing);

        repo.emitir(alquilerDelCanvas);
        await tester.pumpAndSettle();
        expect(find.text(r'$ 12.500 por pagar'), findsOneWidget);

        repo.emitir(alquilerPagado);
        await tester.pumpAndSettle();
        expect(find.text('Al día'), findsOneWidget);

        repo.emitir(AlquilerDelColportor.vacio);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cuenta_fila_alquiler')), findsNothing);
      },
    );

    testWidgets(
      'al tocarla abre «Mi alquiler»; un doble toque abre una sola pantalla y al volver se '
      'puede abrir de nuevo',
      (tester) async {
        await _cuenta(tester, RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas));

        await tester.tap(find.byKey(const Key('cuenta_fila_alquiler')));
        await tester.tap(find.byKey(const Key('cuenta_fila_alquiler')), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(AlquilerPage), findsOneWidget);
        expect(find.text('TE FALTA PAGAR'), findsOneWidget);

        await tester.tap(find.byKey(const Key('alquiler_volver')));
        await tester.pumpAndSettle();
        expect(find.byType(AlquilerPage), findsNothing);
        expect(find.byKey(const Key('cuenta_pestana')), findsOneWidget);

        await tester.tap(find.byKey(const Key('cuenta_fila_alquiler')));
        await tester.pumpAndSettle();
        expect(find.byType(AlquilerPage), findsOneWidget);
      },
    );

    for (final tamano in const [Size(320, 568), Size(390, 844)]) {
      testWidgets(
        'con el texto al 200 % a ${tamano.width.toInt()} dp la línea se lee entera y nada '
        'desborda',
        (tester) async {
          await _cuenta(
            tester,
            RepositorioDeAlquilerControlable(
              inicial: alquilerCon([
                campaniaCon(monto: 123456789, pagos: [pagoDe(6000)]),
              ]),
            ),
            tamano: tamano,
            escala: 2,
          );

          await tester.scrollUntilVisible(
            find.byKey(const Key('cuenta_fila_alquiler')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('cuenta_fila_alquiler_valor')), findsOneWidget);
        },
      );
    }
  });

  group('33B · La deuda con la casa editora dice de dónde viene el descuento del alquiler', () {
    Future<void> montarDeudaConAlquiler(
      WidgetTester tester,
      RepositorioDeAlquilerControlable alquiler,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overridesDeDeuda(repo),
            alquilerRepositoryProvider.overrideWithValue(alquiler),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: const DeudaCasaPage(colportorId: 'col-1'),
          ),
        ),
      );
      await tester.pump();
      repo.responder(lectura(deudaDelCanvas));
      await tester.pumpAndSettle();
    }

    testWidgets('dado que el servidor trasladó \$ 500 de más del alquiler, la deuda lo dice', (
      tester,
    ) async {
      await montarDeudaConAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon([
            campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
          ], trasladado: 500),
        ),
      );

      expect(find.text(r'Incluye $ 500 que pagaste de más en el alquiler.'), findsOneWidget);
    });

    testWidgets('sin alquiler pagado de más, o sin alquiler, la deuda no dice nada', (
      tester,
    ) async {
      await montarDeudaConAlquiler(
        tester,
        RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas),
      );
      expect(find.byKey(const Key('deuda_nota_alquiler')), findsNothing);
    });

    testWidgets('sin traslado del servidor la deuda no dice nada aunque los pagos pasen el monto', (
      tester,
    ) async {
      await montarDeudaConAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon([
            campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
          ]),
        ),
      );

      expect(find.byKey(const Key('deuda_nota_alquiler')), findsNothing);
    });

    testWidgets('quien se dio de baja y ya no tiene campañas igual ve el traslado en la deuda', (
      tester,
    ) async {
      await montarDeudaConAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: const AlquilerDelColportor(campanias: [], trasladadoCentavos: 50000),
        ),
      );

      expect(find.text(r'Incluye $ 500 que pagaste de más en el alquiler.'), findsOneWidget);
    });

    testWidgets('si el alquiler no se puede leer, la deuda se ve igual, sin la nota', (
      tester,
    ) async {
      final alquiler = RepositorioDeAlquilerControlable()..fallaAlSuscribir = true;
      await montarDeudaConAlquiler(tester, alquiler);

      expect(find.byKey(const Key('deuda_nota_alquiler')), findsNothing);
      expect(find.text(r'$ 18.400'), findsOneWidget);
    });

    testWidgets('la nota aparece cuando baja el pago de más, sin recargar', (tester) async {
      final alquiler = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarDeudaConAlquiler(tester, alquiler);
      expect(find.byKey(const Key('deuda_nota_alquiler')), findsNothing);

      alquiler.emitir(
        alquilerCon([
          campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
        ], trasladado: 500),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('deuda_nota_alquiler')), findsOneWidget);
    });
  });
}
