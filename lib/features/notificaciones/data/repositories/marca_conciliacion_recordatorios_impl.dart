import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/conciliacion_recordatorios_repository.dart';

/// [MarcaConciliacionRecordatorios] sobre el almacén seguro: `ClaveSegura.ultimaConciliacionRecordatorios`
/// guarda los milisegundos desde la época (UTC). Un valor que no es un número cuenta como «nunca se
/// guardó»: la próxima revisión solo vuelve a fijar la marca.
final class MarcaConciliacionRecordatoriosImpl implements MarcaConciliacionRecordatorios {
  MarcaConciliacionRecordatoriosImpl(this._almacen);

  final AlmacenSeguro _almacen;

  @override
  Future<DateTime?> leer() async {
    final ms = int.tryParse(
      (await _almacen.leer(ClaveSegura.ultimaConciliacionRecordatorios)) ?? '',
    );
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> guardar(DateTime hasta) => _almacen.escribir(
    ClaveSegura.ultimaConciliacionRecordatorios,
    hasta.toUtc().millisecondsSinceEpoch.toString(),
  );
}

/// [MarcaConciliacionRecordatorios] en memoria: el default de los tests y de la app sin Keystore.
/// **No es código de producción**: `main.dart` lo reemplaza por [MarcaConciliacionRecordatoriosImpl].
class MarcaConciliacionRecordatoriosEnMemoria implements MarcaConciliacionRecordatorios {
  MarcaConciliacionRecordatoriosEnMemoria([this.marca]);

  DateTime? marca;

  /// Con `true`, las lecturas lanzan (simula un almacén roto).
  bool fallaAlLeer = false;

  /// Con `true`, los guardados lanzan y no guardan nada.
  bool fallaAlGuardar = false;

  @override
  Future<DateTime?> leer() async {
    if (fallaAlLeer) throw const AlmacenSeguroException(operacion: 'leer');
    return marca;
  }

  @override
  Future<void> guardar(DateTime hasta) async {
    if (fallaAlGuardar) throw const AlmacenSeguroException(operacion: 'escribir');
    marca = hasta.toUtc();
  }
}
