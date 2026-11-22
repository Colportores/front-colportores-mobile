// Las agendas pendientes de recordar, en memoria, para probar la reprogramación (HU-NOT-004).
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/preferencias_recordatorios_repository.dart';

final class AgendasParaRecordarEnMemoria implements AgendasParaRecordar {
  AgendasParaRecordarEnMemoria([List<RecordatorioDeVisita> agendas = const []])
    : agendas = [...agendas];

  /// Lo que devuelve [pendientes] (ya filtrado: la consulta real filtra en la DB).
  final List<RecordatorioDeVisita> agendas;

  /// Con `true`, [pendientes] lanza.
  bool falla = false;

  /// Si no es `null`, [pendientes] espera a que se complete.
  Completer<void>? demora;

  /// Cuántas veces se pidieron.
  int consultas = 0;

  /// Lo último que se pidió.
  String? ultimoColportor;
  DateTime? ultimoDesde;

  @override
  Future<List<RecordatorioDeVisita>> pendientes({
    required String colportorId,
    required DateTime desde,
  }) async {
    consultas++;
    ultimoColportor = colportorId;
    ultimoDesde = desde;
    await demora?.future;
    if (falla) throw StateError('no se pudieron leer las agendas');
    return [...agendas];
  }
}
