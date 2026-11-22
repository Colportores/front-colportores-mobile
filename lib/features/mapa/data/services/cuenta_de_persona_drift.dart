import '../../domain/entities/ficha_de_persona.dart';
import '../../domain/services/cuenta_de_persona.dart';
import '../../domain/services/movimientos_de_cuenta_de_persona.dart';
import '../datasources/cuenta_de_persona_local_data_source_drift.dart';

/// [MovimientosDeCuentaDeLaPersona] leído de la DB local: las entregas hechas y los cobros de la
/// persona para el historial de la ficha (HU-UBI-009, #403).
final class MovimientosDeCuentaDrift implements MovimientosDeCuentaDeLaPersona {
  const MovimientosDeCuentaDrift(this._local);

  final CuentaDePersonaLocalDataSourceDrift _local;

  @override
  Stream<List<MovimientoDeFicha>> observar(String personaId) =>
      _local.observarMovimientos(personaId);
}

/// [CuentasDePersonas] leído de la DB local: comprado, entregado, pagado y saldo de la persona
/// (HU-COB-005). Si la base no se puede leer, lanza: quien lo pide no da por hecho que no debe nada.
final class CuentasDePersonasDrift implements CuentasDePersonas {
  const CuentasDePersonasDrift(this._local);

  final CuentaDePersonaLocalDataSourceDrift _local;

  @override
  Future<ResumenCuentaPersona?> resumenDe(String personaId) => _local.resumenDe(personaId);
}
