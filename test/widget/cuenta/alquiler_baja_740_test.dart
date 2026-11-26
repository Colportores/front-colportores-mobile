// «Mi alquiler» con la campaña de la baja (vista 38C con la decisión del coordinador, HU-CTA-007, #740):
// el canvas 38C no dibuja la baja, así que cada estado sale de la regla R1 del 23/11 y de lo que dice el
// issue. Un test por estado (por decidir, los tres destinos, lo pagado después de la última decisión,
// devuelto, sin pagos aprobados) y los casos límite: la decisión que llega con la pantalla abierta, volver
// atrás y reentrar, sin conexión, la lista larga, los textos largos, el texto al 200 % y la línea de Mi
// Cuenta de quien solo tiene una baja.
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/alquiler_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alquiler_arnes.dart';
import '../../helpers/cuenta_arnes.dart';

const _porDecidir = 'Lo que pagaste queda por decidir: lo decide tu coordinador.';
const _devolver = 'Tu coordinador decidió devolvértelo.';
const _aCuenta = 'Tu coordinador lo dejó a cuenta de tu próximo depósito.';
const _seLoQueda = 'Tu coordinador decidió quedárselo.';

Future<RepositorioDeAlquilerControlable> _con(
  WidgetTester tester,
  AlquilerDelColportor alquiler, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  TipoConexion conexion = TipoConexion.wifi,
}) async {
  final repo = RepositorioDeAlquilerControlable(inicial: alquiler);
  await montarAlquiler(tester, repo, escala: escala, tamano: tamano, conexion: conexion);
  return repo;
}

AlquilerDelColportor _conDecision(DestinoDeLoPagado destino, {List<PagoDeAlquiler>? pagos}) =>
    alquilerCon(
      const [],
      bajas: [
        bajaCon(pagos: pagos ?? [pagoDe(5000)], decisiones: [decisionDe(destino, 5000)]),
      ],
    );

void main() {
  group('la campaña de la baja · por decidir', () {
    testWidgets('Ana se dio de baja de Otoño después de pagar \$ 5.000: ve la campaña, lo que pagó y '
        'que lo decide su coordinador', (tester) async {
      await _con(tester, alquilerDeBajaPorDecidir);

      expect(find.text('Otoño 2026 · inscripción dada de baja'), findsOneWidget);
      expect(find.text(_porDecidir), findsOneWidget);
      expect(find.text(r'$ 5.000'), findsNWidgets(2)); // el detalle del aviso y el pago
      expect(find.text('PAGOS'), findsOneWidget);
      expect(find.text('15/10 · RETIRO'), findsOneWidget);
      expect(find.text('Validado'), findsOneWidget);
      // Quien se dio de baja no debe nada: ni saldo, ni monto, ni botón; ni la pantalla «no cobra».
      expect(find.text('TE FALTA PAGAR'), findsNothing);
      expect(find.text('Alquiler de la campaña'), findsNothing);
      expect(find.text('Cargar pago de alquiler'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Esta campaña no cobra alquiler'), findsNothing);
    });

    testWidgets('con un pago por validar y otro rechazado, sin nada validado, la lista los muestra '
        'pero no dice «por decidir»: no hay nada que decidir', (tester) async {
      await _con(
        tester,
        alquilerCon(
          const [],
          bajas: [
            bajaCon(
              pagos: [
                pagoDe(
                  1000,
                  fecha: diaDeAlquiler(11, 20),
                  estado: EstadoDePagoDeAlquiler.porValidar,
                ),
                pagoDe(2000, estado: EstadoDePagoDeAlquiler.rechazado, motivo: 'la foto no se lee'),
              ],
            ),
          ],
        ),
      );

      expect(find.text(_porDecidir), findsNothing);
      expect(find.text('Por validar'), findsOneWidget);
      expect(find.text('Rechazado'), findsOneWidget);
      expect(find.textContaining('la foto no se lee'), findsOneWidget);
    });
  });

  group('la campaña de la baja · lo que decidió el coordinador', () {
    testWidgets('devolvérselo', (tester) async {
      await _con(
        tester,
        _conDecision(
          DestinoDeLoPagado.devolverAlColportor,
          pagos: [pagoDe(5000, estado: EstadoDePagoDeAlquiler.devuelto)],
        ),
      );

      expect(find.text(_devolver), findsOneWidget);
      expect(find.text(_porDecidir), findsNothing);
      expect(find.text('Devuelto'), findsOneWidget);
      expect(find.text('Te lo devolvieron: ya no cuenta'), findsOneWidget);
    });

    testWidgets('dejarlo a cuenta de su próximo depósito', (tester) async {
      await _con(tester, _conDecision(DestinoDeLoPagado.aCuentaDelProximoDeposito));

      expect(find.text(_aCuenta), findsOneWidget);
      expect(find.text(_porDecidir), findsNothing);
    });

    testWidgets('quedárselo', (tester) async {
      await _con(tester, _conDecision(DestinoDeLoPagado.seLoQuedaElCoordinador));

      expect(find.text(_seLoQueda), findsOneWidget);
      expect(find.text(_porDecidir), findsNothing);
    });

    testWidgets('cada decisión dice de cuánto fue y cuándo se decidió', (tester) async {
      await _con(tester, _conDecision(DestinoDeLoPagado.aCuentaDelProximoDeposito));

      expect(find.text(r'$ 5.000 · 12/11'), findsOneWidget);
    });

    testWidgets('si pagó después de la última decisión, lo nuevo vuelve a «por decidir», arriba de '
        'la decisión anterior, con su monto', (tester) async {
      await _con(
        tester,
        alquilerCon(
          const [],
          bajas: [
            bajaCon(
              pagos: [
                pagoDe(1000, fecha: diaDeAlquiler(11, 20)),
                pagoDe(5000),
              ],
              decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
            ),
          ],
        ),
      );

      expect(find.text(_porDecidir), findsOneWidget);
      expect(find.text(_aCuenta), findsOneWidget);
      expect(find.text(r'$ 1.000'), findsNWidgets(2)); // detalle de «por decidir» y el pago nuevo
      final arriba = tester.getTopLeft(find.byKey(const Key('alquiler_baja_por_decidir_0'))).dy;
      final abajo = tester.getTopLeft(find.byKey(const Key('alquiler_baja_decision_0_0'))).dy;
      expect(arriba, lessThan(abajo));
    });

    testWidgets('con dos decisiones, la más nueva primero y cada una con su texto', (tester) async {
      await _con(
        tester,
        alquilerCon(
          const [],
          bajas: [
            bajaCon(
              pagos: [
                pagoDe(1000, estado: EstadoDePagoDeAlquiler.devuelto),
                pagoDe(5000),
              ],
              decisiones: [
                decisionDe(DestinoDeLoPagado.devolverAlColportor, 1000, en: diaDeAlquiler(11, 18)),
                decisionDe(
                  DestinoDeLoPagado.aCuentaDelProximoDeposito,
                  5000,
                  en: diaDeAlquiler(11, 12),
                ),
              ],
            ),
          ],
        ),
      );

      final primera = tester.getTopLeft(find.byKey(const Key('alquiler_baja_decision_0_0'))).dy;
      final segunda = tester.getTopLeft(find.byKey(const Key('alquiler_baja_decision_0_1'))).dy;
      expect(primera, lessThan(segunda));
      expect(find.text(_devolver), findsOneWidget);
      expect(find.text(_aCuenta), findsOneWidget);
      expect(find.text(r'$ 1.000 · 18/11'), findsOneWidget);
      expect(find.text(r'$ 5.000 · 12/11'), findsOneWidget);
      expect(find.text(_porDecidir), findsNothing);
    });
  });

  group('junto a una campaña vigente', () {
    testWidgets(
      'la vigente con su saldo y su botón, y la de la baja abajo sin ninguno de los dos',
      (tester) async {
        await _con(
          tester,
          alquilerCon(
            [
              campaniaCon(pagos: [pagoDe(6000)]),
            ],
            bajas: [
              bajaCon(pagos: [pagoDe(5000)]),
            ],
          ),
        );

        expect(find.text('Primavera 2026 · monto fijo por campaña'), findsOneWidget);
        expect(find.text('Otoño 2026 · inscripción dada de baja'), findsOneWidget);
        expect(find.text('TE FALTA PAGAR'), findsOneWidget);
        expect(find.text('Cargar pago de alquiler'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const Key('alquiler_baja_0'))).dy,
          greaterThan(tester.getTopLeft(find.byKey(const Key('alquiler_bloque_0'))).dy),
        );
      },
    );

    testWidgets('quien solo tiene una baja no ve «Esta campaña no cobra alquiler»', (tester) async {
      await _con(tester, alquilerDeBajaPorDecidir);

      expect(find.byKey(const Key('alquiler_sin_alquiler')), findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('la decisión llega con la pantalla abierta: el aviso cambia de «por decidir» a lo '
        'decidido sin recargar, y si se deshace vuelve', (tester) async {
      final repo = await _con(tester, alquilerDeBajaPorDecidir);
      expect(find.text(_porDecidir), findsOneWidget);

      repo.emitir(_conDecision(DestinoDeLoPagado.seLoQuedaElCoordinador));
      await tester.pumpAndSettle();
      expect(find.text(_porDecidir), findsNothing);
      expect(find.text(_seLoQueda), findsOneWidget);

      repo.emitir(alquilerDeBajaPorDecidir);
      await tester.pumpAndSettle();
      expect(find.text(_seLoQueda), findsNothing);
      expect(find.text(_porDecidir), findsOneWidget);
    });

    testWidgets('el aviso de la decisión se anuncia como región viva', (tester) async {
      final manejador = tester.ensureSemantics();
      await _con(tester, _conDecision(DestinoDeLoPagado.aCuentaDelProximoDeposito));

      final nodo = tester.getSemantics(find.byKey(const Key('alquiler_baja_decision_0_0')));
      expect(nodo.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      manejador.dispose();
    });

    testWidgets('el lector de pantalla lee la campaña, el aviso con su detalle y cada pago', (
      tester,
    ) async {
      final manejador = tester.ensureSemantics();
      await _con(tester, _conDecision(DestinoDeLoPagado.devolverAlColportor));

      expect(
        find.bySemanticsLabel(RegExp(r'Otoño 2026 ·\s+inscripción dada de baja')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Tu coordinador decidió devolvértelo')), findsOneWidget);
      expect(
        find.bySemanticsLabel('15/10, RETIRO. \$ 5.000. Validado. Se acreditó al alquiler.'),
        findsOneWidget,
      );
      manejador.dispose();
    });

    testWidgets(
      'volver atrás y reentrar muestra la campaña de la baja otra vez, sin pantalla trabada',
      (tester) async {
        final repo = RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir);
        await montarAlquilerDesdeUnBoton(tester, repo);
        expect(find.text(_porDecidir), findsOneWidget);

        await tester.tap(find.byKey(const Key('alquiler_volver')));
        await tester.pumpAndSettle();
        expect(find.text(_porDecidir), findsNothing);

        await tester.tap(find.byKey(const Key('abrir_alquiler')));
        await tester.pumpAndSettle();
        expect(find.text(_porDecidir), findsOneWidget);
        expect(repo.suscripciones, 2);
      },
    );

    testWidgets('sin conexión, la campaña de la baja se ve con lo último que bajó y el aviso de la '
        'hora', (tester) async {
      await _con(
        tester,
        alquilerCon(
          const [],
          bajas: [
            bajaCon(pagos: [pagoDe(5000)]),
          ],
          bajadoEn: DateTime(2026, 11, 21, 21),
        ),
        conexion: TipoConexion.sinConexion,
      );

      expect(find.text('Sin conexión. Es lo que sabíamos ayer a las 21:00.'), findsOneWidget);
      expect(find.text(_porDecidir), findsOneWidget);
    });

    testWidgets('con varias bajas y muchos pagos la lista es larga y se recorre entera', (
      tester,
    ) async {
      await _con(
        tester,
        alquilerCon(
          const [],
          bajas: [
            for (var i = 0; i < 4; i++)
              bajaCon(
                id: 'b-$i',
                nombre: 'Campaña $i',
                pagos: [
                  for (var p = 0; p < 6; p++) pagoDe(100 + p, fecha: diaDeAlquiler(10, 1 + p)),
                ],
                decisiones: i.isEven
                    ? [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 615)]
                    : const [],
              ),
          ],
        ),
      );

      await tester.dragUntilVisible(
        find.byKey(const Key('alquiler_baja_subtitulo_3')),
        find.byKey(const Key('alquiler_lista')),
        const Offset(0, -300),
      );
      expect(find.text('Campaña 3 · inscripción dada de baja'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un nombre de campaña muy largo se parte en renglones y no desborda', (
      tester,
    ) async {
      await _con(
        tester,
        alquilerCon(
          const [],
          bajas: [
            bajaCon(
              nombre: 'Campaña de Verano de las Sierras y la Costa del Este de Maldonado 2026',
              pagos: [pagoDe(5000)],
              decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
            ),
          ],
        ),
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('con el texto al 200 % y a 360×640 nada desborda y el aviso se lee entero', (
      tester,
    ) async {
      await _con(
        tester,
        alquilerCon(
          const [],
          bajas: [
            bajaCon(
              pagos: [
                pagoDe(5000),
                pagoDe(1000, fecha: diaDeAlquiler(11, 20)),
              ],
              decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
            ),
          ],
        ),
        escala: 2,
        tamano: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_porDecidir), findsOneWidget);
      expect(find.text(_aCuenta), findsOneWidget);
    });
  });

  group('accesibilidad de la campaña de la baja', () {
    final estados = <String, AlquilerDelColportor>{
      'por decidir': alquilerDeBajaPorDecidir,
      'devuelto': _conDecision(
        DestinoDeLoPagado.devolverAlColportor,
        pagos: [pagoDe(5000, estado: EstadoDePagoDeAlquiler.devuelto)],
      ),
      'a cuenta': _conDecision(DestinoDeLoPagado.aCuentaDelProximoDeposito),
      'se lo queda': _conDecision(DestinoDeLoPagado.seLoQuedaElCoordinador),
      'nuevo por decidir y decisión vieja': alquilerCon(
        const [],
        bajas: [
          bajaCon(
            pagos: [
              pagoDe(1000, fecha: diaDeAlquiler(11, 20)),
              pagoDe(5000),
            ],
            decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
          ),
        ],
      ),
    };
    for (final estado in estados.entries) {
      for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.key} a ${tam.key}, texto $escala: toque, etiqueta y contraste', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            await _con(tester, estado.value, tamano: tam.value, escala: escala);
            await tester.pump();

            final falla = tester.takeException();
            expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            if (escala == 1.0) await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('la línea «Alquiler» de Mi Cuenta con solo una baja', () {
    testWidgets(
      'aparece (si no, la persona no llega a ver qué decidió su coordinador) y dice «Al día»: '
      'no debe nada',
      (tester) async {
        await montarCuenta(
          tester,
          RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
          tamano: const Size(390, 844),
          overrides: overridesDeAlquiler(
            RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir),
          ),
        );
        await tester.pump();

        expect(find.byKey(const Key('cuenta_fila_alquiler')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('cuenta_fila_alquiler_valor'))).data,
          'Al día',
        );
      },
    );

    testWidgets('al tocarla abre «Mi alquiler» con la campaña de la baja', (tester) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        tamano: const Size(390, 844),
        overrides: overridesDeAlquiler(
          RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('cuenta_fila_alquiler')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cuenta_fila_alquiler')));
      await tester.pumpAndSettle();

      expect(find.byType(AlquilerPage), findsOneWidget);
      expect(find.text(_porDecidir), findsOneWidget);
    });
  });
}
