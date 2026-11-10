// QA del PR #678 (HU-VEN-003, #433) sobre la ficha de la persona (vista 32B, 32B·01 y 32B·03): las
// entregas pendientes con `fecha_prevista` salen en el historial «SÁB 31/10 · ENTREGA PENDIENTE» y el
// filtro «Entrega pendiente» deja de estar vacío (casilla de #403, decisión del 30/10). La pantalla es
// la real; el historial sale de la base real (`CuentaDePersonaLocalDataSourceDrift`) y se le pasa a la
// ficha en vivo, como lo hace `MovimientosDeCuentaDrift`.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/cuenta_de_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/services/filtro_de_historial.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/qa_ficha_persona_563_arnes.dart' show capturar563, cargarFuentes563;
import 'ficha_persona_arnes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late CuentaDePersonaLocalDataSourceDrift fuente;
  StreamSubscription<List<MovimientoDeFicha>>? suscripcion;
  // Sábado 31/10/2026, 13:00 UTC.
  final sabado = DateTime.utc(2026, 10, 31, 13);

  Future<void> sembrar() async {
    await sembrarCasa(db);
    await db
        .into(db.personas)
        .insert(
          PersonasCompanion.insert(id: 'per-1', nombre: 'María', createdAt: t0, updatedAt: t0),
        );
    for (final (id, nombre) in [('pro-1', 'Nuestros Hijos'), ('pro-2', 'Salud y Hogar')]) {
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
    await db
        .into(db.ventas)
        .insert(
          VentasCompanion.insert(
            id: 'ven-1',
            espacioPersonaId: 'ep-1',
            numeroTalonario: '0042',
            montoTotal: 120000,
            fecha: DateTime.utc(2026, 10, 12, 14),
            colportorId: 'col-1',
            createdAt: t0,
            updatedAt: t0,
          ),
        );
  }

  Future<void> entrega(
    String id,
    String producto, {
    int cantidad = 1,
    bool pendiente = true,
    DateTime? prevista,
  }) => db
      .into(db.entregas)
      .insert(
        EntregasCompanion.insert(
          id: id,
          ventaId: 'ven-1',
          productoId: producto,
          cantidad: cantidad,
          pendiente: Value(pendiente),
          fechaPrevista: Value(prevista),
          fechaEntrega: Value(pendiente ? null : DateTime.utc(2026, 10, 13, 15)),
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> esperar(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  /// Arma la base con [armar], monta la ficha real y le pasa el historial de la base en vivo.
  Future<MundoFicha> montar(
    WidgetTester tester,
    Future<void> Function() armar, {
    Size tamano = const Size(412, 915),
    double escala = 1,
  }) async {
    await cargarFuentes563(tester);
    final mundo = MundoFicha();
    await tester.runAsync(() async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      fuente = CuentaDePersonaLocalDataSourceDrift(db);
      await sembrar();
      await armar();
      mundo.cuentas.cuenta = (await fuente.resumenDe('per-1'))!;
      suscripcion = fuente.observarMovimientos('per-1').listen(mundo.movimientos.poner);
    });
    await montarFicha(tester, mundo, tamano: tamano, escala: escala);
    await esperar(tester);
    return mundo;
  }

  Future<void> cerrar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      await suscripcion?.cancel();
      await db.close();
    });
  }

  Future<void> llegarAlHistorial(WidgetTester tester, Finder f) async {
    final lista = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(f, 300, scrollable: lista);
    await tester.ensureVisible(f);
    await tester.pump();
  }

  group('32B·01 el historial muestra la entrega pendiente con su fecha', () {
    testWidgets('«SÁB 31/10 · ENTREGA PENDIENTE» con lo que falta entregar, y la hecha aparte', (
      tester,
    ) async {
      await montar(tester, () async {
        await entrega('ent-1', 'pro-1', pendiente: true, prevista: sabado);
        await entrega('ent-2', 'pro-2', cantidad: 2, pendiente: true, prevista: sabado);
        await entrega('ent-3', 'pro-1', pendiente: false);
      });

      await llegarAlHistorial(tester, find.textContaining('ENTREGA PENDIENTE'));
      expect(find.text('SÁB 31/10 · ENTREGA PENDIENTE'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1 + Salud y Hogar × 2'), findsOneWidget);
      expect(find.text('13/10 · ENTREGA'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capturar563(tester, '678_historial_con_pendiente');
      await cerrar(tester);
    });

    testWidgets('una pendiente sin fecha prevista no se muestra: no se inventa un día', (
      tester,
    ) async {
      await montar(tester, () => entrega('ent-1', 'pro-1', pendiente: true));

      expect(find.textContaining('ENTREGA PENDIENTE'), findsNothing);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });

    testWidgets('«Entregado» de la cuenta dice «1 de 2» con una hecha y una pendiente', (
      tester,
    ) async {
      await montar(tester, () async {
        await db
            .into(db.ventaItems)
            .insert(
              VentaItemsCompanion.insert(
                id: 'it-1',
                ventaId: 'ven-1',
                productoId: const Value('pro-1'),
                cantidad: 2,
                precioUnitario: 1000,
                subtotal: 2000,
                createdAt: t0,
                updatedAt: t0,
              ),
            );
        await entrega('ent-1', 'pro-1', pendiente: false);
        await entrega('ent-2', 'pro-1', pendiente: true, prevista: sabado);
      });

      expect(find.byKey(ClavesFicha.cuenta), findsOneWidget);
      expect(find.text('1 de 2'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('al cumplirse la entrega, la fila pasa a «ENTREGA» sin reabrir la ficha', (
      tester,
    ) async {
      await montar(tester, () => entrega('ent-1', 'pro-1', pendiente: true, prevista: sabado));
      await llegarAlHistorial(tester, find.textContaining('ENTREGA PENDIENTE'));
      expect(find.text('SÁB 31/10 · ENTREGA PENDIENTE'), findsOneWidget);

      await tester.runAsync(
        () => (db.update(db.entregas)).write(
          EntregasCompanion(
            pendiente: const Value(false),
            fechaEntrega: Value(DateTime.utc(2026, 10, 30, 15)),
          ),
        ),
      );
      await esperar(tester);

      expect(find.textContaining('ENTREGA PENDIENTE'), findsNothing);
      expect(find.text('30/10 · ENTREGA'), findsOneWidget);
      await cerrar(tester);
    });

    testWidgets('el lector de pantalla oye «ENTREGA PENDIENTE» con el día y lo que falta', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await montar(tester, () => entrega('ent-1', 'pro-1', pendiente: true, prevista: sabado));
      await llegarAlHistorial(tester, find.textContaining('ENTREGA PENDIENTE'));

      expect(
        find.bySemanticsLabel(RegExp(r'SÁB 31/10 · ENTREGA PENDIENTE\. Nuestros Hijos × 1')),
        findsOneWidget,
      );
      h.dispose();
      await cerrar(tester);
    });
  });

  group('32B·03 filtro «Entrega pendiente»', () {
    testWidgets('deja solo la pendiente fechada y oculta la entrega hecha', (tester) async {
      await montar(tester, () async {
        await entrega('ent-1', 'pro-1', pendiente: true, prevista: sabado);
        await entrega('ent-2', 'pro-2', pendiente: false);
      });
      final filtro = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente));
      await llegarAlHistorial(tester, filtro);

      await tester.tap(filtro);
      await esperar(tester);

      expect(find.text('SÁB 31/10 · ENTREGA PENDIENTE'), findsOneWidget);
      expect(find.text('13/10 · ENTREGA'), findsNothing);
      expect(find.byKey(ClavesFicha.sinResultados), findsNothing);
      await cerrar(tester);
    });

    testWidgets('sin pendientes dice «No hay entregas pendientes.» y «Todo» a mano lo deshace', (
      tester,
    ) async {
      await montar(tester, () => entrega('ent-2', 'pro-2', pendiente: false));
      final filtro = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.entregaPendiente));
      await llegarAlHistorial(tester, filtro);

      await tester.tap(filtro);
      await esperar(tester);

      expect(find.text('No hay entregas pendientes.'), findsOneWidget);
      final todo = find.byKey(ClavesFicha.filtro(FiltroDeHistorial.todo));
      await tester.ensureVisible(todo);
      await tester.tap(todo);
      await esperar(tester);
      expect(find.text('13/10 · ENTREGA'), findsOneWidget);
      await cerrar(tester);
    });
  });

  group('casos límite del historial', () {
    testWidgets('30 entregas pendientes de otros tantos días no desbordan la ficha', (
      tester,
    ) async {
      await montar(tester, () async {
        for (var i = 0; i < 30; i++) {
          await entrega(
            'ent-$i',
            i.isEven ? 'pro-1' : 'pro-2',
            pendiente: true,
            prevista: sabado.add(Duration(days: i)),
          );
        }
      });

      expect(find.byKey(ClavesFicha.historial), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cerrar(tester);
    });

    for (final (tamano, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 2.0),
    ]) {
      testWidgets('la fila pendiente con un producto de nombre larguísimo no se corta · '
          '${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x', (tester) async {
        await montar(
          tester,
          () async {
            await (db.update(db.productos)).write(
              const ProductosCompanion(
                nombre: Value(
                  'Un libro con un título larguísimo que no entra en una sola línea de la ficha',
                ),
              ),
            );
            await entrega('ent-1', 'pro-1', pendiente: true, prevista: sabado);
          },
          tamano: tamano,
          escala: escala,
        );
        await llegarAlHistorial(tester, find.textContaining('ENTREGA PENDIENTE'));

        expect(tester.takeException(), isNull);
        await capturar563(tester, '678_pendiente_${tamano.width.toInt()}_x$escala');
        for (final e in find.byType(RichText).evaluate()) {
          final texto = e.renderObject! as RenderParagraph;
          expect(
            texto.didExceedMaxLines,
            isFalse,
            reason: 'texto cortado: ${texto.text.toPlainText()}',
          );
        }
        await cerrar(tester);
      });
    }
  });
}
