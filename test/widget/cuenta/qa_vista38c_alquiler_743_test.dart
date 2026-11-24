// QA de «Mi alquiler» (vista 38C, HU-CTA-007, #389), con las fuentes reales: cada estado a 360×640 y
// 412×915, texto al 100 % y al 200 %, sin texto cortado ni palabras partidas, más los casos que los
// tests del implementador no tocan (conexión que vuelve con la pantalla abierta, privacidad, el
// alquiler que no bloquea). Las capturas salen con `--dart-define=QA_CAPTURAS=true` a
// `.dart_tool/qa_capturas/` (fuera del repo).
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/alquiler.dart';
import 'package:colportores_mobile/features/cuenta/presentation/pages/alquiler_page.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alquiler_arnes.dart';
import '../../helpers/cuenta_arnes.dart';
import '../../helpers/qa_alquiler_743_arnes.dart';

typedef _Estado = ({
  String nombre,
  RepositorioDeAlquilerControlable Function() repo,
  TipoConexion conexion,
});

final _estados = <_Estado>[
  (
    nombre: '38C01_deuda',
    repo: () => RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: '38C02_por_validar',
    repo: () => RepositorioDeAlquilerControlable(inicial: alquilerConPorValidar),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: '38C03_pagado',
    repo: () => RepositorioDeAlquilerControlable(inicial: alquilerPagado),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: '38C03_pagado_de_mas',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(monto: 2500, pagos: [pagoDe(3000)]),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: '38C04_no_cobra',
    repo: () => RepositorioDeAlquilerControlable(inicial: AlquilerDelColportor.vacio),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: '38C05_sin_conexion',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon(alquilerDelCanvas.campanias, bajadoEn: DateTime(2026, 11, 21, 21)),
    ),
    conexion: TipoConexion.sinConexion,
  ),
  (
    nombre: 'sin_conexion_nunca_bajo',
    repo: () => RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas),
    conexion: TipoConexion.sinConexion,
  ),
  (
    nombre: 'rechazado_y_devuelto',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(
          pagos: [
            pagoDe(
              3000,
              estado: EstadoDePagoDeAlquiler.rechazado,
              motivo: 'el monto no coincide con el ticket',
            ),
            pagoDe(4000, estado: EstadoDePagoDeAlquiler.devuelto),
            pagoDe(6000),
          ],
        ),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (
    nombre: 'dos_campanias',
    repo: () => RepositorioDeAlquilerControlable(
      inicial: alquilerCon([
        campaniaCon(id: 'c-1', pagos: [pagoDe(6000)]),
        campaniaCon(id: 'c-2', nombre: 'Otoño 2026', monto: 10000),
      ]),
    ),
    conexion: TipoConexion.wifi,
  ),
  (nombre: 'cargando', repo: () => RepositorioDeAlquilerControlable(), conexion: TipoConexion.wifi),
  (
    nombre: 'error',
    repo: () => RepositorioDeAlquilerControlable()..fallaAlSuscribir = true,
    conexion: TipoConexion.wifi,
  ),
];

void main() {
  group('con las fuentes reales: cada estado, sin texto cortado y sin palabras partidas', () {
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
            await capturar743(tester, '${estado.nombre}_${tam.key}_${escala}x');

            final falla = tester.takeException();
            expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
            sinTextoCortado743(tester);
            expect(palabrasPartidas743(tester), isEmpty, reason: 'palabras partidas');
          });
        }
      }
    }
  });

  group('la línea «Alquiler» de Mi Cuenta con las fuentes reales', () {
    for (final tam in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('a ${tam.key}, texto $escala', (tester) async {
          await cargarFuentes743(tester);
          await montarCuenta(
            tester,
            RepositorioDeCuentaControlable(inicial: resumenDelCanvas),
            tamano: tam.value,
            escala: escala,
            overrides: overridesDeAlquiler(
              RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas),
            ),
          );
          await tester.pump();
          await capturar743(tester, 'cuenta_33A01_${tam.key}_${escala}x');

          final falla = tester.takeException();
          expect(falla, isNull, reason: falla is FlutterError ? falla.toStringDeep() : '$falla');
          expect(find.text(r'$ 12.500 por pagar'), findsOneWidget);
          sinTextoCortado743(tester);
        });
      }
    }
  });

  group('casos que el implementador no probó', () {
    testWidgets('si vuelve la red con la pantalla abierta, el aviso de sin conexión se va', (
      tester,
    ) async {
      final red = StreamController<TipoConexion>();
      addTearDown(red.close);
      final repo = RepositorioDeAlquilerControlable(
        inicial: alquilerCon(alquilerDelCanvas.campanias, bajadoEn: DateTime(2026, 11, 21, 21)),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alquilerRepositoryProvider.overrideWithValue(repo),
            relojCuentaProvider.overrideWithValue(() => ahoraDelAlquiler),
            conexionProvider.overrideWith((ref) => red.stream),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: const AlquilerPage(colportorId: 'col-1'),
          ),
        ),
      );
      red.add(TipoConexion.sinConexion);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin conexión.'), findsOneWidget);

      red.add(TipoConexion.wifi);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sin conexión.'), findsNothing);
      expect(find.text('Cargar pago de alquiler'), findsOneWidget);
    });

    testWidgets('un alquiler con centavos se ve con coma y no se redondea', (tester) async {
      final repo = RepositorioDeAlquilerControlable(
        inicial: alquilerCon([
          const AlquilerDeCampania(
            campaniaId: 'c-1',
            campania: 'Primavera 2026',
            montoCentavos: 150050,
            pagos: [],
          ),
        ]),
      );
      await montarAlquiler(tester, repo);
      expect(find.text(r'$ 1.500,50'), findsWidgets);
    });

    testWidgets('con las dos campañas pagadas no hay ningún botón de cargar pago', (tester) async {
      final repo = RepositorioDeAlquilerControlable(
        inicial: alquilerCon([
          campaniaCon(id: 'c-1', pagos: [pagoDe(18500)]),
          campaniaCon(id: 'c-2', nombre: 'Otoño 2026', monto: 10000, pagos: [pagoDe(10000)]),
        ]),
      );
      await montarAlquiler(tester, repo);
      expect(find.text('Cargar pago de alquiler'), findsNothing);
      expect(find.text(r'$ 0'), findsNWidgets(2));
    });

    testWidgets('pagado de más y otro pago por validar a la vez: dice las dos cosas, sin mezclar', (
      tester,
    ) async {
      final repo = RepositorioDeAlquilerControlable(
        inicial: alquilerCon([
          campaniaCon(
            monto: 2500,
            pagos: [
              pagoDe(1000, estado: EstadoDePagoDeAlquiler.porValidar, fecha: diaDeAlquiler(11, 20)),
              pagoDe(3000),
            ],
          ),
        ], trasladado: 500),
      );
      await montarAlquiler(tester, repo);
      expect(find.textContaining('Pagaste \$ 500 de más'), findsOneWidget);
      expect(find.textContaining('Tenés \$ 1.000 por validar'), findsOneWidget);
      expect(find.text('Cargar pago de alquiler'), findsNothing);
    });

    testWidgets('el error se anuncia como región viva y «Reintentar» está a mano', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarAlquiler(tester, RepositorioDeAlquilerControlable()..fallaAlSuscribir = true);
      final nodo = tester.getSemantics(find.textContaining('No pudimos traer tu alquiler'));
      expect(nodo.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(find.text('Reintentar'), findsOneWidget);
      semantica.dispose();
    });

    test('privacidad: ni el motivo de un rechazo ni los montos salen en toString()', () {
      final pago = pagoDe(
        3000,
        estado: EstadoDePagoDeAlquiler.rechazado,
        motivo: 'transferencia de Marta Pérez',
      );
      final alquiler = alquilerCon([
        campaniaCon(pagos: [pago]),
      ]);
      for (final texto in ['$pago', '$alquiler', '${alquiler.campanias.single}']) {
        expect(texto, isNot(contains('Marta')));
        expect(texto, isNot(contains('3000')));
        expect(texto, isNot(contains('300000')));
      }
    });

    test('el alquiler no bloquea: ni pedidos ni ventas ni cobros leen el alquiler', () {
      final prohibidos = [
        'alquilerDelColportorProvider',
        'AlquilerRepository',
        'AlquilerDelColportor',
      ];
      for (final carpeta in ['pedidos', 'ventas', 'cobros', 'jornada', 'stock', 'entregas']) {
        final dir = Directory('lib/features/$carpeta');
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart')) continue;
          final codigo = f.readAsStringSync();
          for (final p in prohibidos) {
            expect(codigo.contains(p), isFalse, reason: '${f.path} usa $p');
          }
        }
      }
    });
  });

  group('hallazgos de la revisión visual (corren con --dart-define=QA_HALLAZGOS=true)', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'QA #389 H1: «Alquiler de la campaña» y «Pagado (validado)» van con el rótulo a la izquierda '
        'y la cifra a la derecha, alineadas en columna (38C kv), texto $escala',
        (tester) async {
          await cargarFuentes743(tester);
          await montarAlquiler(
            tester,
            RepositorioDeAlquilerControlable(inicial: alquilerDelCanvas),
            tamano: const Size(412, 915),
            escala: escala,
          );
          final monto = tester.getRect(find.byKey(const Key('alquiler_monto_0')));
          final pagado = tester.getRect(find.byKey(const Key('alquiler_pagado_0')));
          expect(
            monto.right,
            closeTo(pagado.right, 0.5),
            reason: 'las cifras no quedan en columna',
          );
          final rotulo = tester.getRect(find.text('Alquiler de la campaña'));
          final rotulo2 = tester.getRect(find.text('Pagado (validado)'));
          expect(
            rotulo.left,
            closeTo(rotulo2.left, 0.5),
            reason: 'los rótulos no van a la izquierda',
          );
        },
        skip: !conHallazgos743,
      );
    }
  });
}
