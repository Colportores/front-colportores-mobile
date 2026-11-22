import '../../../../core/database/app_database.dart';
import '../../domain/entities/destino_notificacion.dart';
import '../../domain/usecases/historial_notificaciones_use_cases.dart';

/// Si el lugar al que lleva un aviso sigue en el teléfono (24C·07).
///
/// Una agenda ya no está si se borró (baja lógica) o se canceló; una cumplida o no cumplida sigue
/// teniendo su detalle.
final class ConsultorDestinosNotificacionDrift implements ConsultorDestinosNotificacion {
  ConsultorDestinosNotificacionDrift(this._db);

  final AppDatabase _db;

  @override
  Future<bool> existe(DestinoNotificacion destino) async => switch (destino) {
    DestinoAgenda(:final agendaId) => await _existeAgenda(agendaId),
  };

  Future<bool> _existeAgenda(String agendaId) async {
    final fila = await (_db.select(
      _db.agendas,
    )..where((a) => a.id.equals(agendaId))).getSingleOrNull();
    return fila != null && fila.deletedAt == null && fila.estado != 'CANCELADA';
  }
}
