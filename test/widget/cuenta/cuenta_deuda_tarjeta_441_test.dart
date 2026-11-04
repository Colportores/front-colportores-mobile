// La tarjeta «Deuda con la casa editora» de Mi Cuenta (33A·01, HU-CTA-002, #441): el total que dijo el
// servidor por última vez, el toque que abre el detalle por pedido (33B) y los casos límite de la
// entrada: el doble toque, volver y reentrar, y la deuda que se vuelve a pedir al volver a la pestaña.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deuda_casa_arnes.dart';

Future<void> _montar(
  WidgetTester tester,
  RepositorioDeDeudaControlable deudaRepo, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  await montarCuenta(
    tester,
    RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
    tamano: tamano,
    escala: escala,
    overrides: overridesDeDeuda(deudaRepo),
  );
  // Lo guardado llega en un microtask y se pinta en el cuadro siguiente.
  await tester.pump();
}

void main() {
  const tarjeta = Key('cuenta_deuda');

  group('33A·01 · La tarjeta de la deuda', () {
    testWidgets('muestra el rótulo y el total que dijo el servidor, primera entre las tarjetas', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      await tester.pump();

      expect(find.text('DEUDA CON LA CASA EDITORA'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsOneWidget);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.text('▤'), findsOneWidget);
      expect(find.descendant(of: find.byKey(tarjeta), matching: find.text('›')), findsOneWidget);
      // Primera: arriba de En mano y Por cobrar.
      expect(
        tester.getTopLeft(find.byKey(tarjeta)).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('cuenta_enMano'))).dy),
      );
    });

    testWidgets('lo guardado se ve de entrada, antes de que el servidor conteste', (tester) async {
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await _montar(tester, repo);

      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(repo.pendientes, 1);
    });

    testWidgets('sin nada guardado ni servidor, solo el rótulo: ni cifra inventada ni \$ 0', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsNothing);

      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();

      expect(find.text('DEUDA CON LA CASA EDITORA'), findsOneWidget);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsNothing);
      expect(find.byKey(tarjeta), findsOneWidget);
    });

    testWidgets('sin deuda dice \$ 0', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      repo.responder(lectura(deuda(total: 0)));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('cuenta_deuda_monto')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('cuenta_deuda_monto'))).data, r'$ 0');
    });

    testWidgets('quedando a favor dice «A favor» con el monto', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      repo.responder(lectura(deuda(total: -1200, suma: 0)));
      await tester.pump();
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('cuenta_deuda_monto'))).data,
        r'A favor $ 1.200',
      );
    });

    testWidgets('el lector de pantalla la lee como botón, con el total', (tester) async {
      final manejador = tester.ensureSemantics();
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await _montar(tester, repo);

      final semantica = tester.getSemantics(find.byKey(tarjeta));
      expect(semantica.label, r'Deuda con la casa editora, $ 18.400');
      expect(semantica.flagsCollection.isButton, isTrue);
      manejador.dispose();
    });

    testWidgets('mide al menos 48 dp de alto y con el texto al 200 % sigue entera', (tester) async {
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await _montar(tester, repo, tamano: const Size(320, 568), escala: 2);

      expect(tester.getSize(find.byKey(tarjeta)).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });
  });

  group('La entrada a 33B', () {
    testWidgets('tocar la tarjeta abre la deuda por pedido; volver deja Mi Cuenta como estaba', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await _montar(tester, repo);

      await tester.tap(find.byKey(tarjeta));
      await tester.pumpAndSettle();
      expect(find.byType(DeudaCasaPage), findsOneWidget);
      expect(find.text('PEDIDOS CON SALDO'), findsOneWidget);
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);

      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      expect(find.byType(DeudaCasaPage), findsNothing);
      expect(find.byKey(const Key('cuenta_pestana')), findsOneWidget);
      expect(find.text(r'$ 18.400'), findsOneWidget);
    });

    testWidgets('dos toques seguidos abren una sola pantalla', (tester) async {
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await _montar(tester, repo);

      await tester.tap(find.byKey(tarjeta));
      await tester.tap(find.byKey(tarjeta), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(DeudaCasaPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      expect(find.byType(DeudaCasaPage), findsNothing);
    });

    testWidgets('ir, volver y reentrar varias veces no deja el toque trabado', (tester) async {
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await _montar(tester, repo);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(tarjeta));
        await tester.pumpAndSettle();
        expect(find.byType(DeudaCasaPage), findsOneWidget);
        await tester.tap(find.byKey(const Key('deuda_volver')));
        await tester.pumpAndSettle();
        expect(find.byType(DeudaCasaPage), findsNothing);
      }
    });

    testWidgets('con la tarjeta y la pantalla abiertas, la deuda se pide una sola vez al abrir', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      expect(repo.lecturas, 1);

      await tester.tap(find.byKey(tarjeta));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Abrirla mientras el primer pedido sigue en curso no suma otro.
      expect(repo.lecturas, 1);
      expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);

      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      await tester.pump();
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);
    });

    testWidgets('al abrirla con lo ya leído, se vuelve a pedir y lo nuevo aparece', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      await tester.pump();
      expect(repo.lecturas, 1);

      await tester.tap(find.byKey(tarjeta));
      await tester.pumpAndSettle();
      expect(repo.lecturas, 2);
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);

      repo.responder(lectura(deuda(total: 0)));
      await tester.pumpAndSettle();
      expect(find.text('No le debés nada a la casa editora'), findsOneWidget);
    });

    testWidgets(
      'sin nada guardado y sin conexión, el toque vuelve a pedir y, si sigue sin red, llega '
      'al error con «Reintentar»',
      (tester) async {
        final repo = RepositorioDeDeudaControlable();
        await _montar(tester, repo);
        repo.fallar(const FailureDeudaSinConexion());
        await tester.pump();
        await tester.pump();

        await tester.tap(find.byKey(tarjeta));
        await tester.pumpAndSettle();
        // Al abrir se vuelve a pedir: mientras tanto, la carga (no el error viejo ni un $ 0).
        expect(repo.lecturas, 2);
        expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);

        repo.fallar(const FailureDeudaSinConexion());
        await tester.pump();
        await tester.pump();

        expect(
          find.text('Necesitás conexión para ver tu deuda con la casa editora.'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsOneWidget);
      },
    );
  });

  group('Al volver a la pestaña', () {
    testWidgets(
      'la deuda se vuelve a pedir y lo último que llegó sigue a la vista mientras tanto',
      (tester) async {
        final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
        final cuentaRepo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
        await montarCuenta(tester, cuentaRepo, activa: false, overrides: overridesDeDeuda(repo));
        repo.responder(lectura(deudaDelCanvas));
        await tester.pump();
        await tester.pump();
        expect(repo.lecturas, 1);

        await cambiarActiva(tester, cuentaRepo, activa: true, overrides: overridesDeDeuda(repo));

        expect(repo.lecturas, 2);
        expect(find.text(r'$ 18.400'), findsOneWidget);
      },
    );
  });
}
