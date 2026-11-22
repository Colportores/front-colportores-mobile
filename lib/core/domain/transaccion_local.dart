/// Una escritura de varios repositorios que entra **toda o nada** en la DB local (contrato-sync-engine
/// §3): lo que escribe [correr] (filas y encolados del sync) se revierte entero si el cuerpo lanza.
///
/// Es el puerto con el que un caso de uso de dominio junta dos registros en un solo paso (por ejemplo,
/// el ticket del banco y su depósito, decisión «Paso ticket») sin conocer Drift. Las transacciones de
/// cada repositorio que corren adentro quedan anidadas en esta.
abstract interface class TransaccionLocal {
  /// Corre [cuerpo] en una transacción y devuelve lo que devuelve. Si [cuerpo] lanza, no queda nada de
  /// lo que escribió y la excepción sigue de largo.
  Future<T> correr<T>(Future<T> Function() cuerpo);
}
