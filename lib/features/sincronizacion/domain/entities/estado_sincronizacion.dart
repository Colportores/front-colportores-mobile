import 'package:equatable/equatable.dart';

/// Cómo está la sincronización en este teléfono (HU-SYNC-007, vista 25): lo que cuenta la cola del
/// motor y lo que el motor sabe de sus últimos intercambios con el servidor.
final class EstadoSincronizacion extends Equatable {
  const EstadoSincronizacion({
    this.pendientes = 0,
    this.invalidas = 0,
    this.ultimoEnvio,
    this.ultimaActualizacion,
    this.ultimoRespaldo,
    this.actualizacionEnEspera = false,
    this.sesionSinRenovar = false,
  });

  /// Operaciones que esperan para subir: las que todavía no salieron, las que van en camino y las
  /// que esperan que se resuelva un conflicto (vista 10). Ninguna se pierde: salen solas cuando hay
  /// conexión.
  final int pendientes;

  /// Operaciones que el servidor rechazó por su contenido. Nunca se reintentan solas: las reintenta
  /// la persona desde «Ver detalle» o «Reintentar» (HU-SYNC-007).
  final int invalidas;

  /// Cuándo confirmó el servidor la última escritura de la persona; `null` si el teléfono no lo sabe
  /// (todavía no subió nada que el motor recuerde).
  final DateTime? ultimoEnvio;

  /// Cuándo bajaron por última vez los cambios del coordinador; `null` si el teléfono no lo sabe.
  final DateTime? ultimaActualizacion;

  /// Cuándo terminó el último respaldo; `null` si el teléfono no lo sabe.
  final DateTime? ultimoRespaldo;

  /// El último ciclo dejó la bajada de cambios esperando al Wi-Fi por el modo ahorro (HU-SYNC-008,
  /// `data_saver_on_mobile`).
  final bool actualizacionEnEspera;

  /// El servidor viene contestando que la sesión no vale y el motor no puede subir nada: hace falta
  /// volver a iniciar sesión (HU-AUTH-007).
  final bool sesionSinRenovar;

  /// Todo lo que hay para reenviar o corregir: la cantidad que importa para no cerrar sesión ni
  /// borrar datos sin avisar.
  int get sinEnviar => pendientes + invalidas;

  @override
  List<Object?> get props => [
    pendientes,
    invalidas,
    ultimoEnvio,
    ultimaActualizacion,
    ultimoRespaldo,
    actualizacionEnEspera,
    sesionSinRenovar,
  ];
}

/// Qué hacía una operación que el servidor rechazó.
enum TipoOperacion { alta, cambio, baja }

/// Una operación que el servidor rechazó, para «Ver detalle» (HU-SYNC-007, 25-07): de qué tabla, qué
/// tipo, cuándo y por qué, **sin datos personales** (ni la fila ni los valores que el servidor cita).
final class OperacionFallida extends Equatable {
  const OperacionFallida({
    required this.id,
    required this.tabla,
    required this.tipo,
    required this.fecha,
    required this.codigo,
    required this.error,
  });

  /// El id con el que se reencola.
  final String id;

  /// El nombre remoto de la tabla (`venta`, `cobranza`, `visita`…).
  final String tabla;
  final TipoOperacion tipo;

  /// Cuándo se hizo la operación en el teléfono (UTC).
  final DateTime fecha;

  /// El código con el que el servidor la rechazó.
  final String codigo;

  /// El mensaje del servidor, ya sin datos personales. Puede estar vacío.
  final String error;

  @override
  List<Object?> get props => [id, tabla, tipo, fecha, codigo, error];
}

/// Por qué «Actualizar ahora» no pudo completarse.
enum MotivoFallaActualizacion {
  /// El servidor no contestó o contestó con un error pasajero: lo pendiente sigue guardado.
  servidor,

  /// La sesión no se pudo renovar (el servidor contesta `401`).
  sesion,
}

/// Cómo terminó «Actualizar ahora».
sealed class ResultadoActualizacion extends Equatable {
  const ResultadoActualizacion();
}

/// El ciclo terminó: subió lo pendiente y bajó lo del coordinador.
final class ActualizacionCompleta extends ResultadoActualizacion {
  const ActualizacionCompleta({
    this.enviadas = 0,
    this.recibidas = 0,
    this.rechazadas = 0,
    this.conflictos = 0,
  });

  /// Operaciones que el servidor aceptó.
  final int enviadas;

  /// Cambios que bajaron.
  final int recibidas;

  /// Operaciones que el servidor rechazó en este ciclo (quedan en la lista de «no se pudieron
  /// enviar»).
  final int rechazadas;

  /// Operaciones que esperan que la persona resuelva un conflicto (vista 10).
  final int conflictos;

  @override
  List<Object?> get props => [enviadas, recibidas, rechazadas, conflictos];
}

/// El ciclo se cortó: lo pendiente volvió a la cola y sube en el próximo intento.
final class ActualizacionFallida extends ResultadoActualizacion {
  const ActualizacionFallida(this.motivo, {this.enviadas = 0});

  final MotivoFallaActualizacion motivo;

  /// Lo que alcanzó a subir antes de cortarse.
  final int enviadas;

  @override
  List<Object?> get props => [motivo, enviadas];
}
