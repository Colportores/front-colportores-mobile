import 'package:equatable/equatable.dart';

import '../../../agenda/domain/entities/anticipacion_recordatorio.dart';

/// Lo que la colportora eligió de los recordatorios de su agenda (HU-NOT-004, vista 24 grupo B):
/// si se programan y con cuántos minutos de anticipación (`usuario.notif_anticipacion_minutos`, de 5 a
/// 120). En el S8 se guardan en el teléfono.
final class PreferenciasRecordatorios extends Equatable {
  const PreferenciasRecordatorios({
    this.activados = true,
    this.anticipacionMinutos = AnticipacionRecordatorio.porDefecto,
  });

  /// «Recordatorios de agenda». Apagado, no se programa ninguno y los ya programados se cancelan.
  final bool activados;

  /// «Anticipación»: minutos antes de la visita. Siempre dentro de `5..120` (quien guarda o lee lo
  /// acota con `AnticipacionRecordatorio.acotar`).
  final int anticipacionMinutos;

  PreferenciasRecordatorios copyWith({bool? activados, int? anticipacionMinutos}) =>
      PreferenciasRecordatorios(
        activados: activados ?? this.activados,
        anticipacionMinutos: anticipacionMinutos ?? this.anticipacionMinutos,
      );

  @override
  List<Object?> get props => [activados, anticipacionMinutos];
}
