// QA de «Mi alquiler» con la campaña de la baja (HU-CTA-007, #740), con las fuentes reales: cada estado
// a 360×640 y 412×915, texto al 100 % y al 200 %, sin texto cortado ni palabras partidas, más los casos
// que los tests del implementador no tocan (decisiones sin pagos, tres decisiones iguales, el pago que se
// valida con la pantalla abierta, reentrar, la línea de Mi Cuenta). Las capturas salen con
// `--dart-define=QA_CAPTURAS=true` a `.dart_tool/qa_capturas/` (fuera del repo).
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/alquiler_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/textos_alquiler.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alquiler_arnes.dart';
import '../../helpers/cuenta_arnes.dart';
import '../../helpers/qa_alquiler_743_arnes.dart';

const _porDecidir = 'Lo que pagaste queda por decidir: lo decide tu coordinador.';

typedef _Estado = ({
  String nombre,
  RepositorioDeAlquilerControlable Function() repo,
  TipoConexion conexion,
});

AlquilerDelColportor _conBajas(
  List<AlquilerDeBaja> bajas, {
  List<AlquilerDeCampania> vigentes = const [],
  DateTime? bajadoEn,
}) => alquilerCon(vigentes, bajas: bajas, bajadoEn: bajadoEn);

RepositorioDeAlquilerControlable Function() _repo(AlquilerDelColportor a) =>
    () => RepositorioDeAlquilerControlable(inicial: a);

final _estados = <_Estado>[
  (nombre: 'por_decidir', repo: _repo(alquilerDeBajaPorDecidir), conexion: TipoConexion.wifi),
  (
    nombre: 'devolverlo',
    repo: _repo(
      _conBajas([
        bajaCon(
          pagos: [pagoDe(5000, estado: EstadoDePagoDeAlquiler.devuelto)],
          decisiones: [decisionDe(DestinoDeLoPagado.devolverAlColportor, 5000)],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'a_cuenta',
    repo: _repo(
      _conBajas([
        bajaCon(
          pagos: [pagoDe(5000)],
          decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'se_lo_queda',
    repo: _repo(
      _conBajas([
        bajaCon(
          pagos: [pagoDe(5000)],
          decisiones: [decisionDe(DestinoDeLoPagado.seLoQuedaElCoordinador, 5000)],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'nuevo_por_decidir_y_decision',
    repo: _repo(
      _conBajas([
        bajaCon(
          pagos: [
            pagoDe(1000, fecha: diaDeAlquiler(11, 20)),
            pagoDe(5000),
          ],
          decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'dos_decisiones',
    repo: _repo(
      _conBajas([
        bajaCon(
          pagos: [
            pagoDe(2000, fecha: diaDeAlquiler(11, 18), estado: EstadoDePagoDeAlquiler.devuelto),
            pagoDe(5000),
          ],
          decisiones: [
            decisionDe(DestinoDeLoPagado.devolverAlColportor, 2000, en: diaDeAlquiler(11, 19)),
            decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000),
          ],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'solo_decision_sin_pagos',
    repo: _repo(
      _conBajas([
        bajaCon(decisiones: [decisionDe(DestinoDeLoPagado.seLoQuedaElCoordinador, 5000)]),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'junto_a_una_vigente',
    repo: _repo(
      _conBajas(
        [
          bajaCon(pagos: [pagoDe(5000)]),
        ],
        vigentes: [
          campaniaCon(pagos: [pagoDe(6000)]),
        ],
      ),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'monto_grande',
    repo: _repo(
      _conBajas([
        bajaCon(
          pagos: [pagoDe(1234567)],
          decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 1234567)],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'nombre_largo',
    repo: _repo(
      _conBajas([
        bajaCon(
          nombre: 'Campaña de otoño de las sierras del este y la costa de Rocha 2026',
          pagos: [pagoDe(5000)],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'cuatro_bajas_seis_pagos',
    repo: _repo(
      _conBajas([
        for (var b = 0; b < 4; b++)
          bajaCon(
            id: 'b-$b',
            nombre: 'Campaña $b',
            pagos: [for (var p = 0; p < 6; p++) pagoDe(500 + p, fecha: diaDeAlquiler(10, 1 + p))],
          ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'sin_conexion',
    repo: _repo(
      _conBajas([
        bajaCon(
          pagos: [pagoDe(5000)],
          decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
        ),
      ], bajadoEn: DateTime(2026, 11, 21, 21)),
    ),
    conexion: TipoConexion.sinConexion,
  ),
  (nombre: 'cargando', repo: () => RepositorioDeAlquilerControlable(), conexion: TipoConexion.wifi),
  (
    nombre: 'error',
    repo: () => RepositorioDeAlquilerControlable()..fallaAlSuscribir = true,
    conexion: TipoConexion.wifi,
  ),
];

Future<void> _con(
  WidgetTester tester,
  RepositorioDeAlquilerControlable repo, {
  Size tamano = const Size(390, 844),
  double escala = 1,
  TipoConexion conexion = TipoConexion.wifi,
}) async {
  await cargarFuentes743(tester);
  await montarAlquiler(tester, repo, tamano: tamano, escala: escala, conexion: conexion);
}

void main() {
  group(
    'con las fuentes reales: cada estado de la baja, sin texto cortado ni palabras partidas',
    () {
      for (final estado in _estados) {
        for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
          for (final escala in [1.0, 2.0]) {
            testWidgets('${estado.nombre} a ${tam.key}, texto $escala', (tester) async {
              await _con(
                tester,
                estado.repo(),
                tamano: tam.value,
                escala: escala,
                conexion: estado.conexion,
              );
              await tester.pump();
              await capturar743(tester, 'baja_${estado.nombre}_${tam.key}_${escala}x');

              final falla = tester.takeException();
              expect(
                falla,
                isNull,
                reason: falla is FlutterError ? falla.toStringDeep() : '$falla',
              );
              sinTextoCortado743(tester);
              expect(palabrasPartidas743(tester), isEmpty, reason: 'palabras partidas');
            });
          }
        }
      }
    },
  );

  group('guías de accesibilidad de la campaña de la baja (tamaño de toque y etiquetas)', () {
    for (final estado in _estados) {
      for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.nombre} a ${tam.key}, texto $escala', (tester) async {
            final semantica = tester.ensureSemantics();
            await _con(
              tester,
              estado.repo(),
              tamano: tam.value,
              escala: escala,
              conexion: estado.conexion,
            );
            await tester.pump();
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });

  group('casos límite de la campaña de la baja', () {
    testWidgets(
      'una decisión sin pagos locales se ve igual, sin el rótulo «PAGOS» ni «por decidir»',
      (tester) async {
        await _con(
          tester,
          RepositorioDeAlquilerControlable(
            inicial: _conBajas([
              bajaCon(decisiones: [decisionDe(DestinoDeLoPagado.seLoQuedaElCoordinador, 5000)]),
            ]),
          ),
        );
        expect(find.text('Tu coordinador decidió quedárselo.'), findsOneWidget);
        expect(find.text('PAGOS'), findsNothing);
        expect(find.text(_porDecidir), findsNothing);
        expect(find.text('Esta campaña no cobra alquiler'), findsNothing);
      },
    );

    testWidgets(
      'tres decisiones del mismo monto el mismo día no chocan (cada aviso con su clave)',
      (tester) async {
        await _con(
          tester,
          RepositorioDeAlquilerControlable(
            inicial: _conBajas([
              bajaCon(
                pagos: [pagoDe(3000)],
                decisiones: [
                  decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 1000),
                  decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 1000),
                  decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 1000),
                ],
              ),
            ]),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text('Tu coordinador lo dejó a cuenta de tu próximo depósito.'),
          findsNWidgets(3),
        );
        expect(find.text(_porDecidir), findsNothing);
      },
    );

    testWidgets('el pago por validar que se valida con la pantalla abierta pasa a «por decidir»', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable(
        inicial: _conBajas([
          bajaCon(pagos: [pagoDe(5000, estado: EstadoDePagoDeAlquiler.porValidar)]),
        ]),
      );
      await _con(tester, repo);
      expect(find.text(_porDecidir), findsNothing);
      expect(find.text('Por validar'), findsOneWidget);

      repo.emitir(
        _conBajas([
          bajaCon(pagos: [pagoDe(5000)]),
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(_porDecidir), findsOneWidget);
      expect(find.text('Validado'), findsOneWidget);
    });

    testWidgets('la baja que desaparece (el coordinador la reactivó) deja la pantalla «no cobra»', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir);
      await _con(tester, repo);
      expect(find.text(_porDecidir), findsOneWidget);

      repo.emitir(AlquilerDelColportor.vacio);
      await tester.pump();
      await tester.pump();
      expect(find.text(_porDecidir), findsNothing);
      expect(find.text('Esta campaña no cobra alquiler'), findsOneWidget);
    });

    testWidgets(
      'una falla al leer con la baja ya a la vista no la borra: sigue la última lectura, sin error trabado',
      (tester) async {
        final repo = RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir);
        await _con(tester, repo);
        repo.fallar();
        await tester.pump();
        await tester.pump();
        expect(find.text(_porDecidir), findsOneWidget);
        expect(find.text('Esta campaña no cobra alquiler'), findsNothing);
      },
    );

    testWidgets('abrir, volver y reabrir «Mi alquiler» muestra la baja las dos veces', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir);
      await montarAlquilerDesdeUnBoton(tester, repo);
      expect(find.text(_porDecidir), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AlquilerPage), findsNothing);

      await tester.tap(find.byKey(const Key('abrir_alquiler')));
      await tester.pumpAndSettle();
      expect(find.text(_porDecidir), findsOneWidget);
      expect(repo.suscripciones, 2);
    });

    testWidgets(
      'el subtítulo de cada campaña de baja es un encabezado para el lector de pantalla',
      (tester) async {
        final semantica = tester.ensureSemantics();
        await _con(tester, RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir));
        final nodo = tester.getSemantics(find.byKey(const Key('alquiler_baja_subtitulo_0')));
        expect(nodo.getSemanticsData().flagsCollection.isHeader, isTrue);
        semantica.dispose();
      },
    );

    test('privacidad: ni los montos ni el nombre de la campaña salen en toString()', () {
      final baja = bajaCon(
        nombre: 'Campaña de Marta Pérez',
        pagos: [pagoDe(5000)],
        decisiones: [decisionDe(DestinoDeLoPagado.devolverAlColportor, 5000)],
      );
      for (final texto in [
        '$baja',
        '${baja.decisiones.single}',
        '${alquilerCon(const [], bajas: [baja])}',
      ]) {
        expect(texto, isNot(contains('Marta')));
        expect(texto, isNot(contains('5000')));
        expect(texto, isNot(contains('500000')));
      }
    });
  });

  group('la línea «Alquiler» de Mi Cuenta con una baja', () {
    Future<String> fila(WidgetTester tester, AlquilerDelColportor alquiler) async {
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        tamano: const Size(390, 844),
        overrides: overridesDeAlquiler(RepositorioDeAlquilerControlable(inicial: alquiler)),
      );
      await tester.pump();
      return tester.widget<Text>(find.byKey(const Key('cuenta_fila_alquiler_valor'))).data!;
    }

    testWidgets('con la baja ya decidida y nada por decidir dice «Al día»', (tester) async {
      final texto = await fila(
        tester,
        _conBajas([
          bajaCon(
            pagos: [pagoDe(5000)],
            decisiones: [decisionDe(DestinoDeLoPagado.aCuentaDelProximoDeposito, 5000)],
          ),
        ]),
      );
      expect(texto, 'Al día');
    });

    testWidgets('DECISIÓN 23/11 (P1): con algo por decidir dice «Al día · \$ 5.000 por decidir»', (
      tester,
    ) async {
      final texto = await fila(tester, alquilerDeBajaPorDecidir);
      expect(texto, r'Al día · $ 5.000 por decidir');
    });

    test(
      'DECISIÓN 23/11 (P1): TextosAlquiler.resumenDeLaFila suma «por decidir» cuando lo hay',
      () {
        expect(
          TextosAlquiler.resumenDeLaFila(alquilerDeBajaPorDecidir),
          r'Al día · $ 5.000 por decidir',
        );
        expect(
          TextosAlquiler.resumenDeLaFila(
            _conBajas([
              bajaCon(
                pagos: [pagoDe(5000)],
                decisiones: [decisionDe(DestinoDeLoPagado.seLoQuedaElCoordinador, 5000)],
              ),
            ]),
          ),
          'Al día',
        );
      },
    );

    testWidgets('DECISIÓN 23/11 (P1): el lector de pantalla lee la fila con lo por decidir', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await fila(tester, alquilerDeBajaPorDecidir);
      expect(
        find.bySemanticsLabel(RegExp(r'Alquiler, Al día · \$ 5\.000 por decidir')),
        findsOneWidget,
      );
      semantica.dispose();
    });

    final conSaldoYPorDecidir = _conBajas(
      [
        bajaCon(pagos: [pagoDe(5000)]),
      ],
      vigentes: [
        campaniaCon(pagos: [pagoDe(6000)]),
      ],
    );

    testWidgets(
      'DECISIÓN 26/11 (P1): con saldo en una vigente y plata por decidir en una baja dice las dos',
      (tester) async {
        final texto = await fila(tester, conSaldoYPorDecidir);
        expect(texto, r'$ 12.500 por pagar · $ 5.000 por decidir');
      },
    );

    test('DECISIÓN 26/11 (P1): el texto con 0, 1 y dos bajas por decidir y una ya decidida', () {
      expect(TextosAlquiler.resumenDeLaFila(_conBajas(const [])), 'Al día');
      expect(
        TextosAlquiler.resumenDeLaFila(conSaldoYPorDecidir),
        r'$ 12.500 por pagar · $ 5.000 por decidir',
      );
      final dosPorDecidir = _conBajas([
        bajaCon(id: 'b-1', pagos: [pagoDe(5000)]),
        bajaCon(id: 'b-2', nombre: 'Verano 2026', pagos: [pagoDe(3000)]),
      ]);
      expect(TextosAlquiler.resumenDeLaFila(dosPorDecidir), r'Al día · $ 8.000 por decidir');
      final unaDecididaYOtraNo = _conBajas([
        bajaCon(
          id: 'b-1',
          pagos: [pagoDe(5000)],
          decisiones: [decisionDe(DestinoDeLoPagado.seLoQuedaElCoordinador, 5000)],
        ),
        bajaCon(id: 'b-2', nombre: 'Verano 2026', pagos: [pagoDe(3000)]),
      ]);
      expect(TextosAlquiler.resumenDeLaFila(unaDecididaYOtraNo), r'Al día · $ 3.000 por decidir');
      expect(
        FormatoAlquiler.filaHablada(conSaldoYPorDecidir),
        r'Alquiler, $ 12.500 por pagar · $ 5.000 por decidir',
      );
    });

    testWidgets('con saldo y por decidir, a 360×640 y texto 2,0 la fila se parte sin cortarse', (
      tester,
    ) async {
      await cargarFuentes743(tester);
      await montarCuenta(
        tester,
        RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
        tamano: const Size(360, 640),
        escala: 2.0,
        overrides: overridesDeAlquiler(
          RepositorioDeAlquilerControlable(inicial: conSaldoYPorDecidir),
        ),
      );
      await tester.pump();
      final falla = tester.takeException();
      expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
      sinTextoCortado743(tester);
    });

    for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('la fila con la baja por decidir a ${tam.key}, texto $escala no se corta', (
          tester,
        ) async {
          await cargarFuentes743(tester);
          await montarCuenta(
            tester,
            RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
            tamano: tam.value,
            escala: escala,
            overrides: overridesDeAlquiler(
              RepositorioDeAlquilerControlable(inicial: alquilerDeBajaPorDecidir),
            ),
          );
          await tester.pump();
          await capturar743(tester, 'baja_cuenta_fila_${tam.key}_${escala}x');
          final falla = tester.takeException();
          expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
          sinTextoCortado743(tester);
        });
      }
    }
  });
}
