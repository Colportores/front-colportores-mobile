import 'package:colportores_mobile/features/notificaciones/domain/repositories/datos_locales_de_push_repository.dart';

/// [DatosLocalesDePushRepository] en memoria: lo que el teléfono sabe para el texto de una push.
final class DatosLocalesDePushEnMemoria implements DatosLocalesDePushRepository {
  final campanias = <String, String>{};
  final zonas = <String, String>{};
  int visitasDeManana = 0;

  /// Si es `true`, toda lectura lanza (la base no se deja leer).
  bool falla = false;
  DateTime? ahoraConsultado;

  @override
  Future<String?> nombreDeCampania(String campaniaId) async {
    if (falla) throw StateError('base cerrada');
    return campanias[campaniaId];
  }

  @override
  Future<String?> nombreDeZona(String zonaId) async {
    if (falla) throw StateError('base cerrada');
    return zonas[zonaId];
  }

  @override
  Future<int> visitasProgramadasParaManana(DateTime ahora) async {
    if (falla) throw StateError('base cerrada');
    ahoraConsultado = ahora;
    return visitasDeManana;
  }
}
