import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/totales_de_depositos.dart';
import '../models/deposito_model.dart';

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

  static const _condicionValidado = 'validado_en IS NOT NULL AND rechazado_en IS NULL';
  static const _condicionPorValidar = 'validado_en IS NULL AND rechazado_en IS NULL';

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
    '$_condicionValidado${hasta == null ? '' : ' AND validado_en <= ?'}',
    hasta?.toUtc().millisecondsSinceEpoch,
  );

  /// Lo registrado que todavía no validó ni rechazó el coordinador, en centavos.
  Future<int> porValidar() => _suma(_condicionPorValidar, null);

  /// Los depósitos que suman a una de las dos sumas (los validados y los que esperan), del más viejo al
  /// más nuevo: **con las mismas condiciones que [validado] y [porValidar]**, así la lista de Mi plata
  /// suma exactamente lo que dice la cifra. Un depósito rechazado o dado de baja no está.
  Future<List<DepositoDeLaLista>> listar() async {
    final filas = await _db
        .customSelect(
          'SELECT monto, fecha, destino, concepto, ($_condicionValidado) AS validado FROM deposito '
          'WHERE deleted_at IS NULL AND (($_condicionValidado) OR ($_condicionPorValidar)) '
          'ORDER BY fecha, id',
          readsFrom: tablas,
        )
        .get();
    return [
      for (final f in filas)
        DepositoDeLaLista(
          montoCentavos: f.read<int>('monto'),
          fecha: DateTime.fromMillisecondsSinceEpoch(f.read<int>('fecha'), isUtc: true),
          destino: DepositoModel.destinoDesdeCodigo(f.read<String>('destino')),
          concepto: DepositoModel.conceptoDesdeCodigo(f.read<String>('concepto')),
          validado: f.read<int>('validado') == 1,
        ),
    ];
  }

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
