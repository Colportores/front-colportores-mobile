// La deuda con la casa editora (vista 33B, HU-CTA-002, #441): un test por artboard (33B·01 a 33B·03),
// los estados que el canvas no dibuja (cargando, sin conexión, a favor, los saldos que no dan el
// total) y los casos límite de cada flujo: el doble toque en «Reintentar», la falla a mitad, la lista
// larga, los textos largos y el texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/deuda_casa_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/deuda_casa_arnes.dart';

/// El color con que se dibuja el texto de la clave [clave].
Color? _color(WidgetTester tester, Key clave) =>
    tester.widget<Text>(find.byKey(clave)).style?.color;

void main() {
  group('33B·01 · Deuda por pedido', () {
    testWidgets('dado que tengo 2 pedidos con deuda, cuando abro «Deuda con la casa editora», se '
        'listan los 2 con su saldo y el total va arriba', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      await tester.pump();

      expect(find.text('MI CUENTA'), findsOneWidget);
      expect(find.text('Deuda con la casa editora'), findsOneWidget);
      expect(find.text('TOTAL'), findsOneWidget);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.text('PEDIDOS CON SALDO'), findsOneWidget);

      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);
      expect(find.text(r'Saldo $ 15.400'), findsOneWidget);
      expect(find.text('Salud y Hogar × 10 · Nuestros Hijos × 6'), findsOneWidget);
      expect(find.text(r'Pedido $ 37.400 · pagado $ 22.000'), findsOneWidget);

      expect(find.text('PEDIDO DEL 15/10'), findsOneWidget);
      expect(find.text(r'Saldo $ 3.000'), findsOneWidget);
      expect(find.text('Vida Feliz × 40'), findsOneWidget);
      expect(find.text(r'Pedido $ 4.800 · pagado $ 1.800'), findsOneWidget);
    });

    testWidgets('con 3 pedidos con deuda se listan los 3, el más viejo primero', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.responder(
        lectura(
          deuda(
            total: 600,
            pedidos: [
              pedido('p-1', DateTime.utc(2026, 9, 1, 15), monto: 300, pagado: 100),
              pedido('p-2', DateTime.utc(2026, 9, 8, 15), monto: 200, pagado: 0),
              pedido('p-3', DateTime.utc(2026, 9, 20, 15), monto: 200, pagado: 0),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('deuda_pedido_0')), findsOneWidget);
      expect(find.byKey(const Key('deuda_pedido_1')), findsOneWidget);
      expect(find.byKey(const Key('deuda_pedido_2')), findsOneWidget);
      expect(find.text(r'$ 600'), findsOneWidget);
      final arriba = tester.getTopLeft(find.text('PEDIDO DEL 01/09')).dy;
      expect(tester.getTopLeft(find.text('PEDIDO DEL 08/09')).dy, greaterThan(arriba));
      expect(
        tester.getTopLeft(find.text('PEDIDO DEL 20/09')).dy,
        greaterThan(tester.getTopLeft(find.text('PEDIDO DEL 08/09')).dy),
      );
    });

    testWidgets(
      'el total debido va en rojo, sin aviso ni aclaración cuando los saldos lo explican',
      (tester) async {
        final repo = RepositorioDeDeudaControlable();
        await montarDeuda(tester, repo);
        repo.responder(lectura(deudaDelCanvas));
        await tester.pump();
        await tester.pump();

        expect(_color(tester, const Key('deuda_total')), const Color(0xFFA8312A));
        expect(find.byKey(const Key('deuda_nota')), findsNothing);
        expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
        expect(find.text('Reintentar'), findsNothing);
      },
    );

    testWidgets('el lector de pantalla lee el total y cada pedido de una vez', (tester) async {
      final manejador = tester.ensureSemantics();
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      await tester.pump();

      expect(
        tester.getSemantics(find.byKey(const Key('deuda_total'))).label,
        contains(r'Total, $ 18.400'),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('deuda_pedido_0'))).label,
        r'Pedido del 02/10. Saldo $ 15.400. Salud y Hogar × 10 · Nuestros Hijos × 6. '
        r'Pedido $ 37.400 · pagado $ 22.000.',
      );
      manejador.dispose();
    });

    testWidgets('un pedido sin líneas no deja una línea vacía y sigue legible', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.responder(
        lectura(
          deuda(
            total: 100,
            pedidos: [pedido('p-1', DateTime.utc(2026, 9, 1, 15), monto: 100, pagado: 0)],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(r'Saldo $ 100'), findsOneWidget);
      expect(find.text(r'Pedido $ 100 · pagado $ 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('33B·02 · Sin deuda', () {
    testWidgets(
      'dado que no debo nada, veo el total en \$ 0 y «No le debés nada a la casa editora»',
      (tester) async {
        final repo = RepositorioDeDeudaControlable();
        await montarDeuda(tester, repo);
        repo.responder(lectura(deuda(total: 0)));
        await tester.pump();
        await tester.pump();

        expect(find.text(r'$ 0'), findsOneWidget);
        expect(find.text('No le debés nada a la casa editora'), findsOneWidget);
        expect(find.text('✓'), findsOneWidget);
        expect(find.text('PEDIDOS CON SALDO'), findsNothing);
        expect(find.byKey(const Key('deuda_nota')), findsNothing);
      },
    );
  });

  group('33B·03 · Error', () {
    testWidgets('sin nada guardado y con el servidor caído, «No pudimos traer tus pedidos.» con '
        '«Reintentar», nunca un \$ 0', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.fallar();
      await tester.pump();
      await tester.pump();

      expect(find.text('No pudimos traer tus pedidos.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text(r'$ 0'), findsNothing);
      expect(find.text('No le debés nada a la casa editora'), findsNothing);
      expect(find.text('TOTAL'), findsNothing);
    });

    testWidgets('sin nada guardado y sin conexión es el mismo error: no hay qué mostrar', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();

      expect(find.text('No pudimos traer tus pedidos.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('«Reintentar» vuelve a pedir, pasa por la carga y muestra la deuda', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.fallar();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);

      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      await tester.pump();
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.text('No pudimos traer tus pedidos.'), findsNothing);
      expect(repo.lecturas, 2);
    });

    testWidgets('si falla otra vez a mitad del reintento, el botón vuelve a estar habilitado y '
        'nada queda cargando', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.fallar();
      await tester.pump();
      await tester.pump();

      for (var intento = 2; intento <= 4; intento++) {
        await tester.tap(find.text('Reintentar'));
        await tester.pump();
        expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);
        repo.fallar();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('deuda_esqueleto_total')), findsNothing);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(repo.lecturas, intento);
      }
    });

    testWidgets(
      'dos toques seguidos en «Reintentar» antes de que termine el primero piden una sola '
      'vez',
      (tester) async {
        final repo = RepositorioDeDeudaControlable();
        await montarDeuda(tester, repo);
        repo.fallar();
        await tester.pump();
        await tester.pump();

        final boton = find.text('Reintentar');
        await tester.tap(boton);
        await tester.tap(boton, warnIfMissed: false);
        await tester.pump();

        expect(repo.lecturas, 2);
        expect(repo.pendientes, 1);
        repo.responder(lectura(deudaDelCanvas));
        await tester.pump();
        await tester.pump();
        expect(find.text(r'$ 18.400'), findsOneWidget);
      },
    );
  });

  group('Cargando', () {
    testWidgets('mientras el servidor no contesta y no hay nada guardado, tres bloques grises y el '
        'lector de pantalla dice qué se espera', (tester) async {
      final manejador = tester.ensureSemantics();
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);

      expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);
      expect(find.byKey(const Key('deuda_esqueleto_pedido_1')), findsOneWidget);
      expect(find.byKey(const Key('deuda_esqueleto_pedido_2')), findsOneWidget);
      expect(find.bySemanticsLabel('Cargando tu deuda con la casa editora'), findsOneWidget);
      expect(find.text('TOTAL'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
      manejador.dispose();
    });

    testWidgets(
      'con algo guardado se ve enseguida, sin pasar por la carga, mientras se actualiza',
      (tester) async {
        final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
        await montarDeuda(tester, repo);

        expect(find.byKey(const Key('deuda_esqueleto_total')), findsNothing);
        expect(find.text(r'$ 18.400'), findsOneWidget);
        expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
        expect(repo.pendientes, 1);

        repo.responder(lectura(deuda(total: 3000, pedidos: [deudaDelCanvas.pedidos.last])));
        await tester.pump();
        await tester.pump();
        expect(find.text(r'$ 18.400'), findsNothing);
        expect(find.text(r'$ 3.000'), findsOneWidget);
      },
    );
  });

  group('Sin conexión', () {
    final ayerALas21 = DateTime(2026, 11, 3, 21);

    testWidgets('sin conexión se ve lo último que llegó con el aviso de su hora (como 33A·02)', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deudaDelCanvas, leidaEn: ayerALas21),
      );
      await montarDeuda(tester, repo);
      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();

      expect(find.text('Sin conexión. Esta deuda es de ayer a las 21:00.'), findsOneWidget);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('lo guardado de hoy y de hace días dicen «de hoy» y «del 28/10»', (tester) async {
      final hoy = RepositorioDeDeudaControlable(
        guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 4, 7, 5)),
      );
      await montarDeuda(tester, hoy);
      hoy.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();
      expect(find.text('Sin conexión. Esta deuda es de hoy a las 07:05.'), findsOneWidget);

      // Se desmonta la primera pantalla: la segunda arranca de cero, con su propio repositorio.
      await tester.pumpWidget(const SizedBox());
      final viejo = RepositorioDeDeudaControlable(
        guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 10, 28, 9)),
      );
      await montarDeuda(tester, viejo);
      viejo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();
      expect(find.text('Sin conexión. Esta deuda es del 28/10 a las 09:00.'), findsOneWidget);
    });

    testWidgets('si el servidor falla sin que falte la conexión, lo guardado queda a la vista y el '
        'aviso no dice «sin conexión»', (tester) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deudaDelCanvas, leidaEn: ayerALas21),
      );
      await montarDeuda(tester, repo);
      repo.fallar();
      await tester.pump();
      await tester.pump();

      expect(
        find.text('No pudimos actualizarla. Esta deuda es de ayer a las 21:00.'),
        findsOneWidget,
      );
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsNothing);
      // Decisión del 04/11: «No pudimos actualizarla…» se puede reintentar.
      expect(find.text('Reintentar'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('cuenta_reintentar'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('«Reintentar» de lo guardado pide de nuevo, deja lo guardado a la vista y dos '
        'toques seguidos piden una sola vez', (tester) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deudaDelCanvas, leidaEn: ayerALas21),
      );
      await montarDeuda(tester, repo);
      repo.fallar();
      await tester.pump();
      await tester.pump();
      expect(repo.lecturas, 1);

      await tester.tap(find.byKey(const Key('cuenta_reintentar')));
      await tester.tap(find.byKey(const Key('cuenta_reintentar')), warnIfMissed: false);
      await tester.pump();
      await tester.pump();

      expect(repo.lecturas, 2);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.textContaining('No pudimos actualizarla'), findsNothing);
      expect(find.text(r'$ 18.400'), findsOneWidget);

      // Y si falla otra vez, el botón vuelve.
      repo.fallar();
      await tester.pump();
      await tester.pump();
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('al volver a pedir, el aviso se va, lo guardado sigue a la vista y lo nuevo '
        'reemplaza a lo viejo; dos pedidos seguidos cuentan como uno', (tester) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deudaDelCanvas, leidaEn: ayerALas21),
      );
      await montarDeuda(tester, repo);
      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsOneWidget);
      expect(repo.lecturas, 1);

      final notifier = ProviderScope.containerOf(
        tester.element(find.byType(DeudaCasaPage)),
      ).read(deudaConLaCasaProvider('col-1').notifier);
      unawaited(notifier.actualizar());
      unawaited(notifier.actualizar());
      await tester.pump();

      expect(repo.lecturas, 2);
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
      expect(find.text(r'$ 18.400'), findsOneWidget);

      repo.responder(lectura(deuda(total: 3000, pedidos: [deudaDelCanvas.pedidos.last])));
      await tester.pump();
      await tester.pump();
      expect(find.text(r'$ 3.000'), findsWidgets);
      expect(find.text(r'$ 18.400'), findsNothing);
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
    });
  });

  group('A favor (decisión de Cristian, 25/10, «Pago de más»)', () {
    testWidgets('si se pagó de más, el total dice «A favor» con el monto y que se descuenta de la '
        'próxima deuda; no queda en \$ 0 ni dice que no debe nada', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      repo.responder(lectura(deuda(total: -1200, suma: 0, depositos: 5000)));
      await tester.pump();
      await tester.pump();

      expect(find.text(r'A favor $ 1.200'), findsOneWidget);
      expect(find.text('Se descuenta de tu próxima deuda con la casa editora.'), findsOneWidget);
      expect(find.text('No le debés nada a la casa editora'), findsNothing);
      expect(find.text(r'$ 0'), findsNothing);
      expect(find.byKey(const Key('deuda_nota')), findsNothing);
      expect(_color(tester, const Key('deuda_total')), const Color(0xFF1F6E3A));
    });
  });

  group('Los saldos que no dan el total (decisión de Cristian, 03/11, «Pagado ped.»)', () {
    const aclaracion =
        'La suma de los saldos no da el total: una transferencia o el alquiler movieron tu deuda. '
        'El total de arriba es el real.';

    testWidgets(
      'si la suma de los saldos no da el total, la pantalla lo aclara y el total que manda '
      'es el real',
      (tester) async {
        final repo = RepositorioDeDeudaControlable();
        await montarDeuda(tester, repo);
        repo.responder(lectura(deuda(total: 20000, suma: 18400, pedidos: deudaDelCanvas.pedidos)));
        await tester.pump();
        await tester.pump();

        expect(find.text(r'$ 20.000'), findsOneWidget);
        expect(find.text(aclaracion), findsOneWidget);
        expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);
      },
    );

    testWidgets(
      'con deuda real pero ningún pedido que la explique no dice «no debés nada» y aclara',
      (tester) async {
        final repo = RepositorioDeDeudaControlable();
        await montarDeuda(tester, repo);
        repo.responder(lectura(deuda(total: 5000)));
        await tester.pump();
        await tester.pump();

        expect(find.text(r'$ 5.000'), findsOneWidget);
        expect(find.text('No le debés nada a la casa editora'), findsNothing);
        expect(find.text('PEDIDOS CON SALDO'), findsNothing);
        expect(find.text(aclaracion), findsOneWidget);
      },
    );

    testWidgets(
      'con pedidos con saldo pero la deuda real en cero, no dice «no debés nada» y aclara',
      (tester) async {
        final repo = RepositorioDeDeudaControlable();
        await montarDeuda(tester, repo);
        repo.responder(lectura(deuda(total: 0, pedidos: [deudaDelCanvas.pedidos.last])));
        await tester.pump();
        await tester.pump();

        expect(find.text(r'$ 0'), findsOneWidget);
        expect(find.text('No le debés nada a la casa editora'), findsNothing);
        expect(find.text('PEDIDO DEL 15/10'), findsOneWidget);
        expect(find.text(aclaracion), findsOneWidget);
      },
    );
  });

  group('Casos límite', () {
    testWidgets('una lista larga de pedidos se arma de a poco y el último se alcanza', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo, tamano: const Size(360, 640));
      final pedidos = [
        for (var i = 0; i < 80; i++)
          pedido(
            'p-$i',
            DateTime.utc(2026, 1, 1 + (i % 28), 15).add(Duration(days: i ~/ 28 * 31)),
            monto: 1000 + i,
            pagado: 0,
            lineas: [LineaDePedido(nombre: 'Libro $i', cantidad: i + 1)],
          ),
      ];
      repo.responder(lectura(deuda(total: 80000, suma: 80000 + 3160, pedidos: pedidos)));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('deuda_pedido_79')), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('deuda_pedido_79')),
        400,
        scrollable: find.descendant(
          of: find.byKey(const Key('deuda_lista')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(const Key('deuda_pedido_79')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final tamano in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets('nombres largos y montos de 11 cifras a ${tamano.width.toInt()}x'
            '${tamano.height.toInt()} con el texto a $escala no se cortan ni desbordan', (
          tester,
        ) async {
          final repo = RepositorioDeDeudaControlable();
          await montarDeuda(tester, repo, tamano: tamano, escala: escala);
          repo.responder(
            lectura(
              deuda(
                total: 99999999999,
                pedidos: [
                  pedido(
                    'p-1',
                    DateTime.utc(2026, 10, 2, 15),
                    monto: 99999999999,
                    pagado: 0,
                    lineas: const [
                      LineaDePedido(
                        nombre:
                            'Un título larguísimo de libro que no entra en una sola línea ni a tiros',
                        cantidad: 100000,
                      ),
                      LineaDePedido(nombre: 'Otro título bastante largo también', cantidad: 12),
                    ],
                  ),
                ],
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.textContaining('99.999.999.999'), findsWidgets);
          // El total de arriba se achica antes que cortarse: la caja que lo contiene entra en el
          // ancho de la pantalla (el texto se dibuja escalado dentro de ella).
          final caja = find.ancestor(
            of: find.byKey(const Key('deuda_total')),
            matching: find.byType(FittedBox),
          );
          expect(tester.getSize(caja).width, lessThanOrEqualTo(tamano.width));
        });
      }
    }

    testWidgets('el botón de volver mide al menos 48 dp y vuelve atrás', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_conRutaAnterior(repo));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final tamano = tester.getSize(find.byKey(const Key('deuda_volver')));
      expect(tamano.width, greaterThanOrEqualTo(48));
      expect(tamano.height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deuda_lista')), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
    });

    testWidgets('si el servidor contesta cuando la pantalla ya se cerró, no pasa nada', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await montarDeuda(tester, repo);
      await tester.pumpWidget(const SizedBox());

      repo.responder(lectura(deudaDelCanvas));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

/// Una pantalla con un botón «abrir» que abre la deuda encima, como la tarjeta de Mi Cuenta.
Widget _conRutaAnterior(RepositorioDeDeudaControlable repo) => ProviderScope(
  overrides: overridesDeDeuda(repo),
  child: MaterialApp(
    theme: temaClaro(),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => DeudaCasaPage.abrir(context, colportorId: 'col-1'),
          child: const Text('abrir'),
        ),
      ),
    ),
  ),
);
