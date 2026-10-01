import '../entities/estado_intentos_borrado.dart';

/// Dónde se guardan los intentos de contraseña del borrado de datos locales, para que cerrar la
/// app no reinicie la espera (HU-AUTH-010, vista 19). Nunca lanza y **falla cerrado**: si no puede
/// leer ni hay otro dato de esta corrida, devuelve [EstadoIntentosBorrado.ilegible] (no "limpio"); si
/// no puede escribir, el intento igual queda contado en memoria para el resto de la corrida.
abstract interface class IntentosBorradoRepository {
  Future<EstadoIntentosBorrado> leer();

  Future<void> guardar(EstadoIntentosBorrado estado);

  Future<void> limpiar();
}
