// La pestaña «Cuenta» (vista 33A, HU-CTA-001, #170): un test por artboard (33A·01 a 33A·05) y los casos
// límite de cada flujo: el error que se reintenta, la falla después de los primeros datos, el volver a
// la pestaña, los montos largos y el texto al 200 %.
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

/// Lo que el lector de pantalla dice de una tarjeta.
String _etiqueta(WidgetTester tester, Key tarjeta) =>
    tester.getSemantics(find.byKey(tarjeta)).label;

void main() {
  group('33A·01 · Resumen', () {
    testWidgets('dado que tengo movimientos, cuando abro «Mi cuenta», veo En mano y Por cobrar con '
        'su total y cuánto cambiaron contra la semana pasada', (tester) async {
      await montarCuenta(tester, RepositorioDeCuentaControlable(inicial: resumenDelCanvas));

      expect(find.text('CUENTA'), findsOneWidget);
      expect(find.text('Mi Cuenta'), findsOneWidget);
      expect(find.text('EN MANO'), findsOneWidget);
      expect(find.text(r'$ 2.400'), findsOneWidget);
      expect(find.text(r'▲ $ 1.800 · depositalo pronto'), findsOneWidget);
      expect(find.text('POR COBRAR'), findsOneWidget);
      expect(find.text(r'$ 9.700'), findsOneWidget);
      expect(find.text(r'▼ $ 1.300 contra la semana pasada'), findsOneWidget);
    });

    testWidgets('en V1 no se dibuja nada de lo V2 ni lo que no lleva a ningún lado: ni deuda, ni '
        'acciones, ni enlaces, ni previews, ni «Próximamente»', (tester) async {
      await montarCuenta(tester, RepositorioDeCuentaControlable(inicial: resumenDelCanvas));

      for (final texto in [
        'DEUDA CON LA CASA EDITORA',
        'DEPOSITADO',
        '+ Hacer un pedido',
        'Cargar ticket',
        'Registrar depósito',
        'Mis pedidos',
        'Mis tickets',
        'Alquiler',
        'Stock y beca',
        'TAMBIÉN',
        'Stock',
        'Beca',
        'Próximamente',
      ]) {
        expect(find.textContaining(texto), findsNothing, reason: texto);
      }
      // Lo único que se toca son las dos tarjetas, que abren su detalle en «Mi plata» (HU-CTA-003).
      expect(find.text('›'), findsNWidgets(2));
      expect(find.byType(InkWell), findsNWidgets(2));
    });

    testWidgets('una cifra que subió y una que bajó se leen con su verbo, sin las flechas', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await montarCuenta(tester, RepositorioDeCuentaControlable(inicial: resumenDelCanvas));

      expect(
        _etiqueta(tester, const Key('cuenta_enMano')),
        r'En mano, $ 2.400. Subió $ 1.800 contra la semana pasada. Depositalo pronto.',
      );
      expect(
        _etiqueta(tester, const Key('cuenta_porCobrar')),
        r'Por cobrar, $ 9.700. Bajó $ 1.300 contra la semana pasada.',
      );
      manejador.dispose();
    });

    testWidgets('«En mano» que no creció no aconseja depositar; si no se movió, lo dice', (
      tester,
    ) async {
      final repo = RepositorioDeCuentaControlable(
        inicial: ResumenDeCuenta(
          enMano: cifra(500, variacion: -200),
          porCobrar: cifra(100, variacion: 0),
        ),
      );
      await montarCuenta(tester, repo);

      expect(find.text(r'▼ $ 200 contra la semana pasada'), findsOneWidget);
      expect(find.text('Igual que la semana pasada'), findsOneWidget);
      expect(find.textContaining('depositalo pronto'), findsNothing);
    });

    testWidgets('lo que sube de «Por cobrar» se dice con la flecha hacia arriba', (tester) async {
      final repo = RepositorioDeCuentaControlable(
        inicial: ResumenDeCuenta(
          enMano: cifra(0, variacion: 0),
          porCobrar: cifra(900, variacion: 400),
        ),
      );
      await montarCuenta(tester, repo);

      expect(find.text(r'▲ $ 400 contra la semana pasada'), findsOneWidget);
    });

    testWidgets('al día solo: una cifra nueva reemplaza a la anterior sin recargar', (
      tester,
    ) async {
      final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
      await montarCuenta(tester, repo);

      repo.emitir(
        ResumenDeCuenta(
          enMano: cifra(3000, variacion: 2400),
          porCobrar: cifra(9000, variacion: -2000),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(r'$ 3.000'), findsOneWidget);
      expect(find.text(r'$ 2.400'), findsNothing);
      expect(find.text(r'▼ $ 2.000 contra la semana pasada'), findsOneWidget);
      expect(repo.suscripciones, 1);
    });
  });

  group('33A·02 · Sin conexión', () {
    testWidgets('las dos cifras salen del teléfono: se ven igual y sin aviso de datos viejos', (
      tester,
    ) async {
      // La pantalla no mira la conexión: lo único que lee es la base local.
      await montarCuenta(tester, RepositorioDeCuentaControlable(inicial: resumenDelCanvas));

      expect(find.text(r'$ 2.400'), findsOneWidget);
      expect(find.text(r'$ 9.700'), findsOneWidget);
      expect(find.textContaining('Sin conexión'), findsNothing);
      expect(find.textContaining('servidor'), findsNothing);
      expect(find.text('Reintentar'), findsNothing);
    });
  });

  group('33A·03 · Cargando', () {
    testWidgets('mientras calcula, un bloque gris por tarjeta y ninguna cifra', (tester) async {
      await montarCuenta(tester, RepositorioDeCuentaControlable());

      expect(find.byKey(const Key('cuenta_esqueleto_enMano')), findsOneWidget);
      expect(find.byKey(const Key('cuenta_esqueleto_porCobrar')), findsOneWidget);
      expect(find.textContaining(r'$ '), findsNothing);
      expect(find.text('Mi Cuenta'), findsOneWidget);
    });

    testWidgets('el lector de pantalla lo anuncia: «Calculando tu cuenta»', (tester) async {
      final manejador = tester.ensureSemantics();
      await montarCuenta(tester, RepositorioDeCuentaControlable());

      expect(find.bySemanticsLabel('Calculando tu cuenta'), findsOneWidget);
      manejador.dispose();
    });

    testWidgets('llegan los datos y el esqueleto se va', (tester) async {
      final repo = RepositorioDeCuentaControlable();
      await montarCuenta(tester, repo);

      repo.emitir(resumenDelCanvas);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cuenta_esqueleto_enMano')), findsNothing);
      expect(find.text(r'$ 2.400'), findsOneWidget);
    });
  });

  group('33A·04 · Cuenta nueva', () {
    testWidgets(
      'dado que no tengo nada, veo ceros y «Sin datos de la semana anterior», no un error',
      (tester) async {
        await montarCuenta(tester, RepositorioDeCuentaControlable(inicial: resumenCuentaNueva));

        expect(find.text(r'$ 0'), findsNWidgets(2));
        expect(find.text('Sin datos de la semana anterior'), findsNWidgets(2));
        expect(find.text('Reintentar'), findsNothing);
        expect(find.textContaining('▲'), findsNothing);
        expect(find.textContaining('▼'), findsNothing);
      },
    );
  });

  group('33A·05 · Error', () {
    testWidgets('si no se puede calcular, dice qué pasó y ofrece «Reintentar», sin ceros', (
      tester,
    ) async {
      await montarCuenta(tester, RepositorioDeCuentaControlable()..fallaAlSuscribir = true);

      expect(find.text('No pudimos calcular tu cuenta.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('EN MANO'), findsNothing);
      expect(find.textContaining(r'$ '), findsNothing);
    });

    testWidgets('«Reintentar» vuelve a calcular: mientras tanto no queda el botón para tocarlo dos '
        'veces, y al terminar se ven las cifras', (tester) async {
      final repo = RepositorioDeCuentaControlable()..fallaAlSuscribir = true;
      await montarCuenta(tester, repo);
      expect(repo.suscripciones, 1);
      repo
        ..fallaAlSuscribir = false
        ..inicial = null;

      await tester.tap(find.text('Reintentar'));
      await tester.pump();

      expect(repo.suscripciones, 2);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.byKey(const Key('cuenta_esqueleto_enMano')), findsOneWidget);

      repo.emitir(resumenDelCanvas);
      await tester.pumpAndSettle();
      expect(find.text(r'$ 2.400'), findsOneWidget);
      expect(find.text('No pudimos calcular tu cuenta.'), findsNothing);
      expect(repo.suscripciones, 2);
    });

    testWidgets('si vuelve a fallar, el botón vuelve a estar disponible: nada queda trabado', (
      tester,
    ) async {
      final repo = RepositorioDeCuentaControlable()..fallaAlSuscribir = true;
      await montarCuenta(tester, repo);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Reintentar'), findsOneWidget);
      expect(repo.suscripciones, 2);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      expect(repo.suscripciones, 3);
      expect(find.text('No pudimos calcular tu cuenta.'), findsOneWidget);
    });

    testWidgets('la falla después de los primeros datos también se dice: no sigue mostrando cifras '
        'que ya no se sabe si están al día', (tester) async {
      final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
      await montarCuenta(tester, repo);
      expect(find.text(r'$ 2.400'), findsOneWidget);

      repo.fallar();
      await tester.pumpAndSettle();

      expect(find.text('No pudimos calcular tu cuenta.'), findsOneWidget);
      expect(find.text(r'$ 2.400'), findsNothing);
    });

    testWidgets('el error se anuncia solo al lector de pantalla', (tester) async {
      final manejador = tester.ensureSemantics();
      await montarCuenta(tester, RepositorioDeCuentaControlable()..fallaAlSuscribir = true);

      final datos = tester.getSemantics(find.byKey(const Key('cuenta_error_texto')));
      expect(datos.label, 'No pudimos calcular tu cuenta.');
      expect(
        tester.getSemantics(find.byKey(const Key('cuenta_reintentar'))),
        isSemantics(label: 'Reintentar', isButton: true, hasTapAction: true),
      );
      manejador.dispose();
    });
  });

  group('volver a la pestaña', () {
    testWidgets(
      'al reentrar se vuelve a leer, con las cifras de antes a la vista (sin pasar por la '
      'carga) y la nueva cuando llega',
      (tester) async {
        final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
        await montarCuenta(tester, repo);
        await cambiarActiva(tester, repo, activa: false);
        expect(repo.suscripciones, 1);

        repo.inicial = null;
        await cambiarActiva(tester, repo, activa: true);

        expect(repo.suscripciones, 2);
        expect(find.text(r'$ 2.400'), findsOneWidget);
        expect(find.byKey(const Key('cuenta_esqueleto_enMano')), findsNothing);

        repo.emitir(
          ResumenDeCuenta(enMano: cifra(2400, variacion: 0), porCobrar: cifra(9700, variacion: 0)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Igual que la semana pasada'), findsNWidgets(2));
      },
    );

    testWidgets('irse de la pestaña no vuelve a leer', (tester) async {
      final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
      await montarCuenta(tester, repo);

      await cambiarActiva(tester, repo, activa: false);

      expect(repo.suscripciones, 1);
      expect(find.text(r'$ 2.400'), findsOneWidget);
    });
  });

  group('datos límite y texto grande', () {
    testWidgets('un monto largo, con centavos, entra en la tarjeta', (tester) async {
      final repo = RepositorioDeCuentaControlable(
        inicial: const ResumenDeCuenta(
          enMano: CifraDeCuenta(totalCentavos: 123456789, variacionCentavos: 123456789),
          porCobrar: CifraDeCuenta(totalCentavos: 99999999999, variacionCentavos: -88888888850),
        ),
      );
      await montarCuenta(tester, repo, tamano: const Size(320, 568));

      expect(find.text(r'$ 1.234.567,89'), findsOneWidget);
      expect(find.text(r'$ 999.999.999,99'), findsOneWidget);
      expect(find.text(r'▼ $ 888.888.888,50 contra la semana pasada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final tamano in const [Size(320, 568), Size(360, 640), Size(412, 915)]) {
      testWidgets('con el texto al 200 % a ${tamano.width.toInt()}x${tamano.height.toInt()} no '
          'desborda y la última tarjeta se alcanza desplazando', (tester) async {
        final repo = RepositorioDeCuentaControlable(inicial: resumenDelCanvas);
        await montarCuenta(tester, repo, tamano: tamano, escala: 2);

        await tester.ensureVisible(find.byKey(const Key('cuenta_porCobrar')));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text(r'$ 9.700'), findsOneWidget);
        final caja = tester.getRect(find.byKey(const Key('cuenta_porCobrar')));
        expect(caja.left, greaterThanOrEqualTo(0));
        expect(caja.right, lessThanOrEqualTo(tamano.width));
      });

      testWidgets(
        'el error y la carga a ${tamano.width.toInt()}x${tamano.height.toInt()}, texto al '
        '200 %, tampoco desbordan',
        (tester) async {
          await montarCuenta(tester, RepositorioDeCuentaControlable(), tamano: tamano, escala: 2);
          expect(tester.takeException(), isNull);

          await montarCuenta(
            tester,
            RepositorioDeCuentaControlable()..fallaAlSuscribir = true,
            tamano: tamano,
            escala: 2,
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const Key('cuenta_reintentar'))).height,
            greaterThanOrEqualTo(48),
          );
        },
      );
    }
  });
}
