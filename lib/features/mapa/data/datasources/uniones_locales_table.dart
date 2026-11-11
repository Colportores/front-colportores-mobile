import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Los estados de una fila de [UnionesLocales], tal como van a la columna `estado`.
abstract final class EstadoUnionLocal {
  /// La unión está hecha en el teléfono y su trabajo «marcar como duplicado» no volvió rechazado.
  static const aplicada = 'APLICADA';

  /// El servidor rechazó el trabajo y la unión se deshizo en el teléfono: el par quedó separado
  /// (decisión de Cristian, 10/11, «Unión rech.»; #679).
  static const deshecha = 'DESHECHA';
}

/// Tabla `ubicacion_union_local` de la DB local cifrada: **qué movió** cada unión de duplicados hecha
/// en el teléfono (HU-UBI-006), para poder deshacerla si el servidor rechaza su trabajo «marcar como
/// duplicado» (`UB003`, `UB004`, `42501`, `CG001`; contrato-sync-engine §6.2).
///
/// Una fila por unión, con el `id` del trabajo en `sync_queue` ([trabajoId]): así se sabe cuál de las
/// uniones de un mismo par es la que volvió rechazada (el par se puede volver a unir después).
/// [movimientos] es un JSON con los `id` de lo que la unión cambió (`MovimientosDeUnion`).
///
/// **Solo local** (`SyncSpec.local`): no tiene tabla en el cloud y no sube. Viaja en el backup E2E con
/// la cola de sync: un trabajo restaurado que vuelve rechazado tiene que encontrar su unión. Las filas
/// no se borran: una deshecha es la que pone el aviso del par en «Posibles duplicados».
@DataClassName('UnionLocalFila')
class UnionesLocales extends Table {
  @override
  String get tableName => 'ubicacion_union_local';

  /// El `id` del trabajo «marcar como duplicado» en `sync_queue`.
  TextColumn get trabajoId => text()();

  /// La que se conservó (A).
  TextColumn get conservadaId => text()();

  /// La que se unió (B).
  TextColumn get duplicadaId => text()();

  IntColumn get unidaEn => integer().map(const FechaUtcConverter())();

  /// Lo que la unión movió, en JSON (`MovimientosDeUnion`).
  TextColumn get movimientos => text()();

  /// Ver [EstadoUnionLocal].
  TextColumn get estado => text().withDefault(const Constant(EstadoUnionLocal.aplicada))();

  /// El código con que el servidor rechazó el trabajo (`UB003`…), cuando se deshizo.
  TextColumn get codigoRechazo => text().nullable()();

  IntColumn get deshechaEn => integer().nullable().map(const FechaUtcConverter())();

  @override
  Set<Column<Object>> get primaryKey => {trabajoId};

  @override
  List<String> get customConstraints => const ["CHECK (estado IN ('APLICADA', 'DESHECHA'))"];
}
