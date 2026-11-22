import '../../../../core/database/app_database.dart';

/// Lo guardado: el JSON del RPC y la hora en que llegó.
typedef DeudaGuardada = ({String respuesta, DateTime leidaEn});

/// Dónde se guarda la última respuesta de la deuda con la casa editora.
abstract interface class DeudaConLaCasaCacheDataSource {
  /// Lo último que llegó para [colportorId], o `null` si nunca llegó nada.
  Future<DeudaGuardada?> leer(String colportorId);

  /// Pisa lo guardado de [colportorId] con [respuesta], que llegó a las [leidaEn].
  Future<void> guardar(String colportorId, String respuesta, DateTime leidaEn);
}

/// [DeudaConLaCasaCacheDataSource] sobre la tabla `deuda_casa_cache` de la DB cifrada.
final class DeudaConLaCasaCacheDrift implements DeudaConLaCasaCacheDataSource {
  DeudaConLaCasaCacheDrift(this._db);

  final AppDatabase _db;

  @override
  Future<DeudaGuardada?> leer(String colportorId) async {
    final fila = await (_db.select(
      _db.deudaCasaCaches,
    )..where((c) => c.colportorId.equals(colportorId))).getSingleOrNull();
    if (fila == null) return null;
    return (respuesta: fila.respuesta, leidaEn: fila.leidaEn);
  }

  @override
  Future<void> guardar(String colportorId, String respuesta, DateTime leidaEn) => _db
      .into(_db.deudaCasaCaches)
      .insertOnConflictUpdate(
        DeudaCasaCachesCompanion.insert(
          colportorId: colportorId,
          respuesta: respuesta,
          leidaEn: leidaEn,
        ),
      );
}

/// Sin DB abierta no se guarda nada: la deuda se pide y se muestra, pero no queda para después.
final class DeudaConLaCasaSinCache implements DeudaConLaCasaCacheDataSource {
  const DeudaConLaCasaSinCache();

  @override
  Future<DeudaGuardada?> leer(String colportorId) async => null;

  @override
  Future<void> guardar(String colportorId, String respuesta, DateTime leidaEn) async {}
}
