import 'dart:async';

import '../motor_de_avisos.dart';

/// Un aviso programado en [MotorDeAvisosEnMemoria].
final class AvisoProgramado {
  const AvisoProgramado({
    required this.id,
    required this.titulo,
    required this.cuerpo,
    required this.instante,
    required this.payload,
  });

  final int id;
  final String titulo;
  final String cuerpo;
  final DateTime instante;
  final String payload;
}

/// [MotorDeAvisos] en memoria.
///
/// **No es código de producción.** Lo usan los tests de `RecordatoriosLocales`: guarda los avisos
/// por id (programar con el mismo id reemplaza, como el plugin) y permite simular fallas y demoras.
final class MotorDeAvisosEnMemoria implements MotorDeAvisos {
  /// Los avisos pendientes, por id.
  final Map<int, AvisoProgramado> pendientes = {};

  /// Cada llamada en el orden en que llegó: `programar:<id>`, `cancelar:<id>`.
  final List<String> llamadas = [];

  /// Si es `true`, [iniciar] lanza.
  bool fallaAlIniciar = false;

  /// Si es `true`, [programar] lanza.
  bool fallaAlProgramar = false;

  /// Si es `true`, [cancelar] lanza.
  bool fallaAlCancelar = false;

  /// Si no es `null`, [programar] espera a que se complete (el sistema todavía no contestó).
  Completer<void>? programacionDemorada;

  /// Lo que devuelve [payloadQueAbrioLaApp].
  String? payloadDeLanzamiento;

  /// El oyente de toques que registró [iniciar].
  void Function(String? payload)? alTocar;

  /// Simula que la persona toca un aviso con la app viva.
  void tocar(String? payload) => alTocar?.call(payload);

  @override
  Future<void> iniciar({required void Function(String? payload) alTocar}) async {
    if (fallaAlIniciar) throw StateError('el plugin no arrancó');
    this.alTocar = alTocar;
  }

  @override
  Future<String?> payloadQueAbrioLaApp() async => payloadDeLanzamiento;

  @override
  Future<void> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime instante,
    required String payload,
  }) async {
    llamadas.add('programar:$id');
    final demora = programacionDemorada;
    if (demora != null) await demora.future;
    if (fallaAlProgramar) throw StateError('el sistema no aceptó el aviso');
    pendientes[id] = AvisoProgramado(
      id: id,
      titulo: titulo,
      cuerpo: cuerpo,
      instante: instante,
      payload: payload,
    );
  }

  @override
  Future<void> cancelar(int id) async {
    llamadas.add('cancelar:$id');
    if (fallaAlCancelar) throw StateError('el sistema no canceló el aviso');
    pendientes.remove(id);
  }
}
