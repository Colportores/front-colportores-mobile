import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/sync_queue_table.dart';
import '../../domain/entities/estado_alta_ubicacion.dart';
import '../../domain/services/consultor_alta_ubicacion.dart';

/// [ConsultorAltaUbicacion] sobre `sync_queue`: el alta de una ubicación (`op = insert`) que sigue
/// en la cola sin haber sido aceptada.
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
            j.state.isIn(EstadoJob.sinAplicar),
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
