import 'package:drift/drift.dart';

import '../../../../core/database/fecha_utc_converter.dart';

/// Tabla `deuda_casa_cache` de la DB local cifrada (HU-CTA-002, vista 33B): la última respuesta del
/// RPC `mi_deuda_con_la_casa_editora` con la hora en que llegó, para ver la deuda sin conexión
/// (decisión de Cristian, 03/11, «Leer deuda»).
///
/// **local-only**: no tiene tabla en el cloud y no entra al sync (`SyncSpec.local`) ni al backup E2E
/// (se vuelve a bajar del servidor). Una fila por colportor: cada lectura nueva pisa la anterior, así
/// que la cuenta se hace siempre en el servidor y acá solo se guarda lo último que dijo. [respuesta]
/// es el JSON del RPC tal cual (montos y nombres de productos, nunca clientes ni cobros) y [leidaEn]
/// la hora del teléfono en que llegó.
@DataClassName('DeudaCasaCacheFila')
class DeudaCasaCaches extends Table {
  @override
  String get tableName => 'deuda_casa_cache';

  /// UUID del colportor de la sesión.
  TextColumn get colportorId => text()();

  /// El JSON que contestó el RPC.
  TextColumn get respuesta => text()();

  /// Cuándo llegó (hora del teléfono, UTC).
  IntColumn get leidaEn => integer().map(const FechaUtcConverter())();

  @override
  Set<Column<Object>> get primaryKey => {colportorId};
}
