import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import 'pares_duplicados_local_data_source.dart';
import 'pares_duplicados_table.dart';
import 'uniones_locales_table.dart';

part 'pares_duplicados_local_data_source_drift.g.dart';

/// [ParesDuplicadosLocalDataSource] sobre la tabla `ubicacion_par_decidido` ([ParesDecididos]) y,
/// para el aviso de una unión rechazada, `ubicacion_union_local` ([UnionesLocales]). No encola nada:
/// las dos son solo locales.
@DriftAccessor(tables: [ParesDecididos, UnionesLocales])
final class ParesDuplicadosLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$ParesDuplicadosLocalDataSourceDriftMixin
    implements ParesDuplicadosLocalDataSource {
  ParesDuplicadosLocalDataSourceDrift(super.attachedDatabase);

  @override
  Future<Map<String, ParDecidido>> decididos() async => _aMapa(await select(paresDecididos).get());

  @override
  Stream<Map<String, ParDecidido>> observarDecididos() =>
      select(paresDecididos).watch().map(_aMapa);

  /// La última unión de cada par manda: si se volvió a unir después del rechazo, ya no hay aviso.
  @override
  Stream<Map<String, String>> observarUnionesRechazadas() =>
      (select(unionesLocales)
            ..orderBy([(u) => OrderingTerm.asc(u.unidaEn), (u) => OrderingTerm.asc(u.trabajoId)]))
          .watch()
          .map((filas) {
            final ultima = <String, UnionLocalFila>{
              for (final f in filas) ParDuplicado.claveDe(f.conservadaId, f.duplicadaId): f,
            };
            return {
              for (final MapEntry(key: clave, value: f) in ultima.entries)
                if (f.estado == EstadoUnionLocal.deshecha) clave: f.codigoRechazo ?? '',
            };
          });

  static Map<String, ParDecidido> _aMapa(List<ParDecididoFila> filas) => {
    for (final fila in filas)
      ParDuplicado.claveDe(fila.ubicacionAId, fila.ubicacionBId): ParDecidido(
        decision: decisionDe(fila.decision),
        decididoEn: fila.decididoEn,
      ),
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

  /// La decisión que guarda el valor [codigo] de la columna `decision` (el `CHECK` de [ParesDecididos]
  /// no admite otro).
  static DecisionParDuplicado decisionDe(String codigo) => switch (codigo) {
    'CONSERVAR_AMBOS' => DecisionParDuplicado.conservarAmbos,
    _ => DecisionParDuplicado.ignorar,
  };

  /// El valor de la columna `decision` (ver el `CHECK` de [ParesDecididos]).
  static String codigoDe(DecisionParDuplicado decision) => switch (decision) {
    DecisionParDuplicado.conservarAmbos => 'CONSERVAR_AMBOS',
    DecisionParDuplicado.ignorar => 'IGNORAR',
  };
}
