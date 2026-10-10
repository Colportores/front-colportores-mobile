/// El trabajo de sync «marcar como duplicado» (HU-UBI-006): le pide al servidor que pase a la
/// ubicación conservada los espacios, las personas y las visitas de la duplicada y la dé de baja
/// (RPC `marcar_como_duplicado`, backend-supabase 0026).
///
/// **No es un upsert de una fila**, así que no entra por `EncoladorSync`: su forma en la cola es del
/// motor de sync (#178, backend-supabase#70) y no se inventa acá. El puerto lo llama la unión local
/// **dentro de su transacción**: si falla, la unión se revierte entera. Hasta que el motor exista,
/// `EncoladorMarcarDuplicadoSinMotor` falla a propósito.
abstract interface class EncoladorMarcarDuplicado {
  /// Encola «la ubicación [duplicadaId] es un duplicado de [conservadaId]».
  Future<void> encolarMarcarDuplicado({required String duplicadaId, required String conservadaId});
}
