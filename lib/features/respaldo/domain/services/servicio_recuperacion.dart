/// Recuperar los datos en un teléfono sin datos (HU-SYNC-006, contrato §7, vista 34).
///
/// Este servicio es la lógica del asistente de recuperación: lo que la pantalla (#175) muestra y
/// llama. Ninguna de las dos funciones lanza: todo lo que puede pasar sale como un resultado.
abstract interface class ServicioRecuperacion {
  /// Busca en el Drive conectado el respaldo que se puede traer a este teléfono (pasos 1, 2 y 9 de
  /// la vista 34). No baja nada: mira los metadatos.
  Future<BusquedaRespaldo> buscar();

  /// Restaura [respaldo] abriéndolo con [password] (pasos 3 a 8 de la vista 34): baja y verifica la
  /// cadena, la arma aparte de la DB en uso y recién entonces la pasa; después reenvía lo que había
  /// en la cola y trae de Supabase lo que subió después del respaldo.
  ///
  /// [alAvanzar] recibe el paso en que va. [cancelar] corta la descarga sin tocar la DB; una vez
  /// que empezó a aplicarse, ya no se puede cancelar ([ProgresoRecuperacion.sePuedeCancelar]).
  Future<ResultadoRecuperacion> recuperar({
    required RespaldoEnDrive respaldo,
    required String password,
    void Function(ProgresoRecuperacion progreso)? alAvanzar,
    CancelacionRecuperacion? cancelar,
  });
}

/// Un respaldo de Drive que se puede traer a este teléfono: la tarjeta «Respaldo del 22/10 a las
/// 03:10 · 15 partes · 38 MB».
final class RespaldoEnDrive {
  const RespaldoEnDrive({
    required this.llave,
    required this.fecha,
    required this.partes,
    required this.bytes,
    required this.completo,
    required this.tieneLlave,
  });

  /// De qué llave es (el identificador del motor; no es la clave). Es lo que `recuperar` usa para
  /// elegir la cadena.
  final String? llave;

  /// De cuándo son los datos: la parte más nueva que se puede aplicar.
  final DateTime fecha;

  /// Cuántas partes tiene (la base y los incrementales).
  final int partes;

  /// Cuánto pesa, cifrado. La confirmación previa dice «Vamos a restaurar X MB».
  final int bytes;

  /// La cadena llega entera. Si no, el restore va a ser parcial y la pantalla puede avisarlo desde
  /// antes.
  final bool completo;

  /// Drive tiene la clave envuelta que abre este respaldo. Sin ella no se puede abrir con ninguna
  /// contraseña ([ResultadoRecuperacion] `SinLlaveParaElRespaldo`).
  final bool tieneLlave;
}

/// Qué encontró la búsqueda.
sealed class BusquedaRespaldo {
  const BusquedaRespaldo();
}

/// Hay un respaldo para traer. Paso 1 de la vista 34.
final class RespaldoEncontrado extends BusquedaRespaldo {
  const RespaldoEncontrado(this.respaldo);

  final RespaldoEnDrive respaldo;
}

/// No hay respaldo de otro teléfono en este Drive (vista 34, paso 9). Lo que hizo este mismo
/// teléfono no cuenta: es su copia, no algo para traer.
final class SinRespaldoEnDrive extends BusquedaRespaldo {
  const SinRespaldoEnDrive();
}

/// Hay más de un respaldo que se podría abrir (el de cada teléfono que la persona tuvo). Qué se
/// ofrece en ese caso **no está decidido**: la restauración no elige por la persona y la pantalla
/// queda a la espera de la decisión.
final class VariosRespaldosEnDrive extends BusquedaRespaldo {
  const VariosRespaldosEnDrive(this.respaldos);

  final List<RespaldoEnDrive> respaldos;
}

/// No hay un permiso de Drive vigente: la persona tiene que conectarlo (vista 34, paso 2).
final class DriveSinPermiso extends BusquedaRespaldo {
  const DriveSinPermiso();
}

/// Sin conexión (vista 34, paso 10).
final class BusquedaSinConexion extends BusquedaRespaldo {
  const BusquedaSinConexion();
}

/// Falló por otra razón; se puede reintentar.
final class BusquedaFallida extends BusquedaRespaldo {
  const BusquedaFallida();
}

/// En qué paso va la recuperación (vista 34, pasos 5 y 6).
final class ProgresoRecuperacion {
  const ProgresoRecuperacion(
    this.paso, {
    this.hechas = 0,
    this.total = 0,
    this.esperandoConexion = false,
  });

  final PasoRecuperacion paso;

  /// Partes bajadas de [total]: el «12/15 partes».
  final int hechas;
  final int total;

  /// Se cortó la conexión: sigue solo, desde la parte [hechas], cuando vuelva (vista 34, paso 6).
  final bool esperandoConexion;

  /// Hasta que termina la descarga se puede cancelar y todo queda como estaba.
  bool get sePuedeCancelar => paso == PasoRecuperacion.buscando || paso == PasoRecuperacion.bajando;
}

enum PasoRecuperacion {
  /// Mirando qué hay en Drive.
  buscando,

  /// Bajando y verificando las partes.
  bajando,

  /// Armando la copia y pasándola a este teléfono.
  aplicando,

  /// Reenviando lo que estaba en la cola del respaldo.
  reenviando,

  /// Trayendo de Supabase lo que subió después del respaldo.
  reconciliando,

  /// Terminó.
  listo,
}

/// Para cancelar una recuperación en curso.
final class CancelacionRecuperacion {
  bool _cancelada = false;

  bool get cancelada => _cancelada;

  void cancelar() => _cancelada = true;
}

/// Qué se recuperó (vista 34, paso 8, y el aviso del paso 7).
final class InformeRecuperacion {
  const InformeRecuperacion({
    required this.fechaDelRespaldo,
    required this.parcial,
    required this.partesRestauradas,
    required this.partesTotales,
    required this.trabajosReenviados,
    required this.filasTraidas,
    required this.ahora,
  });

  /// De cuándo son los datos restaurados: hasta acá llega la copia. Si es [parcial], es la última
  /// parte buena.
  final DateTime fechaDelRespaldo;

  /// Una parte dañada cortó la cadena: lo posterior a [fechaDelRespaldo] no se restauró (vista 34,
  /// paso 7).
  final bool parcial;

  final int partesRestauradas;
  final int partesTotales;

  /// Ventas, cobros y demás que estaban esperando subir en el respaldo y se reenviaron.
  final int trabajosReenviados;

  /// Entidad → filas que volvieron de Supabase (lo que subió después del respaldo).
  final Map<String, int> filasTraidas;

  /// El momento de la recuperación.
  final DateTime ahora;

  /// La ventana que no se pudo recuperar: lo creado entre el respaldo y la pérdida que tampoco
  /// llegó a subir. Existe siempre que hubo respaldo (contrato §7, «Lo que no se puede recuperar»).
  Duration get ventanaPerdida => ahora.difference(fechaDelRespaldo);

  int get totalDeFilasTraidas => filasTraidas.values.fold(0, (n, f) => n + f);
}

/// Cómo terminó `recuperar`.
sealed class ResultadoRecuperacion {
  const ResultadoRecuperacion();
}

/// Se restauró todo, o se restauró hasta una parte dañada ([InformeRecuperacion.parcial]).
final class RecuperacionHecha extends ResultadoRecuperacion {
  const RecuperacionHecha(this.informe);

  final InformeRecuperacion informe;
}

/// La contraseña no abre la copia (vista 34, paso 4). No se tocó nada.
final class ContrasenaNoAbreElRespaldo extends ResultadoRecuperacion {
  const ContrasenaNoAbreElRespaldo();
}

/// Drive no tiene la clave envuelta de este respaldo: sin ella no se puede abrir con ninguna
/// contraseña. No se tocó nada.
final class SinLlaveParaElRespaldo extends ResultadoRecuperacion {
  const SinLlaveParaElRespaldo();
}

/// El respaldo es de una versión de la app más nueva que esta: «Tus datos son de una versión más
/// nueva de la app. Actualizala para seguir usando tus datos.» No se tocó nada.
final class RespaldoDeVersionMasNueva extends ResultadoRecuperacion {
  const RespaldoDeVersionMasNueva({required this.esquemaDelRespaldo, required this.esquemaDeLaApp});

  final int esquemaDelRespaldo;
  final int esquemaDeLaApp;
}

/// La base del respaldo está dañada o no se puede leer: no hay nada que restaurar. No se tocó nada.
final class RespaldoIlegible extends ResultadoRecuperacion {
  const RespaldoIlegible();
}

/// Se cortó la conexión y no volvió a tiempo (vista 34, paso 6). No se tocó nada; lo ya bajado
/// queda para que «Reintentar» siga desde la parte donde quedó.
final class RecuperacionSinConexion extends ResultadoRecuperacion {
  const RecuperacionSinConexion({required this.hechas, required this.total});

  final int hechas;
  final int total;
}

/// La persona canceló. La DB quedó como estaba y no queda nada a medias.
final class RecuperacionCancelada extends ResultadoRecuperacion {
  const RecuperacionCancelada();
}

/// Drive dejó de dar el permiso en medio de la recuperación.
final class RecuperacionSinPermiso extends ResultadoRecuperacion {
  const RecuperacionSinPermiso();
}

/// Falló por otra razón. La DB en uso quedó como estaba.
final class RecuperacionFallida extends ResultadoRecuperacion {
  const RecuperacionFallida();
}
