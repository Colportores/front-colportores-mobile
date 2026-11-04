import '../../../mapa/domain/entities/consulta_lista_ubicaciones.dart';
import '../entities/estado_agenda.dart';
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
/// por hora y lo agrupa por día con su conteo. Las `PROGRAMADA` de días anteriores a hoy (una visita
/// que pasó y nadie registró) no se pierden: van al grupo «ATRASADAS» arriba de «HOY». Es una función
/// pura: la pantalla la vuelve a correr cada vez que cambia lo leído, un filtro o el minuto.
abstract final class ArmadorAgenda {
  /// Cuántas agendas suma cada «Ver más»: las de siempre de las listas de la app (Supuesto S14, el
  /// lazy loading de la lista de ubicaciones), sin un número nuevo.
  static const tamanoPagina = ConsultaListaUbicaciones.tamanoPagina;

  /// La lista de **la campaña en curso** (un estado cerrado o «Todas», HU-VIS-002): lo leído de toda la
  /// campaña, filtrado por tipo y estado, de la más nueva a la más vieja, agrupado por día (también
  /// del más nuevo al más viejo) y cortado en [limite] agendas; [VistaAgenda.hayMas] dice si quedan.
  static VistaAgenda armarCampania(
    List<ItemAgenda> items,
    FiltrosAgenda filtros,
    DateTime ahora, {
    int limite = tamanoPagina,
  }) {
    final hoy = VentanaAgenda.de(ahora).inicioDeHoy;
    final elegidos = [
      for (final item in items)
        if (!item.agenda.estaBorrada &&
            filtros.estado.admite(item.agenda.estado) &&
            (filtros.tipo == null || item.agenda.tipo == filtros.tipo))
          item,
    ]..sort((a, b) => _porHora(b, a));
    final visibles = elegidos.take(limite).toList();

    final dias = <DiaDeAgenda>[];
    List<ItemAgenda>? delDia;
    DateTime? diaActual;
    for (final item in visibles) {
      final local = item.agenda.fechaProgramada.toLocal();
      final dia = DateTime(local.year, local.month, local.day);
      if (diaActual == null || dia != diaActual) {
        diaActual = dia;
        delDia = <ItemAgenda>[];
        dias.add(DiaDeAgenda(dia: dia, items: delDia, diasDesdeHoy: _diasEntre(hoy, dia)));
      }
      delDia!.add(item);
    }
    return VistaAgenda(dias: dias, deCampania: true, hayMas: elegidos.length > visibles.length);
  }

  static VistaAgenda armar(List<ItemAgenda> items, FiltrosAgenda filtros, DateTime ahora) {
    final ventana = VentanaAgenda.de(ahora);
    final elegidos = <ItemAgenda>[];
    final atrasadas = <ItemAgenda>[];
    for (final item in items) {
      final agenda = item.agenda;
      if (agenda.estaBorrada ||
          !filtros.estado.admite(agenda.estado) ||
          (filtros.tipo != null && agenda.tipo != filtros.tipo)) {
        continue;
      }
      if (ventana.contiene(agenda.fechaProgramada)) {
        elegidos.add(item);
      } else if (agenda.estado == EstadoAgenda.programada &&
          agenda.fechaProgramada.toLocal().isBefore(ventana.inicioDeHoy)) {
        atrasadas.add(item);
      }
    }
    elegidos.sort(_porHora);
    atrasadas.sort(_porHora);

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
    return dias.isEmpty && atrasadas.isEmpty
        ? VistaAgenda.vacia
        : VistaAgenda(dias: dias, atrasadas: atrasadas);
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
