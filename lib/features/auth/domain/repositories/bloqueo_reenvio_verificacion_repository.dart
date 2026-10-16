import '../entities/reenvios_guardados.dart';

/// Lo que el teléfono recuerda del reenvío del email de verificación (HU-AUTH-002, vista 12): los
/// candados que siguen a un rechazo por límite de intentos (12-A06; decisión de Cristian, 30/09,
/// front-colportores-mobile#221 y #239; seguimiento #249) y la espera de 60 s desde el último correo
/// que salió a cada dirección (decisión del orquestador, 08/10, #325). Ver [ReenviosGuardados].
///
/// Todo es **por dirección de correo** (otra dirección no queda bloqueada ni esperando) y se guarda
/// fuera de la sesión, así que **sobrevive a reiniciar la app**. Los correos van normalizados (sin
/// espacios alrededor y en minúsculas, como los guarda Supabase): el que normaliza es el caso de
/// uso, no el repositorio.
///
/// **Nada se queda más de su hora**: cada lectura y cada guardado podan lo vencido (y la clave se
/// borra cuando no queda nada), así ningún correo sigue en el teléfono pasado su vencimiento.
///
/// Nunca lanza: si el almacén falla, [leer] devuelve vacío y el resto queda en el log (el límite de
/// verdad lo aplica el servidor, que vuelve a rechazar). Las operaciones se ejecutan **en el orden
/// en que se piden**.
abstract interface class BloqueoReenvioVerificacionRepository {
  /// Lo que sigue vigente a [ahora] (ver [ReenviosGuardados.vigentesA]), sin lo vencido ni lo que
  /// pasa de su tope. Lo que podó o recortó queda así también en el teléfono: el recorte se aplica
  /// una vez, no en cada apertura (si no, un vencimiento muy lejano se correría una hora más cada
  /// vez que se abre la pantalla).
  Future<ReenviosGuardados> leer({required DateTime ahora});

  /// Guarda que el reenvío a [correo] queda bloqueado hasta [vence], reemplazando el anterior de esa
  /// dirección, y descarta de lo guardado lo que ya venció a [ahora]. **El mismo «ahora» que decide
  /// si algo sigue vigente.**
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora});

  /// Guarda que a [correo] no se le puede reenviar hasta [vence] (la espera de 60 s desde el último
  /// correo que salió), con la misma poda que [guardar].
  Future<void> guardarEspera(String correo, DateTime vence, {required DateTime ahora});

  /// Olvida el candado y la espera de [correo] (la cuenta entró: el reenvío ya no hace falta).
  Future<void> olvidar(String correo);

  /// Olvida todo (la persona cerró la sesión a propósito).
  Future<void> olvidarTodo();
}
