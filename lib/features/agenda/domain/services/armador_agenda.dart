import '../entities/filtros_agenda.dart';
import '../entities/item_agenda.dart';
import '../entities/vista_agenda.dart';

/// La ventana de la agenda (HU-VIS-002, «hoy + próximos 7 días»): del primer instante de hoy al
/// primer instante del día 8 (hoy y los 7 siguientes), en hora local.
///
/// La ventana va por días de calendario y no por 24 h: un cambio de hora no corre las agendas de un
/// día a otro.
class VentanaAgenda {
  const VentanaAgenda._(this.inicioDeHoy, this.fin);

  /// Cuántos días después de hoy llega la agenda.
  static const diasSiguientes = 7;

  /// La ventana que arranca el día de [ahora].
  factory VentanaAgenda.de(DateTime ahora) {
    final local = ahora.toLocal();
    final hoy = DateTime(local.year, local.month, local.day);
    return VentanaAgenda._(hoy, DateTime(hoy.year, hoy.month, hoy.day + diasSiguientes + 1));
  }

  /// Hoy a medianoche, hora local.
  final DateTime inicioDeHoy;

  /// El primer instante que ya no entra (medianoche del día 8), hora local.
  final DateTime fin;

  /// Para pedirle a la base: desde (incluido), en UTC.
  DateTime get desdeUtc => inicioDeHoy.toUtc();

  /// Para pedirle a la base: hasta (excluido), en UTC.
  DateTime get hastaUtc => fin.toUtc();

  /// ¿El instante [t] cae dentro de la ventana?
  bool contiene(DateTime t) {
    final local = t.toLocal();
    return !local.isBefore(inicioDeHoy) && local.isBefore(fin);
  }
}

/// Arma la vista de la agenda (23B): filtra lo leído por la ventana, el tipo y el estado, lo ordena
/// por hora y lo agrupa por día con su conteo. Es una función pura: la pantalla la vuelve a correr
/// cada vez que cambia lo leído, un filtro o el minuto.
abstract final class ArmadorAgenda {
  static VistaAgenda armar(List<ItemAgenda> items, FiltrosAgenda filtros, DateTime ahora) {
    final ventana = VentanaAgenda.de(ahora);
    final elegidos = [
      for (final item in items)
        if (!item.agenda.estaBorrada &&
            ventana.contiene(item.agenda.fechaProgramada) &&
            filtros.estado.admite(item.agenda.estado) &&
            (filtros.tipo == null || item.agenda.tipo == filtros.tipo))
          item,
    ]..sort(_porHora);

    final dias = <DiaDeAgenda>[];
    List<ItemAgenda>? delDia;
    DateTime? diaActual;
    for (final item in elegidos) {
      final local = item.agenda.fechaProgramada.toLocal();
      final dia = DateTime(local.year, local.month, local.day);
      if (diaActual == null || dia != diaActual) {
        diaActual = dia;
        delDia = <ItemAgenda>[];
        dias.add(
          DiaDeAgenda(dia: dia, items: delDia, diasDesdeHoy: _diasEntre(ventana.inicioDeHoy, dia)),
        );
      }
      delDia!.add(item);
    }
    return dias.isEmpty ? VistaAgenda.vacia : VistaAgenda(dias: dias);
  }

  static int _porHora(ItemAgenda a, ItemAgenda b) {
    final porFecha = a.agenda.fechaProgramada.compareTo(b.agenda.fechaProgramada);
    return porFecha != 0 ? porFecha : a.agenda.id.compareTo(b.agenda.id);
  }

  /// Días de calendario entre dos medianoches locales (sin que una hora de verano lo corra).
  static int _diasEntre(DateTime desde, DateTime hasta) => DateTime.utc(
    hasta.year,
    hasta.month,
    hasta.day,
  ).difference(DateTime.utc(desde.year, desde.month, desde.day)).inDays;
}
