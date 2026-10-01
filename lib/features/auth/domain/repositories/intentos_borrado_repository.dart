import '../entities/estado_intentos_borrado.dart';

/// Dónde se guardan los intentos de contraseña del borrado de datos locales, para que cerrar la
/// app no reinicie la espera (HU-AUTH-010, vista 19). Nunca lanza: si no puede leer, devuelve el
/// estado limpio (el borrado igual exige la contraseña) y si no puede escribir, lo ignora.
abstract interface class IntentosBorradoRepository {
  Future<EstadoIntentosBorrado> leer();

  Future<void> guardar(EstadoIntentosBorrado estado);

  Future<void> limpiar();
}
