import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/totales_de_depositos.dart';

/// Las sumas de los depósitos de la tabla `deposito`, por estado: **la única definición** de qué
/// depósito cuenta como validado y cuál como «por validar», para que Mi Cuenta (HU-CTA-001) y Mi plata
/// (HU-CTA-003) nunca sumen distinto.
///
/// El estado sale de las columnas que baja el pull (`validado_en`, `rechazado_en`): un depósito vivo
/// (`deleted_at IS NULL`) es **rechazado** si tiene `rechazado_en` (aunque tuviera `validado_en`: ante
/// la duda no se acredita), **validado** si tiene `validado_en`, y **por validar** si no tiene ninguna.
final class TotalesDeDepositosDrift {
  TotalesDeDepositosDrift(this._db);

  final AppDatabase _db;

  /// Las tablas que, al cambiar, cambian estas sumas.
  Set<ResultSetImplementation<dynamic, dynamic>> get tablas => {_db.depositos};

  /// Las dos sumas de ahora.
  Future<TotalesDeDepositos> leer() async => TotalesDeDepositos(
    validadoCentavos: await validado(),
    porValidarCentavos: await porValidar(),
  );

  /// Lo validado, en centavos. Con [hasta], lo que ya estaba validado entonces (`validado_en <= hasta`):
  /// la base de «contra la semana pasada».
  Future<int> validado({DateTime? hasta}) => _suma(
    'validado_en IS NOT NULL AND rechazado_en IS NULL'
    '${hasta == null ? '' : ' AND validado_en <= ?'}',
    hasta?.toUtc().millisecondsSinceEpoch,
  );

  /// Lo registrado que todavía no validó ni rechazó el coordinador, en centavos.
  Future<int> porValidar() => _suma('validado_en IS NULL AND rechazado_en IS NULL', null);

  Future<int> _suma(String condicion, int? ms) async {
    final fila = await _db
        .customSelect(
          'SELECT COALESCE(SUM(monto), 0) AS suma FROM deposito '
          'WHERE deleted_at IS NULL AND $condicion',
          variables: [if (ms != null) Variable<int>(ms)],
          readsFrom: tablas,
        )
        .getSingle();
    return fila.read<int>('suma');
  }
}
