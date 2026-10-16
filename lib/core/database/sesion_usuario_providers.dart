import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/datasources/sesion_usuario_local_data_source.dart';
import 'database_providers.dart';

/// La copia local del nombre del usuario (#243), o `null` mientras la DB no está abierta. Observa
/// `dbLocalProvider`: se reconstruye sola al abrirse o cerrarse la DB.
final sesionUsuarioLocalDataSourceProvider = Provider<SesionUsuarioLocalDataSource?>((ref) {
  final db = ref.watch(dbLocalProvider);
  return db == null ? null : SesionUsuarioLocalDataSource(db);
});
