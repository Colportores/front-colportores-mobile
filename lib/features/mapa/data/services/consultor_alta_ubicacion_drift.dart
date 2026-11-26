import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/sync_queue_table.dart';
import '../../domain/entities/estado_alta_ubicacion.dart';
import '../../domain/services/consultor_alta_ubicacion.dart';

/// [ConsultorAltaUbicacion] sobre `sync_queue`: el alta de una ubicación (`op = insert`) que sigue
/// en la cola sin haber sido aceptada: esperando, viajando o rechazada por el servidor (`INVALID`).
final class ConsultorAltaUbicacionDrift implements ConsultorAltaUbicacion {
  const ConsultorAltaUbicacionDrift(this._db);

  final AppDatabase _db;

  @override
  Stream<Map<String, EstadoAltaUbicacion>> observarSinConfirmar() {
    final cola = _db.syncQueue;
    final consulta = _db.select(cola)
      ..where(
        (j) =>
            j.entity.equals('ubicacion') &
            j.op.equals('insert') &
            // `INVALID`: el servidor la rechazó por un error de datos y nunca la tuvo; también es
            // «Par local» (decisión de Cristian, 05/11, «Alta invalid»).
            j.state.isIn([...EstadoJob.sinAplicar, EstadoJob.invalid]),
      );
    return consulta.watch().map(
      (jobs) => {
        for (final j in jobs)
          if (j.rowPk != null)
            j.rowPk!: j.state == EstadoJob.inFlight
                ? EstadoAltaUbicacion.subiendo
                : EstadoAltaUbicacion.soloEnTelefono,
      },
    );
  }
}
