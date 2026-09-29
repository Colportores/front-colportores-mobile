import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import 'pares_duplicados_local_data_source.dart';
import 'pares_duplicados_table.dart';

part 'pares_duplicados_local_data_source_drift.g.dart';

/// [ParesDuplicadosLocalDataSource] sobre la tabla `ubicacion_par_decidido` ([ParesDecididos]).
/// No encola nada: la tabla es solo local.
@DriftAccessor(tables: [ParesDecididos])
final class ParesDuplicadosLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$ParesDuplicadosLocalDataSourceDriftMixin
    implements ParesDuplicadosLocalDataSource {
  ParesDuplicadosLocalDataSourceDrift(super.attachedDatabase);

  @override
  Future<Map<String, DateTime>> decididos() async => {
    for (final fila in await select(paresDecididos).get())
      ParDuplicado.claveDe(fila.ubicacionAId, fila.ubicacionBId): fila.decididoEn,
  };

  @override
  Future<void> decidir(
    String ubicacionId1,
    String ubicacionId2,
    DecisionParDuplicado decision, {
    required DateTime decididoEn,
  }) async {
    final primeroEl1 = ubicacionId1.compareTo(ubicacionId2) <= 0;
    await into(paresDecididos).insertOnConflictUpdate(
      ParesDecididosCompanion.insert(
        ubicacionAId: primeroEl1 ? ubicacionId1 : ubicacionId2,
        ubicacionBId: primeroEl1 ? ubicacionId2 : ubicacionId1,
        decision: codigoDe(decision),
        decididoEn: decididoEn,
      ),
    );
  }

  /// El valor de la columna `decision` (ver el `CHECK` de [ParesDecididos]).
  static String codigoDe(DecisionParDuplicado decision) => switch (decision) {
    DecisionParDuplicado.conservarAmbos => 'CONSERVAR_AMBOS',
    DecisionParDuplicado.ignorar => 'IGNORAR',
  };
}
