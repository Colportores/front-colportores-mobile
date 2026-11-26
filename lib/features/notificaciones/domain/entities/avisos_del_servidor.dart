import 'package:equatable/equatable.dart';

/// Una hora del día elegida por la colportora para un aviso del servidor (`"HH:MM"`, 24 h, hora de
/// Montevideo; backend-supabase 0166).
final class HoraDelAviso extends Equatable implements Comparable<HoraDelAviso> {
  const HoraDelAviso(this.hora, this.minuto)
    : assert(hora >= 0 && hora < 24, 'hora fuera de 0..23'),
      assert(minuto >= 0 && minuto < 60, 'minuto fuera de 0..59');

  /// La hora de los avisos de cuotas si nunca se eligió otra.
  static const cuotaPorDefecto = HoraDelAviso(9, 0);

  /// La hora del aviso de «Mañana tenés visitas» si nunca se eligió otra.
  static const agendaPorDefecto = HoraDelAviso(20, 0);

  static final _forma = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$');

  /// Lee `"HH:MM"`; lo que no tiene esa forma (otro tipo, `"9:00"`, `"24:00"`) es `null`.
  static HoraDelAviso? interpretar(Object? valor) {
    if (valor is! String) return null;
    final m = _forma.firstMatch(valor);
    if (m == null) return null;
    return HoraDelAviso(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  final int hora;
  final int minuto;

  /// `"09:00"`: lo que se guarda en el servidor y lo que se muestra.
  String get texto => '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';

  @override
  int compareTo(HoraDelAviso otra) => (hora * 60 + minuto).compareTo(otra.hora * 60 + otra.minuto);

  @override
  List<Object?> get props => [hora, minuto];

  @override
  String toString() => texto;
}

/// Los avisos que manda el servidor y que la colportora enciende o apaga, más la hora de dos de ellos
/// (HU-NOT-004, vista 24 grupo B, `usuario.notif_preferences`).
///
/// Es el objeto ENTERO que se guarda con `guardar_mis_preferencias_de_avisos` (decisión del 04/11, R7:
/// sin PATCH). Una clave que falta cuenta como prendida (y la hora, como la de siempre); las claves que
/// esta versión de la app no conoce ([otras]) se conservan al guardar: son de otra versión o del
/// servidor, y borrarlas por reescribir el objeto sería perder una preferencia.
final class AvisosDelServidor extends Equatable {
  const AvisosDelServidor({
    this.pedidos = true,
    this.tickets = true,
    this.cuotas = true,
    this.asignaciones = true,
    this.agenda = true,
    this.horaCuota = HoraDelAviso.cuotaPorDefecto,
    this.horaAgenda = HoraDelAviso.agendaPorDefecto,
    this.otras = const {},
  });

  static const claves = (
    pedidos: 'pedidos',
    tickets: 'tickets',
    cuotas: 'cuotas',
    asignaciones: 'asignaciones',
    agenda: 'agenda',
    horaCuota: 'hora_cuota',
    horaAgenda: 'hora_agenda',
  );

  /// Lee lo que contestó el servidor. `null` o algo que no es un objeto son los valores de siempre;
  /// un interruptor que no es booleano cuenta como prendido, y una hora ilegible como la de siempre.
  factory AvisosDelServidor.desdeJson(Object? json) {
    if (json is! Map) return const AvisosDelServidor();
    bool prendido(String clave) => json[clave] is bool ? json[clave] as bool : true;
    final conocidas = {
      claves.pedidos,
      claves.tickets,
      claves.cuotas,
      claves.asignaciones,
      claves.agenda,
      claves.horaCuota,
      claves.horaAgenda,
    };
    return AvisosDelServidor(
      pedidos: prendido(claves.pedidos),
      tickets: prendido(claves.tickets),
      cuotas: prendido(claves.cuotas),
      asignaciones: prendido(claves.asignaciones),
      agenda: prendido(claves.agenda),
      horaCuota: HoraDelAviso.interpretar(json[claves.horaCuota]) ?? HoraDelAviso.cuotaPorDefecto,
      horaAgenda:
          HoraDelAviso.interpretar(json[claves.horaAgenda]) ?? HoraDelAviso.agendaPorDefecto,
      otras: {
        for (final e in json.entries)
          if (e.key is String && !conocidas.contains(e.key)) e.key as String: e.value,
      },
    );
  }

  /// «Pedidos» (pedidos autorizados o rechazados por la casa editora).
  final bool pedidos;

  /// «Tickets» (revisados por el coordinador).
  final bool tickets;

  /// «Cuotas» (cuotas pendientes de cobrar).
  final bool cuotas;

  /// «Asignaciones» (zona y campaña).
  final bool asignaciones;

  /// «Recordatorios de agenda»: la copia del servidor del interruptor que vive en el teléfono (para que
  /// el servidor no mande «Mañana tenés visitas» con los recordatorios apagados).
  final bool agenda;

  /// A qué hora llega «Tenés una cuota por cobrar».
  final HoraDelAviso horaCuota;

  /// A qué hora llega «Mañana tenés visitas».
  final HoraDelAviso horaAgenda;

  /// Las claves que esta versión no conoce, tal como llegaron.
  final Map<String, Object?> otras;

  AvisosDelServidor copyWith({
    bool? pedidos,
    bool? tickets,
    bool? cuotas,
    bool? asignaciones,
    bool? agenda,
    HoraDelAviso? horaCuota,
    HoraDelAviso? horaAgenda,
  }) => AvisosDelServidor(
    pedidos: pedidos ?? this.pedidos,
    tickets: tickets ?? this.tickets,
    cuotas: cuotas ?? this.cuotas,
    asignaciones: asignaciones ?? this.asignaciones,
    agenda: agenda ?? this.agenda,
    horaCuota: horaCuota ?? this.horaCuota,
    horaAgenda: horaAgenda ?? this.horaAgenda,
    otras: otras,
  );

  /// Lo que esta versión cambió respecto de [base], aplicado sobre [sobre]: de cada interruptor y cada hora,
  /// si difiere de [base] manda esta versión; si no, queda lo que tiene [sobre] (y sus claves desconocidas).
  /// Sirve para guardar un cambio sobre lo que hay ahora sin pisar lo que la persona no tocó.
  AvisosDelServidor cambiosSobre({
    required AvisosDelServidor base,
    required AvisosDelServidor sobre,
  }) => AvisosDelServidor(
    pedidos: pedidos != base.pedidos ? pedidos : sobre.pedidos,
    tickets: tickets != base.tickets ? tickets : sobre.tickets,
    cuotas: cuotas != base.cuotas ? cuotas : sobre.cuotas,
    asignaciones: asignaciones != base.asignaciones ? asignaciones : sobre.asignaciones,
    agenda: agenda != base.agenda ? agenda : sobre.agenda,
    horaCuota: horaCuota != base.horaCuota ? horaCuota : sobre.horaCuota,
    horaAgenda: horaAgenda != base.horaAgenda ? horaAgenda : sobre.horaAgenda,
    otras: sobre.otras,
  );

  /// El objeto entero que recibe el servidor.
  Map<String, Object?> aJson() => {
    ...otras,
    claves.pedidos: pedidos,
    claves.tickets: tickets,
    claves.cuotas: cuotas,
    claves.asignaciones: asignaciones,
    claves.agenda: agenda,
    claves.horaCuota: horaCuota.texto,
    claves.horaAgenda: horaAgenda.texto,
  };

  @override
  List<Object?> get props => [
    pedidos,
    tickets,
    cuotas,
    asignaciones,
    agenda,
    horaCuota,
    horaAgenda,
    otras,
  ];
}
