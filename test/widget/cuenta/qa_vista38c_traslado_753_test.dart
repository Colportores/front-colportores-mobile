// QA de «Mi alquiler» lee el pagado de más del servidor (vista 38C y nota de 33B, HU-CTA-007, #753):
// el aviso «Pagaste $ X de más» sale de `cuenta_colportor.alquiler_trasladado` (un total de todas las
// campañas), va una sola vez arriba de la lista y la deuda con la casa editora usa la misma cifra.
// Con las fuentes reales, a 360×640 y 412×915, texto al 100 % y al 200 %, más los casos límite (la cifra
// que sube, baja, se deshace o llega con la pantalla abierta, la reentrada y el error). Las capturas
// salen con `--dart-define=QA_CAPTURAS=true` a `.dart_tool/qa_capturas/` (fuera del repo).

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/deuda_con_la_casa.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/deuda_casa_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alquiler_arnes.dart';
import '../../helpers/deuda_casa_arnes.dart';
import '../../helpers/qa_alquiler_743_arnes.dart';

/// El aviso de la HU, literal (decisión «Alquiler fav», 28/10).
String _aviso(String monto) =>
    'Pagaste $monto de más. Se descontaron de tu deuda con la casa editora.';

typedef _Estado = ({
  String nombre,
  RepositorioDeAlquilerControlable Function() repo,
  TipoConexion conexion,
  String monto,
});

/// Estados de «Mi alquiler» con un traslado del servidor; [monto] es lo que dice el aviso.
final _estados = <_Estado>[
  (
    nombre: 'pagado_de_mas',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
      ], trasladado: 500),
    ),
    conexion: TipoConexion.wifi,
    monto: r'$ 500',
  ),
  (
    nombre: 'dos_campanias_una_debe',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(id: 'c-1', pagos: [pagoDe(6000)]),
        campaniaCon(id: 'c-2', nombre: 'Otoño 2026', monto: 10000),
      ], trasladado: 500),
    ),
    conexion: TipoConexion.wifi,
    monto: r'$ 500',
  ),
  (
    nombre: 'por_validar_y_de_mas',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(
          monto: 2500,
          pagos: [
            pagoDe(1000, estado: EstadoDePagoDeAlquiler.porValidar, fecha: diaDeAlquiler(11, 20)),
            pagoDe(3000),
          ],
        ),
      ], trasladado: 500),
    ),
    conexion: TipoConexion.wifi,
    monto: r'$ 500',
  ),
  (
    nombre: 'sin_conexion_y_de_mas',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon(
        [
          campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
        ],
        bajadoEn: DateTime(2026, 11, 21, 21),
        trasladado: 500,
      ),
    ),
    conexion: TipoConexion.sinConexion,
    monto: r'$ 500',
  ),
  (
    nombre: 'baja_sin_campanias',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: const AlquilerDelColportor(campanias: [], trasladadoCentavos: 250000),
    ),
    conexion: TipoConexion.wifi,
    monto: r'$ 2.500',
  ),
  (
    nombre: 'monto_con_centavos',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
      ]).conTraslado(123456750),
    ),
    conexion: TipoConexion.wifi,
    monto: r'$ 1.234.567,50',
  ),
  (
    nombre: 'un_centavo',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
      ]).conTraslado(1),
    ),
    conexion: TipoConexion.wifi,
    monto: r'$ 0,01',
  ),
];

extension on AlquilerDelColportor {
  /// El mismo alquiler con un traslado dado en centavos (los datos límite no caben en pesos enteros).
  AlquilerDelColportor conTraslado(int centavos) =>
      AlquilerDelColportor(campanias: campanias, bajadoEn: bajadoEn, trasladadoCentavos: centavos);
}

Future<void> _soltar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group(
    '38C con traslado del servidor, fuentes reales: sin texto cortado y con el aviso a la vista',
    () {
      for (final estado in _estados) {
        for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
          for (final escala in [1.0, 2.0]) {
            testWidgets('${estado.nombre} a ${tam.key}, texto $escala', (tester) async {
              await cargarFuentes743(tester);
              await montarAlquiler(
                tester,
                estado.repo(),
                tamano: tam.value,
                escala: escala,
                conexion: estado.conexion,
              );
              await tester.pump();
              await capturar743(tester, '753_${estado.nombre}_${tam.key}_${escala}x');

              final falla = tester.takeException();
              expect(
                falla,
                isNull,
                reason: falla is FlutterError ? falla.toStringDeep() : '$falla',
              );
              sinTextoCortado743(tester);
              expect(palabrasPartidas743(tester), isEmpty, reason: 'palabras partidas');

              // El aviso sale una sola vez y se ve entero sin tener que desplazar la pantalla.
              expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);
              expect(find.text(_aviso(estado.monto)), findsOneWidget);
              final caja = tester.getRect(find.byKey(const Key('alquiler_de_mas')));
              expect(caja.top, greaterThanOrEqualTo(0));
              expect(
                caja.bottom,
                lessThanOrEqualTo(tam.value.height),
                reason: 'aviso fuera de pantalla',
              );
            });
          }
        }
      }
    },
  );

  group('accesibilidad del aviso «Pagaste de más»', () {
    for (final estado in _estados) {
      for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${estado.nombre} a ${tam.key}, texto $escala: toque, etiqueta y contraste', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            await montarAlquiler(
              tester,
              estado.repo(),
              tamano: tam.value,
              escala: escala,
              conexion: estado.conexion,
            );
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

    testWidgets('el lector lo lee entero y como región viva (aparece con la pantalla abierta)', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montarAlquiler(tester, repo);
      repo.emitir(
        alquilerCon([
          campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
        ], trasladado: 500),
      );
      await _soltar(tester);

      final nodo = tester.getSemantics(find.byKey(const Key('alquiler_de_mas')));
      expect(nodo.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(nodo.label, contains('Pagaste \$ 500 de más'));
      expect(nodo.label, contains('Se descontaron de tu deuda con la casa editora'));
      semantica.dispose();
    });
  });

  group('HU-CTA-007 · Escenario: Pagué de más el alquiler', () {
    testWidgets(
      'dado \$ 2.500 de alquiler y \$ 3.000 validados, veo el alquiler en \$ 0 y los \$ 500 '
      'de más que bajaron mi deuda con la casa editora',
      (tester) async {
        await montarAlquiler(tester, _estados.first.repo());

        expect(find.text('TE FALTA PAGAR'), findsOneWidget);
        expect(find.text(r'$ 0'), findsWidgets);
        expect(find.text(_aviso(r'$ 500')), findsOneWidget);
        expect(find.text('Cargar pago de alquiler'), findsNothing);
      },
    );

    testWidgets('con dos campañas el aviso es uno, arriba de los bloques, y no mezcla saldos', (
      tester,
    ) async {
      await montarAlquiler(tester, _estados[1].repo());

      expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);
      expect(find.byKey(const Key('alquiler_de_mas_0')), findsNothing);
      expect(find.byKey(const Key('alquiler_de_mas_1')), findsNothing);
      final aviso = tester.getRect(find.byKey(const Key('alquiler_de_mas')));
      final bloque0 = tester.getRect(find.byKey(const Key('alquiler_bloque_0')));
      expect(aviso.bottom, lessThanOrEqualTo(bloque0.top));
      // Lo que falta de la segunda campaña sigue entero y sigue habiendo dónde cargar el pago.
      expect(find.text(r'$ 10.000'), findsWidgets);
      expect(find.text('Cargar pago de alquiler'), findsNWidgets(2));
    });

    testWidgets('con «sin conexión» el aviso de la red va primero y el de lo trasladado después', (
      tester,
    ) async {
      await montarAlquiler(tester, _estados[3].repo(), conexion: TipoConexion.sinConexion);

      final red = tester.getRect(find.textContaining('Sin conexión.'));
      final deMas = tester.getRect(find.byKey(const Key('alquiler_de_mas')));
      expect(red.bottom, lessThanOrEqualTo(deMas.top));
    });
  });

  group('casos límite del traslado', () {
    testWidgets('sin traslado (0) no hay aviso aunque los pagos pasen el monto', (tester) async {
      await montarAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon([
            campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
          ]),
        ),
      );
      expect(find.byKey(const Key('alquiler_de_mas')), findsNothing);
      expect(find.textContaining('de más'), findsNothing);
    });

    testWidgets('un traslado negativo que llegue al modelo no dice «Pagaste − \$ …»', (
      tester,
    ) async {
      await montarAlquiler(
        tester,
        RepositorioDeAlquilerControlable(
          inicial: alquilerCon([
            campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
          ]).conTraslado(-500),
        ),
      );
      expect(find.byKey(const Key('alquiler_de_mas')), findsNothing);
    });

    testWidgets(
      'el traslado sube, baja y se deshace con la pantalla abierta: siempre un solo aviso',
      (tester) async {
        final repo = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
        await montarAlquiler(tester, repo);
        expect(find.byKey(const Key('alquiler_de_mas')), findsNothing);

        for (final (pesos, texto) in [(500, r'$ 500'), (800, r'$ 800'), (50, r'$ 50')]) {
          repo.emitir(
            alquilerCon([
              campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
            ], trasladado: pesos),
          );
          await _soltar(tester);
          expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);
          expect(find.text(_aviso(texto)), findsOneWidget);
        }

        repo.emitir(alquilerCon(alquilerDelCanvas.campanias));
        await _soltar(tester);
        expect(find.byKey(const Key('alquiler_de_mas')), findsNothing);
        expect(find.text('Cargar pago de alquiler'), findsOneWidget);
      },
    );

    testWidgets('si el stream falla después de mostrar el aviso, el aviso no desaparece', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable(inicial: _estados.first.repo().inicial);
      await montarAlquiler(tester, repo);
      expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);

      repo.fallar();
      await _soltar(tester);

      // Lo último que se supo sigue a la vista: no se cambia por un error ni por «no cobra alquiler».
      expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);
      expect(find.text('Esta campaña no cobra alquiler'), findsNothing);
    });

    testWidgets('error al abrir y «Reintentar» trae el aviso', (tester) async {
      final repo = RepositorioDeAlquilerControlable(inicial: _estados.first.repo().inicial)
        ..fallaAlSuscribir = true;
      await montarAlquiler(tester, repo);
      expect(find.byKey(const Key('alquiler_de_mas')), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);

      repo.fallaAlSuscribir = false;
      await tester.tap(find.text('Reintentar'));
      await _soltar(tester);

      expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
    });

    testWidgets('salir y volver a entrar: el aviso sigue y no se duplica', (tester) async {
      final repo = _estados.first.repo();
      await montarAlquilerDesdeUnBoton(tester, repo);
      expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);

      await tester.tap(find.byKey(const Key('alquiler_volver')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alquiler_de_mas')), findsNothing);

      await tester.tap(find.byKey(const Key('abrir_alquiler')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('alquiler_de_mas')), findsOneWidget);
      expect(find.text(_aviso(r'$ 500')), findsOneWidget);
    });

    testWidgets(
      'quien se dio de baja ve el aviso arriba del vacío (efecto aceptado en la decisión del 24/11)',
      (tester) async {
        await montarAlquiler(tester, _estados[4].repo());

        expect(find.text(_aviso(r'$ 2.500')), findsOneWidget);
        // Pendiente §2 del implementador (P1): lo que dice el vacío de 38C·04 con un traslado.
        expect(find.text('Esta campaña no cobra alquiler'), findsOneWidget);
      },
    );
  });

  group('privacidad', () {
    test('lo trasladado no sale en toString() del alquiler', () {
      final alquiler = alquilerCon([
        campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
      ]).conTraslado(77700);
      expect('$alquiler', isNot(contains('77700')));
      expect('$alquiler', isNot(contains('777')));
    });
  });

  group('33B · la nota «Ya descontamos \$ X que pagaste de más» con la misma cifra', () {
    Future<void> montar(
      WidgetTester tester,
      RepositorioDeAlquilerControlable alquiler, {
      required DeudaConLaCasa deudaDe,
      Size tamano = const Size(390, 844),
      double escala = 1,
    }) async {
      final repo = RepositorioDeDeudaControlable(guardada: lectura(deudaDe));
      tester.view.physicalSize = tamano;
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
              child: child!,
            ),
            home: const DeudaCasaPage(colportorId: 'col-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    final deudas = {'con_deuda': deudaDelCanvas, 'sin_deuda': deuda(total: 0)};

    for (final d in deudas.entries) {
      for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final escala in [1.0, 2.0]) {
          testWidgets('${d.key} a ${tam.key}, texto $escala: la nota se lee y no corta', (
            tester,
          ) async {
            await cargarFuentes743(tester);
            await montar(
              tester,
              _estados.first.repo(),
              deudaDe: d.value,
              tamano: tam.value,
              escala: escala,
            );
            await tester.scrollUntilVisible(
              find.byKey(const Key('deuda_nota_alquiler')),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pump();
            await capturar743(tester, '753_33B_${d.key}_${tam.key}_${escala}x');

            final falla = tester.takeException();
            expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
            sinTextoCortado743(tester);
            expect(
              find.text(r'Ya descontamos $ 500 que pagaste de más en el alquiler.'),
              findsOneWidget,
            );
          });
        }
      }
    }

    testWidgets('el traslado que llega por el sync aparece y se va sin recargar la deuda', (
      tester,
    ) async {
      final alquiler = RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas);
      await montar(tester, alquiler, deudaDe: deudaDelCanvas);
      expect(find.byKey(const Key('deuda_nota_alquiler')), findsNothing);

      alquiler.emitir(alquilerCon(alquilerDelCanvas.campanias, trasladado: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deuda_nota_alquiler')), findsOneWidget);

      alquiler.emitir(alquilerCon(alquilerDelCanvas.campanias));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deuda_nota_alquiler')), findsNothing);
    });
  });
}
