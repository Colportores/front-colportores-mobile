import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Qué cobro cuenta para lo que debe una venta: **la única definición** que usan el saldo
/// (`CobranzaLocalDataSourceDrift`, HU-COB-005) y el color de la casa (`HouseStatusUpdaterDrift`,
/// R-UB08), para que nunca cuenten cobros distintos.
///
/// Cuenta el que no está dado de baja (`deleted_at IS NULL`) ni anulado (`anulado_at IS NULL`,
/// HU-COB-006, #422): al anular un cobro, el saldo y el color de la casa dejan de contarlo a la vez.
abstract final class CobroValido {
  /// La condición SQL sobre la tabla `cobranza` con el alias `c`.
  static const sql = 'c.deleted_at IS NULL AND c.anulado_at IS NULL';

  /// Lo cobrado de la venta [ventaId], en centavos: la suma de sus cobros válidos (0 si no hay).
  static Future<int> cobradoDe(AppDatabase db, String ventaId) async {
    final fila = await db
        .customSelect(
          'SELECT COALESCE(SUM(c.monto), 0) AS cobrado FROM cobranza c '
          'WHERE c.venta_id = ? AND $sql',
          variables: [Variable<String>(ventaId)],
        )
        .getSingle();
    return fila.read<int>('cobrado');
  }
}
