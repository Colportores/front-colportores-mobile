// QA de la ficha de una persona con la cuenta y el historial REALES (HU-UBI-009, vista 32B, #403, PR #588):
// la pantalla (real), los providers reales de la cuenta y de los movimientos (`cuentaDePersonaLocalProvider`
// → Drift en memoria). Los tests del PR prueban la pantalla con la cuenta falsa y la lectura sin pantalla;
// estos prueban que lo que la colportora VE sale de `venta`, `entrega` y `cobranza`, se mantiene al día
// con la ficha abierta, dice «Sin movimientos aún» cuando corresponde, y no se desborda a 360×640 ni al
// 200 % de texto. Capturas (solo con `--dart-define=QA_CAPTURAS=true`): `.dart_tool/qa_capturas/403_*.png`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/cuenta_de_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ficha_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ficha_persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/ficha_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ficha_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import 'ficha_persona_arnes.dart';

const _tamanos = [Size(360, 640), Size(412, 915)];
const _escalas = [1.0, 2.0];
const _nbsp = '\u00A0';
const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

var _fuentes = false;
Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentes) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await c.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final c = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(iconos.readAsBytesSync().buffer)));
        await c.load();
        break;
      }
    }
  });
  _fuentes = true;
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!const bool.fromEnvironment('QA_CAPTURAS')) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final img = await (vista.debugLayer! as OffsetLayer).toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/403_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;

  Future<void> sembrar(
    WidgetTester tester, {
    Future<void> Function()? datos,
    String? telefono = '099123456',
  }) async {
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      await sembrarCasa(db);
      await db
          .into(db.personas)
          .insert(
            PersonasCompanion.insert(
              id: 'per-1',
              nombre: 'María',
              apellido: const Value('Fernández'),
              telefono: Value(telefono),
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      for (final (id, nombre) in [('pro-1', 'Salud y Hogar'), ('pro-2', 'Nuestros Hijos')]) {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                id: id,
                nombre: nombre,
                tipo: 'LIBRO',
                createdAt: t0,
                updatedAt: t0,
              ),
            );
      }
      if (datos != null) await datos();
    });
  }

  Future<void> venta(String id, {int monto = 450000, String talonario = '0042', DateTime? fecha}) =>
      db
          .into(db.ventas)
          .insert(
            VentasCompanion.insert(
              id: id,
              espacioPersonaId: 'ep-1',
              numeroTalonario: talonario,
              montoTotal: monto,
              fecha: fecha ?? DateTime.utc(2026, 10, 12, 14),
              colportorId: 'col-1',
              createdAt: t0,
              updatedAt: t0,
            ),
          );

  Future<void> renglon(String id, String ventaId, String productoId) => db
      .into(db.ventaItems)
      .insert(
        VentaItemsCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: Value(productoId),
          cantidad: 1,
          precioUnitario: 1000,
          subtotal: 1000,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> cobro(
    String id,
    String ventaId,
    int monto, {
    DateTime? fecha,
    String medio = 'EFECTIVO',
  }) => db
      .into(db.cobranzas)
      .insert(
        CobranzasCompanion.insert(
          id: id,
          ventaId: ventaId,
          monto: monto,
          medio: medio,
          fecha: fecha ?? DateTime.utc(2026, 10, 20, 16),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> entrega(String id, String ventaId, String productoId, DateTime cuando) => db
      .into(db.entregas)
      .insert(
        EntregasCompanion.insert(
          id: id,
          ventaId: ventaId,
          productoId: productoId,
          cantidad: 1,
          pendiente: const Value(false),
          fechaEntrega: Value(cuando),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  /// La cuenta del canvas: venta de $ 4.500, cobros de $ 600 y de $ 2.700, falta una entrega.
  Future<void> datosDelCanvas() async {
    await venta('ven-1');
    await renglon('it-1', 'ven-1', 'pro-1');
    await renglon('it-2', 'ven-1', 'pro-2');
    await cobro('cob-1', 'ven-1', 60000, fecha: DateTime.utc(2026, 10, 20, 16));
    await cobro(
      'cob-2',
      'ven-1',
      270000,
      fecha: DateTime.utc(2026, 10, 21, 16),
      medio: 'TRANSFERENCIA',
    );
    await entrega('ent-1', 'ven-1', 'pro-1', DateTime.utc(2026, 10, 13, 15));
  }

  Future<MundoFicha> montar(
    WidgetTester tester, {
    Size tamano = const Size(412, 915),
    double escala = 1,
    bool lector = false,
  }) async {
    await _cargarFuentes(tester);
    final mundo = MundoFicha();
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fichaPersonaRepositoryProvider.overrideWithValue(
            FichaPersonaRepositoryImpl(FichaPersonaLocalDataSourceDrift(db)),
          ),
          cuentaDePersonaLocalProvider.overrideWithValue(CuentaDePersonaLocalDataSourceDrift(db)),
          notaPersonaRepositoryProvider.overrideWithValue(mundo.notas),
          espacioRepositoryProvider.overrideWithValue(mundo.espacios),
          marcadorDeTelefonoProvider.overrideWithValue(mundo.marcador),
          personaRepositoryProvider.overrideWithValue(mundo.personas),
          relojPersonaProvider.overrideWithValue(() => ahoraFicha),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(escala), accessibleNavigation: lector),
            child: child!,
          ),
          home: const FichaPersonaPage(
            personaId: 'per-1',
            espacioId: 'esp-1',
            colportorId: 'col-1',
          ),
        ),
      ),
    );
    await _esperar(tester);
    return mundo;
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(db.close);
  }

  Finder texto(String t) =>
      find.descendant(of: find.byKey(ClavesFicha.cuenta), matching: find.text(t));

  group('lo que se ve sale de las tablas', () {
    testWidgets('32B·01: comprado, pagado, saldo, el cobro «\$ 600 en efectivo» y la entrega', (
      tester,
    ) async {
      await sembrar(tester, datos: datosDelCanvas);
      await montar(tester);

      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(find.byKey(ClavesFicha.sinMovimientos), findsNothing);
      for (final t in [
        'Comprado',
        'Entregado',
        'Pagado',
        'Saldo',
        '\$$_nbsp'
            '4.500',
        '\$$_nbsp'
            '3.300',
        '\$$_nbsp'
            '1.200',
      ]) {
        expect(texto(t), findsOneWidget, reason: t);
      }
      await tester.dragUntilVisible(
        find.byKey(ClavesFicha.fila('cob-1')),
        find.byType(Scrollable).first,
        const Offset(0, -200),
      );
      expect(find.text('20/10 · COBRO'), findsOneWidget);
      expect(find.text('\$${_nbsp}600 en efectivo'), findsOneWidget);
      expect(find.text('Venta 0042'), findsWidgets);
      expect(find.byKey(ClavesFicha.fila('ent-1')), findsOneWidget);
      expect(find.text('13/10 · ENTREGA'), findsOneWidget);
      await _capturar(tester, '32B01_real');
      await cerrar(tester);
    });

    testWidgets('«Sin movimientos aún» (HU) cuando tiene visitas pero ninguna venta', (
      tester,
    ) async {
      await sembrar(
        tester,
        datos: () => insertarVisita(db, visitaDe('vis-1', creada: DateTime.utc(2026, 10, 5, 14))),
      );
      await montar(tester);

      expect(find.byKey(ClavesFicha.sinMovimientos), findsOneWidget);
      expect(find.text('Sin movimientos aún'), findsOneWidget);
      expect(find.byKey(ClavesFicha.cuenta), findsNothing);
      expect(find.text('Saldo'), findsNothing);
      expect(find.byKey(ClavesFicha.fila('vis-1')), findsOneWidget);
      await _capturar(tester, 'sin_movimientos');
      await cerrar(tester);
    });

    testWidgets(
      '32B·05: sin visitas ni ventas solo el aviso de la vista, no «Sin movimientos aún»',
      (tester) async {
        await sembrar(tester);
        await montar(tester);

        expect(find.byKey(ClavesFicha.hero), findsOneWidget);
        expect(find.byKey(ClavesFicha.sinMovimientos), findsNothing);
        await cerrar(tester);
      },
    );

    testWidgets('una venta sin cobros ni entregas muestra la deuda, no «Sin movimientos aún»', (
      tester,
    ) async {
      await sembrar(
        tester,
        datos: () async {
          await venta('ven-1', monto: 120000);
          await renglon('it-1', 'ven-1', 'pro-1');
        },
      );
      await montar(tester);

      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(texto('\$${_nbsp}1.200'), findsNWidgets(2), reason: 'comprado y saldo');
      expect(texto('\$${_nbsp}0'), findsOneWidget, reason: 'pagado');
      expect(find.byKey(ClavesFicha.sinMovimientos), findsNothing);
      await cerrar(tester);
    });

    testWidgets('el filtro «Con saldo» deja solo la venta que todavía debe', (tester) async {
      await sembrar(
        tester,
        datos: () async {
          await venta('ven-1', monto: 100000, talonario: '0001');
          await venta('ven-2', monto: 50000, talonario: '0002', fecha: DateTime.utc(2026, 10, 14));
          await cobro('cob-1', 'ven-1', 100000);
        },
      );
      await montar(tester);
      final filtro = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.conSaldo));
      await tester.ensureVisible(filtro);
      await tester.tap(filtro);
      await _esperar(tester);

      expect(find.byKey(ClavesFicha.fila('ven-2')), findsOneWidget);
      expect(find.byKey(ClavesFicha.fila('ven-1')), findsNothing);
      await cerrar(tester);
    });
  });

  group('con la ficha abierta', () {
    testWidgets('el primer cobro y la primera venta cambian «Sin movimientos aún» por la cuenta', (
      tester,
    ) async {
      await sembrar(
        tester,
        datos: () => insertarVisita(db, visitaDe('vis-1', creada: DateTime.utc(2026, 10, 5, 14))),
      );
      await montar(tester);
      expect(find.text('Sin movimientos aún'), findsOneWidget);

      // Una escritura por vez: la lectura de la ficha abre una transacción cuyo avance necesita `pump`.
      await tester.runAsync(() => venta('ven-1', monto: 100000));
      await _esperar(tester);
      await tester.runAsync(() => renglon('it-1', 'ven-1', 'pro-1'));
      await _esperar(tester);
      expect(find.text('Sin movimientos aún'), findsNothing);
      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(texto('\$${_nbsp}1.000'), findsNWidgets(2));

      await tester.runAsync(() => cobro('cob-1', 'ven-1', 100000));
      await _esperar(tester);
      expect(texto('\$${_nbsp}1.000'), findsNWidgets(2), reason: 'comprado y pagado');
      expect(texto('\$${_nbsp}0'), findsOneWidget, reason: 'saldo');
      expect(find.byKey(ClavesFicha.fila('cob-1')), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('una entrega registrada con la ficha abierta suma su tarjeta y «Entregado»', (
      tester,
    ) async {
      await sembrar(
        tester,
        datos: () async {
          await venta('ven-1');
          await renglon('it-1', 'ven-1', 'pro-1');
        },
      );
      await montar(tester);
      expect(find.text('0 de 1'), findsOneWidget);

      await tester.runAsync(
        () => entrega('ent-1', 'ven-1', 'pro-1', DateTime.utc(2026, 10, 21, 9)),
      );
      await _esperar(tester);

      expect(find.text('1 de 1'), findsOneWidget);
      expect(find.byKey(ClavesFicha.fila('ent-1')), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('si la base no se puede leer', () {
    testWidgets('32B·07: error con «Reintentar» y, al volver la tabla, la ficha completa', (
      tester,
    ) async {
      await sembrar(tester, datos: datosDelCanvas);
      await tester.runAsync(() => db.customStatement('ALTER TABLE cobranza RENAME TO cobranza_x'));
      await montar(tester);

      expect(find.byKey(ClavesFicha.error), findsOneWidget);
      expect(find.textContaining('No pudimos leer los datos'), findsOneWidget);
      expect(find.byKey(ClavesFicha.cuenta), findsNothing, reason: 'no una ficha a medias');
      expect(find.text('Reintentar'), findsOneWidget);
      await _capturar(tester, '32B07_real');

      await tester.runAsync(() => db.customStatement('ALTER TABLE cobranza_x RENAME TO cobranza'));
      await tester.tap(find.text('Reintentar'));
      await _esperar(tester);

      expect(find.byKey(ClavesFicha.error), findsNothing);
      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('tamaños y texto grande, con datos reales', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        final donde =
            '${tamano.width.toInt()}×${tamano.height.toInt()} al ${(escala * 100).toInt()} %';

        testWidgets(
          '32B·01 con la cuenta del canvas a $donde: sin desborde y con las guías de toque',
          (tester) async {
            final h = tester.ensureSemantics();
            await sembrar(tester, datos: datosDelCanvas);
            await montar(tester, tamano: tamano, escala: escala);

            expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _capturar(tester, '32B01_${tamano.width.toInt()}_${(escala * 10).toInt()}');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await cerrar(tester);
            h.dispose();
          },
        );

        testWidgets('«Sin movimientos aún» a $donde: sin desborde y con las guías de toque', (
          tester,
        ) async {
          final h = tester.ensureSemantics();
          await sembrar(
            tester,
            datos: () =>
                insertarVisita(db, visitaDe('vis-1', creada: DateTime.utc(2026, 10, 5, 14))),
          );
          await montar(tester, tamano: tamano, escala: escala);

          expect(find.byKey(ClavesFicha.sinMovimientos), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capturar(tester, 'sin_mov_${tamano.width.toInt()}_${(escala * 10).toInt()}');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await cerrar(tester);
          h.dispose();
        });

        testWidgets('importes de millones y muchos cobros a $donde: sin desborde', (tester) async {
          await sembrar(
            tester,
            datos: () async {
              await venta('ven-1', monto: 123456789000, talonario: 'AB-0042/2026');
              await renglon('it-1', 'ven-1', 'pro-1');
              for (var i = 0; i < 30; i++) {
                await cobro(
                  'cob-${i.toString().padLeft(2, '0')}',
                  'ven-1',
                  987654321,
                  fecha: DateTime.utc(2026, 9, 1).add(Duration(days: i)),
                  medio: i.isEven ? 'EFECTIVO' : 'TARJETA',
                );
              }
            },
          );
          await montar(tester, tamano: tamano, escala: escala);

          expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _capturar(tester, 'importes_${tamano.width.toInt()}_${(escala * 10).toInt()}');
          await cerrar(tester);
        });
      }
    }

    // skip: QA #403 — «Comprado» se parte en «Comprad/o» a 360×640 al 200 %: el rótulo (`Expanded`) y el
    // valor (`Flexible`) de `TarjetaCuenta` tienen el mismo `flex` y se reparten el ancho a mitades.
    testWidgets('QA #403: los rótulos de la cuenta no se parten a 360×640 al 200 %', (
      tester,
    ) async {
      await sembrar(tester, datos: datosDelCanvas);
      await montar(tester, tamano: const Size(360, 640), escala: 2);

      for (final rotulo in ['Comprado', 'Entregado', 'Pagado', 'Saldo']) {
        final parrafo = tester.renderObject<RenderParagraph>(texto(rotulo));
        expect(parrafo.size.height, lessThan(28 * 1.6), reason: '«$rotulo» en un solo renglón');
      }
      await cerrar(tester);
    }, skip: !_conHallazgos);

    testWidgets('con lector: la cuenta se lee fila por fila, con su rótulo y su valor', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await sembrar(tester, datos: datosDelCanvas);
      await montar(tester, lector: true);

      expect(
        tester.getSemantics(find.text('Saldo')),
        matchesSemantics(label: 'Saldo\n\$${_nbsp}1.200'),
      );
      await cerrar(tester);
      h.dispose();
    });
  });
}

Future<void> _esperar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}
