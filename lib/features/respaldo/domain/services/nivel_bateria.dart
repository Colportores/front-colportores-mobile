/// El nivel de la batería del teléfono, para decidir si corre un backup automático (HU-SYNC-005,
/// R-SY10: batería ≥ 30 %).
abstract interface class NivelBateria {
  /// El porcentaje (0 a 100) o `null` si el sistema no lo informa (otra plataforma, un fallo del
  /// canal). Nunca lanza: no saber el nivel no puede frenar el respaldo.
  Future<int?> porcentaje();
}

/// La batería mínima para un backup automático (HU-JOR-002, R-SY10).
const int bateriaMinimaParaRespaldar = 30;
