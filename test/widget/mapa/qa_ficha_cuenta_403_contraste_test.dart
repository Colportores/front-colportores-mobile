// QA de la ficha con la cuenta real (HU-UBI-009, #403, PR #588): contraste del texto (WCAG 1.4.3, AA) en la
// tarjeta de la cuenta, en «Sin movimientos aún» y en las filas de cobros y entregas, a 360×640 y 412×915,
// al 100 % y al 200 %. Archivo aparte con la letra de prueba (Ahem): con las fuentes reales el
// `textContrastGuideline` da falsos negativos.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/cuenta_de_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ficha_persona_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ficha_persona_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/ficha_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/baja_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ficha_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/notas_persona_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import 'ficha_persona_arnes.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<AppDatabase> base(WidgetTester tester, {required bool conVentas}) async {
    final db = await tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      await sembrarCasa(db);
      await db
          .into(db.personas)
          .insert(
            PersonasCompanion.insert(
              id: 'per-1',
              nombre: 'María',
              apellido: const Value('Fernández'),
              telefono: const Value('099123456'),
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              id: 'pro-1',
              nombre: 'Salud y Hogar',
              tipo: 'LIBRO',
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      if (conVentas) {
        await db
            .into(db.ventas)
            .insert(
              VentasCompanion.insert(
                id: 'ven-1',
                espacioPersonaId: 'ep-1',
                numeroTalonario: '0042',
                montoTotal: 450000,
                fecha: DateTime.utc(2026, 10, 12, 14),
                colportorId: 'col-1',
                createdAt: t0,
                updatedAt: t0,
              ),
            );
        await db
            .into(db.ventaItems)
            .insert(
              VentaItemsCompanion.insert(
                id: 'it-1',
                ventaId: 'ven-1',
                productoId: const Value('pro-1'),
                cantidad: 1,
                precioUnitario: 1000,
                subtotal: 1000,
                createdAt: t0,
                updatedAt: t0,
              ),
            );
        await db
            .into(db.cobranzas)
            .insert(
              CobranzasCompanion.insert(
                id: 'cob-1',
                ventaId: 'ven-1',
                monto: 60000,
                medio: 'EFECTIVO',
                fecha: DateTime.utc(2026, 10, 20, 16),
                createdAt: t0,
                updatedAt: t0,
              ),
            );
        await db
            .into(db.entregas)
            .insert(
              EntregasCompanion.insert(
                id: 'ent-1',
                ventaId: 'ven-1',
                productoId: 'pro-1',
                cantidad: 1,
                pendiente: const Value(false),
                fechaEntrega: Value(DateTime.utc(2026, 10, 13, 15)),
                createdAt: t0,
                updatedAt: t0,
              ),
            );
      } else {
        await insertarVisita(db, visitaDe('vis-1', creada: DateTime.utc(2026, 10, 5, 14)));
      }
      return db;
    });
    return db!;
  }

  for (final tamano in const [Size(360, 640), Size(412, 915)]) {
    for (final escala in const [1.0, 2.0]) {
      for (final conVentas in const [true, false]) {
        final donde =
            '${conVentas ? 'con cuenta' : 'sin movimientos'} a ${tamano.width.toInt()}×'
            '${tamano.height.toInt()} al ${(escala * 100).toInt()} %';

        testWidgets('contraste del texto, $donde', (tester) async {
          final h = tester.ensureSemantics();
          final db = await base(tester, conVentas: conVentas);
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
                cuentaDePersonaLocalProvider.overrideWithValue(
                  CuentaDePersonaLocalDataSourceDrift(db),
                ),
                notaPersonaRepositoryProvider.overrideWithValue(mundo.notas),
                espacioRepositoryProvider.overrideWithValue(mundo.espacios),
                marcadorDeTelefonoProvider.overrideWithValue(mundo.marcador),
                personaRepositoryProvider.overrideWithValue(mundo.personas),
                relojPersonaProvider.overrideWithValue(() => ahoraFicha),
              ],
              child: MaterialApp(
                theme: temaClaro(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
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
          for (var i = 0; i < 8; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
            await tester.pump(const Duration(milliseconds: 60));
          }

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(db.close);
          h.dispose();
        });
      }
    }
  }
}
