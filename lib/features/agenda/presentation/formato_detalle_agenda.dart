import '../../notificaciones/domain/entities/preferencias_recordatorios.dart';
import '../domain/entities/anticipacion_recordatorio.dart';
import 'formato_agendar_visita.dart';
import 'textos_detalle_agenda.dart';

/// Cómo se escriben el día, la hora y el recordatorio en el detalle de una agenda (vista 23, 23C·01).
/// Siempre en la hora del teléfono: es-UY, `DD/MM`, 24 horas.
abstract final class FormatoDetalleAgenda {
  /// «Jue 24/10 · 14:30».
  static String cuando(DateTime fecha) =>
      '${FormatoAgendarVisita.diaCortoYMes(fecha)} · ${FormatoAgendarVisita.hora(fecha)}';

  /// Cuándo suena el aviso de una visita: la visita menos la anticipación elegida.
  static DateTime horaDelAviso(DateTime visita, int anticipacionMinutos) =>
      visita.subtract(Duration(minutes: AnticipacionRecordatorio.acotar(anticipacionMinutos)));

  /// El aviso como se dice dentro de una frase: «10:00» si cae el mismo día de la visita, y con el día
  /// («lun 12/10 a las 23:40» queda a cargo de quien arma la frase) si no.
  static ({String? dia, String hora}) avisoEnFrase(DateTime aviso, DateTime visita) {
    final hora = FormatoAgendarVisita.hora(aviso);
    if (FormatoAgendarVisita.mismoDia(aviso, visita)) return (dia: null, hora: hora);
    return (dia: FormatoAgendarVisita.diaCortoYMes(aviso).toLowerCase(), hora: hora);
  }

  /// El renglón «Recordatorio» del detalle de una agenda programada: la hora del aviso («14:00»; con el
  /// día si cae otro día que la visita), «Apagado» si los recordatorios están apagados en las
  /// preferencias, o «Ya pasó» si la hora del aviso ya quedó atrás. [preferencias] `null`: los valores
  /// de fábrica.
  static String recordatorio({
    required DateTime visita,
    required DateTime ahora,
    PreferenciasRecordatorios? preferencias,
  }) {
    if (preferencias != null && !preferencias.activados) {
      return TextosDetalleAgenda.recordatorioApagado;
    }
    final aviso = horaDelAviso(
      visita,
      preferencias?.anticipacionMinutos ?? AnticipacionRecordatorio.porDefecto,
    );
    if (!aviso.isAfter(ahora)) return TextosDetalleAgenda.recordatorioYaPaso;
    final hora = FormatoAgendarVisita.hora(aviso);
    if (FormatoAgendarVisita.mismoDia(aviso, visita)) return hora;
    return '${FormatoAgendarVisita.diaCortoYMes(aviso)} · $hora';
  }
}
