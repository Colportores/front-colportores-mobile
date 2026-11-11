// La tarjeta «Deuda con la casa editora» de Mi Cuenta (33A·01, #642): la línea de abajo con cuánto
// cambió la deuda contra la semana pasada (la deuda de hace 7 días la registra el servidor, backend-supabase
// 0168) y la tarjeta sin lectura, que dice por qué no hay cifra: leyendo (33A·03), sin conexión o con una
// falla del servidor (decisión del orquestador, 04/11, por el mapa: estados que no se saben).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
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

/// El servidor contesta [deuda] y la tarjeta la dibuja.
Future<void> _responder(
  WidgetTester tester,
  RepositorioDeDeudaControlable repo,
  DeudaConLaCasa deuda,
) async {
  repo.responder(lectura(deuda));
  await tester.pump();
  await tester.pump();
}

void main() {
  const tarjeta = Key('cuenta_deuda');
  const variacion = Key('cuenta_deuda_variacion');
  const sinLectura = Key('cuenta_deuda_sin_lectura');
  const cargando = Key('cuenta_deuda_cargando');

  String textoDe(WidgetTester tester, Key llave) => tester.widget<Text>(find.byKey(llave)).data!;

  group('33A·01 · cuánto cambió la deuda contra la semana pasada', () {
    testWidgets('el canvas: de \$ 20.500 a \$ 18.400 dice «▼ \$ 2.100 contra la semana pasada», en '
        'verde', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      await _responder(tester, repo, deuda(total: 18400, haceUnaSemana: 20500));

      expect(textoDe(tester, variacion), r'▼ $ 2.100 contra la semana pasada');
      expect(tester.widget<Text>(find.byKey(variacion)).style!.color, const Color(0xFF1F6E3A));
      expect(find.text(r'$ 18.400'), findsOneWidget);
    });

    testWidgets('si la deuda subió dice «▲» con la diferencia, en gris', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      await _responder(tester, repo, deuda(total: 18400, haceUnaSemana: 15000));

      expect(textoDe(tester, variacion), r'▲ $ 3.400 contra la semana pasada');
      expect(tester.widget<Text>(find.byKey(variacion)).style!.color, const Color(0xFF5B6B82));
    });

    testWidgets('si no se movió dice «Igual que la semana pasada»', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      await _responder(tester, repo, deuda(total: 18400, haceUnaSemana: 18400));

      expect(textoDe(tester, variacion), 'Igual que la semana pasada');
    });

    testWidgets('sin registro de hace 7 días dice «Sin datos de la semana anterior», no «igual»', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      await _responder(tester, repo, deuda(total: 18400));

      expect(textoDe(tester, variacion), 'Sin datos de la semana anterior');
      expect(tester.widget<Text>(find.byKey(variacion)).style!.color, const Color(0xFF5B6B82));
    });

    testWidgets('sin deuda hoy y con deuda hace una semana: «▼» con todo lo que debía', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      await _responder(tester, repo, deuda(total: 0, haceUnaSemana: 5000));

      expect(textoDe(tester, variacion), r'▼ $ 5.000 contra la semana pasada');
    });

    testWidgets('quedar a favor cuenta como deuda negativa: de \$ 500 a «A favor \$ 1.200» baja \$ '
        '1.700', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      await _responder(tester, repo, deuda(total: -1200, suma: 0, haceUnaSemana: 500));

      expect(textoDe(tester, const Key('cuenta_deuda_monto')), r'A favor $ 1.200');
      expect(textoDe(tester, variacion), r'▼ $ 1.700 contra la semana pasada');
    });

    testWidgets('lo guardado también muestra la línea, antes de que el servidor conteste', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deuda(total: 18400, haceUnaSemana: 20500)),
      );
      await _montar(tester, repo);

      expect(textoDe(tester, variacion), r'▼ $ 2.100 contra la semana pasada');
      expect(repo.pendientes, 1);
    });

    testWidgets('el lector de pantalla lee el total y la variación, como botón', (tester) async {
      final manejador = tester.ensureSemantics();
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deuda(total: 18400, haceUnaSemana: 20500)),
      );
      await _montar(tester, repo);

      final semantica = tester.getSemantics(find.byKey(tarjeta));
      expect(
        semantica.label,
        r'Deuda con la casa editora, $ 18.400. Bajó $ 2.100 contra la semana pasada',
      );
      expect(semantica.flagsCollection.isButton, isTrue);
      manejador.dispose();
    });

    testWidgets('sin registro de hace 7 días el lector dice «Sin datos de la semana anterior»', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDelCanvas));
      await _montar(tester, repo);

      expect(
        tester.getSemantics(find.byKey(tarjeta)).label,
        r'Deuda con la casa editora, $ 18.400. Sin datos de la semana anterior',
      );
      manejador.dispose();
    });

    testWidgets('si el servidor contesta otra deuda, la línea se actualiza', (tester) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deuda(total: 18400, haceUnaSemana: 20500)),
      );
      await _montar(tester, repo);

      await _responder(tester, repo, deuda(total: 20000, haceUnaSemana: 18400));

      expect(textoDe(tester, variacion), r'▲ $ 1.600 contra la semana pasada');
    });

    testWidgets(
      'a 320 dp con el texto al 200 % la línea larga se parte y la tarjeta queda entera',
      (tester) async {
        final repo = RepositorioDeDeudaControlable(
          guardada: lectura(deuda(total: 18400, haceUnaSemana: 20500)),
        );
        await _montar(tester, repo, tamano: const Size(320, 568), escala: 2);

        expect(find.byKey(variacion), findsOneWidget);
        expect(tester.getSize(find.byKey(tarjeta)).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('con un monto enorme y el texto al 300 % no desborda', (tester) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deuda(total: 123456789, haceUnaSemana: 100000000)),
      );
      await _montar(tester, repo, tamano: const Size(320, 568), escala: 3);

      expect(find.byKey(variacion), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Tarjeta sin lectura: dice por qué no hay cifra', () {
    testWidgets('33A·03 mientras lee: el bloque gris bajo el rótulo, sin cifra ni texto', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      expect(find.byKey(cargando), findsOneWidget);
      expect(find.byKey(sinLectura), findsNothing);
      expect(find.byKey(variacion), findsNothing);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsNothing);
      expect(find.text('DEUDA CON LA CASA EDITORA'), findsOneWidget);
    });

    testWidgets(
      'mientras lee, el lector de pantalla dice «Cargando tu deuda con la casa editora»',
      (tester) async {
        final manejador = tester.ensureSemantics();
        final repo = RepositorioDeDeudaControlable();
        await _montar(tester, repo);

        expect(
          tester.getSemantics(find.byKey(tarjeta)).label,
          'Deuda con la casa editora. Cargando tu deuda con la casa editora',
        );
        manejador.dispose();
      },
    );

    testWidgets('sin conexión y sin nada guardado: «Necesitás conexión para ver tu deuda con la '
        'casa editora.»', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();

      expect(
        textoDe(tester, sinLectura),
        'Necesitás conexión para ver tu deuda con la casa editora.',
      );
      expect(tester.widget<Text>(find.byKey(sinLectura)).style!.color, const Color(0xFF5B6B82));
      expect(find.byKey(cargando), findsNothing);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsNothing);
    });

    testWidgets('con red y una falla del servidor: «No pudimos traer tu deuda con la casa '
        'editora.»', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      repo.fallar();
      await tester.pump();
      await tester.pump();

      expect(textoDe(tester, sinLectura), 'No pudimos traer tu deuda con la casa editora.');
      expect(find.byKey(cargando), findsNothing);
    });

    testWidgets('el lector de pantalla lee la línea de cada falla', (tester) async {
      final manejador = tester.ensureSemantics();
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(tarjeta)).label,
        'Deuda con la casa editora. Necesitás conexión para ver tu deuda con la casa editora.',
      );

      await tester.tap(find.byKey(tarjeta));
      await tester.pumpAndSettle();
      repo.fallar();
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.byKey(tarjeta)).label,
        'Deuda con la casa editora. No pudimos traer tu deuda con la casa editora.',
      );
      manejador.dispose();
    });

    testWidgets('de leyendo pasa a la cifra con su línea cuando llega la respuesta', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      expect(find.byKey(cargando), findsOneWidget);

      await _responder(tester, repo, deuda(total: 18400, haceUnaSemana: 20500));

      expect(find.byKey(cargando), findsNothing);
      expect(find.byKey(sinLectura), findsNothing);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.byKey(variacion), findsOneWidget);
    });

    testWidgets('tras la falla, tocar la tarjeta vuelve a pedir y mientras tanto muestra el bloque '
        'gris, no el error viejo', (tester) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);
      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();
      expect(find.byKey(sinLectura), findsOneWidget);

      await tester.tap(find.byKey(tarjeta));
      await tester.pumpAndSettle();
      // Al abrir el detalle se pidió de nuevo; volviendo a Mi Cuenta la tarjeta sigue la misma lectura.
      expect(repo.lecturas, 2);
      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      expect(find.byKey(cargando), findsOneWidget);
      expect(find.byKey(sinLectura), findsNothing);

      repo.fallar();
      await tester.pump();
      await tester.pump();
      expect(textoDe(tester, sinLectura), 'No pudimos traer tu deuda con la casa editora.');
    });

    testWidgets('con una lectura guardada que ya no se actualiza, queda la cifra (no la línea de '
        'falla)', (tester) async {
      final repo = RepositorioDeDeudaControlable(
        guardada: lectura(deuda(total: 18400, haceUnaSemana: 20500)),
      );
      await _montar(tester, repo);

      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();

      expect(find.byKey(sinLectura), findsNothing);
      expect(find.byKey(cargando), findsNothing);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.byKey(variacion), findsOneWidget);
    });

    testWidgets('a 320 dp con el texto al 200 % cada línea se parte y la tarjeta queda entera', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo, tamano: const Size(320, 568), escala: 2);
      expect(find.byKey(cargando), findsOneWidget);
      expect(tester.takeException(), isNull);

      repo.fallar(const FailureDeudaSinConexion());
      await tester.pump();
      await tester.pump();

      expect(find.byKey(sinLectura), findsOneWidget);
      expect(tester.getSize(find.byKey(tarjeta)).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
    });

    testWidgets('el toque abre el detalle aunque no haya lectura, y vuelve sin trabarse', (
      tester,
    ) async {
      final repo = RepositorioDeDeudaControlable();
      await _montar(tester, repo);

      await tester.tap(find.byKey(tarjeta));
      await tester.tap(find.byKey(tarjeta), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deuda_volver')), findsOneWidget);

      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(tarjeta));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deuda_volver')), findsOneWidget);
    });
  });
}
