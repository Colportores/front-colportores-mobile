import 'dart:async';

import '../../../domain/entities/asignacion_campania.dart';
import '../asignacion_campania_data_source.dart';

/// [AsignacionCampaniaDataSource] en memoria, para tests y la demo sin backend. **No es código de
/// producción.**
final class AsignacionCampaniaEnMemoria implements AsignacionCampaniaDataSource {
  AsignacionCampaniaEnMemoria({
    this.asignacion = const AsignacionCampania(
      campania: 'Campaña Primavera 2026',
      zona: 'Centro',
      ciudad: 'Montevideo',
    ),
  });

  /// Lo que responde el «backend»; `null` si todavía no se sabe.
  AsignacionCampania? asignacion;

  /// Si no es `null`, [consultar] lo lanza.
  Object? falla;

  /// Si está, [consultar] espera a que el test la complete.
  Completer<void>? demora;

  int consultas = 0;

  @override
  Future<AsignacionCampania?> consultar() async {
    consultas++;
    await demora?.future;
    if (falla case final falla?) throw falla;
    return asignacion;
  }
}
