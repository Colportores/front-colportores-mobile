// QA de la deuda con la casa editora (vista 33A y 33B, HU-CTA-002, #441), segunda pasada sobre la
// punta que ya trae las decisiones del 04/11 y el merge de develop con «Mi plata» (#598):
// - los estados de Mi Cuenta que nacieron con esas decisiones (la deuda que no se pudo actualizar con
//   red y la que se avisa sin «Depositado»), en la matriz de tamaños y escalas;
// - el recorrido de punta a punta de quien abre el detalle sin red y sin nada guardado;
// - el literal del canvas 33A·02, carácter por carácter;
// - los casos límite del «Reintentar» de Mi Cuenta y la privacidad de lo que se imprime.
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/deuda_casa_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';
import '../../helpers/deuda_casa_arnes.dart';
import '../../helpers/qa_vista33_deuda_441_arnes.dart';

const _tamanos = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

/// Monta Mi Cuenta con la conexión [red] y la deuda guardada [guardada].
Future<RepositorioDeDeudaControlable> _montar(
  WidgetTester tester, {
  required TipoConexion red,
  LecturaDeLaDeuda? guardada,
  ResumenDeCuenta? resumen,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  final repo = RepositorioDeDeudaControlable(guardada: guardada);
  await montarCuenta(
    tester,
    RepositorioDeCuentaControlable(inicial: resumen ?? resumenDelCanvas),
    tamano: tamano,
    escala: escala,
    overrides: [
      ...overridesDeDeuda(repo),
      monitorConectividadProvider.overrideWithValue(QaConexion(red)),
    ],
  );
  await tester.pump();
  return repo;
}

Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('Matriz de Mi Cuenta · estados de las decisiones del 04/11', () {
    // (a) Con red, el servidor no contesta la deuda y se ve lo guardado con «Reintentar».
    // (b) Sin conexión, sin «Depositado» bajado y con la deuda guardada: el aviso sale igual.
    for (final caso in const ['servidor caído con lo guardado', 'sin conexión y sin Depositado']) {
      for (final t in _tamanos.entries) {
        for (final esc in const [1.0, 2.0]) {
          testWidgets('$caso · ${t.key} · texto ${esc}x: sin overflow y con las guías de '
              'accesibilidad', (tester) async {
            final handle = tester.ensureSemantics();
            final servidorCaido = caso.startsWith('servidor');
            final repo = await _montar(
              tester,
              red: servidorCaido ? TipoConexion.wifi : TipoConexion.sinConexion,
              guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 3, 21)),
              tamano: t.value,
              escala: esc,
            );
            repo.fallar(
              servidorCaido ? const FailureDeudaNoDisponible() : const FailureDeudaSinConexion(),
            );
            await _asentar(tester);
            expect(tester.takeException(), isNull);
            // El aviso está y dice de cuándo es la deuda que se ve.
            expect(find.textContaining('de ayer a las 21:00'), findsOneWidget);
            if (servidorCaido) expect(find.text('Reintentar'), findsOneWidget);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            if (esc == 1.0) await expectLater(tester, meetsGuideline(textContrastGuideline));
            handle.dispose();
          });
        }
      }
    }
  });

  group('Literal del canvas 33A·02', () {
    testWidgets('con la deuda y «Depositado» de la misma hora, el aviso es el del canvas, '
        'palabra por palabra', (tester) async {
      final repo = await _montar(
        tester,
        red: TipoConexion.sinConexion,
        guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 3, 21)),
        resumen: ResumenDeCuenta(
          depositado: cifra(26900, variacion: 5300),
          depositadoAl: DateTime(2026, 11, 3, 21),
          enMano: cifra(2400, variacion: 1800),
          porCobrar: cifra(9700, variacion: -1300),
        ),
      );
      repo.fallar(const FailureDeudaSinConexion());
      await _asentar(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('cuenta_aviso_sin_conexion'))).data,
        'Sin conexión. La deuda y lo depositado son de ayer a las 21:00; en mano y por cobrar '
        'están al día.',
      );
    });
  });

  group('Recorrido sin red y sin nada guardado', () {
    testWidgets('Mi Cuenta no inventa una cifra; el detalle dice que falta la conexión; al volver '
        'la red, «Reintentar» muestra la deuda y la tarjeta la toma', (tester) async {
      final repo = await _montar(tester, red: TipoConexion.sinConexion);
      repo.fallar(const FailureDeudaSinConexion());
      await _asentar(tester);
      // Nada guardado, ninguna hora: sin aviso y sin cifra (ni un «$ 0»).
      expect(find.byKey(const Key('cuenta_aviso_sin_conexion')), findsNothing);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsNothing);
      expect(find.text('DEUDA CON LA CASA EDITORA'), findsOneWidget);

      // Se abre el detalle: pide de nuevo (carga) y falla por falta de red.
      await tester.tap(find.byKey(const Key('cuenta_deuda')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);
      repo.fallar(const FailureDeudaSinConexion());
      await _asentar(tester);
      expect(
        find.text('Necesitás conexión para ver tu deuda con la casa editora.'),
        findsOneWidget,
      );
      expect(find.text('No pudimos traer tus pedidos.'), findsNothing);

      // Vuelve la red: «Reintentar» pasa por la carga y muestra la deuda.
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(find.byKey(const Key('deuda_esqueleto_total')), findsOneWidget);
      repo.responder(lectura(deudaDelCanvas));
      await _asentar(tester);
      expect(find.text(r'$ 18.400'), findsOneWidget);
      expect(find.text('PEDIDO DEL 02/10'), findsOneWidget);

      // Volver: Mi Cuenta ya tiene la cifra, sin recargar nada.
      await tester.tap(find.byKey(const Key('deuda_volver')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cuenta_pestana')), findsOneWidget);
      expect(find.byKey(const Key('cuenta_deuda_monto')), findsOneWidget);
      expect(find.text(r'$ 18.400'), findsOneWidget);
    });
  });

  group('«Reintentar» de Mi Cuenta (la deuda que no se pudo actualizar)', () {
    testWidgets('dos toques seguidos piden una sola vez; si falla otra vez, el aviso vuelve con '
        'el botón habilitado; si anda, el aviso se va y queda lo nuevo', (tester) async {
      final repo = await _montar(
        tester,
        red: TipoConexion.wifi,
        guardada: lectura(deudaDelCanvas, leidaEn: DateTime(2026, 11, 3, 21)),
      );
      repo.fallar();
      await _asentar(tester);
      final antes = repo.lecturas;
      expect(
        find.text('No pudimos actualizar la deuda con la casa editora. Es de ayer a las 21:00.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'), warnIfMissed: false);
      await tester.pump();
      expect(repo.lecturas, antes + 1);
      // Mientras pide, el aviso no queda a la vista (no hay un botón que tocar dos veces) y lo
      // guardado sigue.
      expect(find.textContaining('No pudimos actualizar la deuda'), findsNothing);
      expect(find.text(r'$ 18.400'), findsOneWidget);

      // Falla a mitad del reintento: el aviso y el botón vuelven.
      repo.fallar();
      await _asentar(tester);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(repo.lecturas, antes + 2);

      repo.responder(lectura(deuda(total: 5000), leidaEn: DateTime(2026, 11, 4, 9, 30)));
      await _asentar(tester);
      expect(find.textContaining('No pudimos actualizar la deuda'), findsNothing);
      expect(find.text(r'$ 5.000'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });
  });

  group('Privacidad', () {
    test('lo que se imprime de la deuda no lleva montos, productos ni ids', () {
      final impreso = [
        deudaDelCanvas.toString(),
        lectura(deudaDelCanvas).toString(),
        const EstadoDeLaDeuda(fallo: FalloDeLaDeuda.sinConexion).toString(),
        EstadoDeLaDeuda(lectura: lectura(deudaDelCanvas)).toString(),
      ].join(' | ');
      expect(impreso, isNot(contains('18400')));
      expect(impreso, isNot(contains('1840000')));
      expect(impreso, isNot(contains('Salud')));
      expect(impreso, isNot(contains('p-1')));
    });
  });
}
