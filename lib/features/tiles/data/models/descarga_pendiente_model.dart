import '../../domain/entities/descarga_pendiente.dart';
import 'paquete_tiles_model.dart';

/// [DescargaPendiente] como la guarda `descargas_pendientes.json`: el paquete con el que se empezó
/// (dirección, tamaño y huella de cada parte), cuándo se pidió y los dos permisos. Lo que no se
/// puede leer lanza [FormatException]: quien lee descarta esa entrada.
abstract final class DescargaPendienteModel {
  static Map<String, dynamic> aJson(DescargaPendiente pendiente) {
    return {
      'paquete': PaqueteTilesModel.aJson(pendiente.paquete),
      'anotada_en': pendiente.anotadaEn.toUtc().toIso8601String(),
      'permitir_datos_moviles': pendiente.permitirDatosMoviles,
      'pausada_por_el_colportor': pendiente.pausadaPorElColportor,
    };
  }

  static DescargaPendiente desdeJson(Object? json) {
    if (json is! Map<String, dynamic>) throw const FormatException('descarga pendiente inválida');
    final paquete = json['paquete'];
    final fecha = json['anotada_en'];
    final datos = json['permitir_datos_moviles'];
    final pausada = json['pausada_por_el_colportor'];
    final anotada = fecha is String ? DateTime.tryParse(fecha) : null;
    if (paquete is! Map<String, dynamic> || anotada == null || datos is! bool || pausada is! bool) {
      throw const FormatException('descarga pendiente con campos inválidos');
    }
    return DescargaPendiente(
      paquete: PaqueteTilesModel.desdeJson(paquete),
      anotadaEn: anotada.toUtc(),
      permitirDatosMoviles: datos,
      pausadaPorElColportor: pausada,
    );
  }
}
