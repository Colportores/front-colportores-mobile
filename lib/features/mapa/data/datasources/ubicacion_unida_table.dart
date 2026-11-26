import 'package:drift/drift.dart';

/// Tabla `ubicacion_unida` de la DB local cifrada: la **marca de unión** que el servidor manda con
/// cada ubicación (HU-UBI-006, «Marca unión» y «Marca local»: «Aparte en el teléfono», contrato del
/// motor §2.3). Una fila por ubicación que el servidor tiene unida a otra: [ubicacionId] es la B (la
/// que quedó de baja) y [unidaAId] es la A (a la que se unió).
///
/// **De solo bajada**: la llena el pull de `ubicacion` (el campo `unida_a_id` de cada fila, que no es
/// una columna de `ubicacion`) y **nunca sube**; la entidad `ubicacion` sigue sin columnas que no
/// suben. De acá salen la leyenda «Unida a otra ubicación» de la Lista y la guarda de «Reactivar».
/// Una fila del servidor con `unida_a_id` nulo borra la marca.
@DataClassName('UbicacionUnidaFila')
class UbicacionesUnidas extends Table {
  @override
  String get tableName => 'ubicacion_unida';

  TextColumn get ubicacionId => text()();

  TextColumn get unidaAId => text()();

  @override
  Set<Column<Object>> get primaryKey => {ubicacionId};
}
