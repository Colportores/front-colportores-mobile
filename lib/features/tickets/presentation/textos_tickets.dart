import '../../catalogo/presentation/formato_precios.dart' show FormatoPrecios;
import '../../cuenta/presentation/textos_cuenta.dart' show FormatoCuenta;
import '../../depositos/domain/entities/deposito.dart';
import '../domain/entities/item_del_historial.dart';
import '../domain/entities/ticket.dart';

/// Los textos de «Mis tickets» (vista 38B, HU-COB-009) y del detalle de un ticket. Los del canvas van
/// tal cual; los que el canvas no dibuja salen de la misma voz (aceptados por el mapa §2: texto/aviso,
/// #727).
abstract final class TextosTickets {
  // --- 38B·01 -------------------------------------------------------------------------------
  static const eyebrow = 'MI CUENTA';
  static const titulo = 'Mis tickets';
  static const volver = 'Volver';
  static const cargarTicket = '+ Cargar ticket';

  static const filtroTodos = 'Todos';
  static const filtroPorValidar = 'Por validar';
  static const filtroRechazados = 'Rechazados';
  static const filtroAlquiler = 'Alquiler';

  /// Lo que oye el lector de pantalla al llegar a los filtros.
  static const filtrosEtiqueta = 'Filtrar los tickets';

  static String filtro(FiltroDeTickets filtro) => switch (filtro) {
    FiltroDeTickets.todos => filtroTodos,
    FiltroDeTickets.porValidar => filtroPorValidar,
    FiltroDeTickets.rechazados => filtroRechazados,
    FiltroDeTickets.alquiler => filtroAlquiler,
  };

  static const estadoPorValidar = 'Por validar';
  static const estadoValidado = 'Validado';
  static const estadoRechazado = 'Rechazado';
  static const estadoEnCola = 'En cola';
  static const estadoDevuelto = 'Devuelto';

  static String estado(EstadoDelItem estado) => switch (estado) {
    EstadoDelItem.porValidar => estadoPorValidar,
    EstadoDelItem.validado => estadoValidado,
    EstadoDelItem.rechazado => estadoRechazado,
    EstadoDelItem.enCola => estadoEnCola,
    EstadoDelItem.devuelto => estadoDevuelto,
  };

  /// La primera parte de la línea de arriba («BANCO», «RETIRO»).
  static String lugarCorto(LugarDelTicket lugar) => switch (lugar) {
    LugarDelTicket.banco => 'BANCO',
    LugarDelTicket.oficina => 'OFICINA',
    LugarDelTicket.retiro => 'RETIRO',
    LugarDelTicket.cobroConTarjeta => 'COBRO CON TARJETA',
    LugarDelTicket.deposito => 'DEPÓSITO',
    LugarDelTicket.otro => 'OTRO',
  };

  /// El lugar en el subtítulo del detalle («Banco · casa editora»).
  static String lugarLargo(LugarDelTicket lugar) => switch (lugar) {
    LugarDelTicket.banco => 'Banco',
    LugarDelTicket.oficina => 'Oficina',
    LugarDelTicket.retiro => 'Retiro por el coordinador',
    LugarDelTicket.cobroConTarjeta => 'Cobro con tarjeta',
    LugarDelTicket.deposito => 'Depósito',
    LugarDelTicket.otro => 'Otro',
  };

  static String concepto(ConceptoDeDeposito concepto) => switch (concepto) {
    ConceptoDeDeposito.casaEditora => 'Casa editora',
    ConceptoDeDeposito.alquiler => 'Alquiler',
  };

  static String tarjeta(TipoDeTarjeta? tipo) => switch (tipo) {
    TipoDeTarjeta.debito => 'Débito',
    TipoDeTarjeta.credito => 'Crédito',
    null => 'No',
  };

  // --- Lo que hay en cada fila --------------------------------------------------------------

  /// «HOY · BANCO» o «20/10 · BANCO»: [hoy] es el día de ahora, en la hora del teléfono.
  static String lineaDeArriba(ItemDelHistorial item, DateTime hoy) {
    final dia = esHoy(item.fecha, hoy) ? 'HOY' : FormatoCuenta.fecha(item.fecha);
    return '$dia · ${lugarCorto(item.lugar)}';
  }

  static bool esHoy(DateTime fecha, DateTime hoy) {
    final f = fecha.toLocal();
    final h = hoy.toLocal();
    return f.year == h.year && f.month == h.month && f.day == h.day;
  }

  /// «Casa editora · débito · aut. 004512», «Casa editora · la foto no se lee» (rechazado) o «Se envía
  /// cuando vuelva la red» (en cola). Sin dato que decir queda vacío.
  static String subtitulo(ItemDelHistorial item) {
    if (item.estado == EstadoDelItem.enCola) return seEnviaCuandoVuelva;
    return [
      if (item.concepto case final c?) concepto(c),
      if (item.estado == EstadoDelItem.rechazado && item.motivoRechazo != null)
        item.motivoRechazo!
      else ...[
        if (item.tarjetaTipo case final t?) tarjeta(t).toLowerCase(),
        if (item.numeroAutorizacion case final a?) 'aut. $a',
      ],
    ].join(' · ');
  }

  /// Lo que lee el lector de pantalla de una fila.
  static String hablada(ItemDelHistorial item, DateTime hoy) {
    final dia = esHoy(item.fecha, hoy) ? 'hoy' : 'el ${FormatoCuenta.fecha(item.fecha)}';
    final sub = subtitulo(item);
    return '${estado(item.estado)}. ${lugarLargo(item.lugar)}, $dia. '
        '${FormatoPrecios.monto(item.montoCentavos)}.${sub.isEmpty ? '' : ' $sub.'}';
  }

  static const seEnviaCuandoVuelva = 'Se envía cuando vuelva la red';

  // --- 38B·04, 38B·05, 38B·06, 38B·07 ------------------------------------------------------
  static const vacioTitulo = 'Todavía no cargaste tickets';
  static const vacioTexto =
      'Cuando deposites o tu coordinador retire el dinero, cargá el ticket acá.';

  /// El canvas no dibuja un filtro sin resultados.
  static String sinResultadosDelFiltro(FiltroDeTickets filtro) => switch (filtro) {
    FiltroDeTickets.todos => vacioTitulo,
    FiltroDeTickets.porValidar => 'No tenés tickets por validar.',
    FiltroDeTickets.rechazados => 'No tenés tickets rechazados.',
    FiltroDeTickets.alquiler => 'No tenés tickets de alquiler.',
  };

  static const cargando = 'Cargando tus tickets';
  static const errorAlTraer = 'No pudimos traer tus tickets.';
  static const reintentar = 'Reintentar';

  /// 38B·06: «Sin conexión. Los estados son de ayer a las 21:00.» Sin ninguna bajada todavía no hay
  /// hora que decir: se dice que los estados son los del teléfono.
  static String sinConexion(DateTime? bajadoEn, DateTime ahora) {
    if (bajadoEn == null) {
      return 'Sin conexión. Los estados son los que guardó el teléfono.';
    }
    return 'Sin conexión. Los estados son ${FormatoCuenta.cuandoYHora(bajadoEn, ahora)}.';
  }

  // --- El detalle (38B·02, 38B·03) ---------------------------------------------------------
  static String eyebrowDelDetalle(DateTime fecha) => 'TICKET DEL ${FormatoCuenta.fecha(fecha)}';

  /// «Banco · casa editora» (la línea de abajo del monto).
  static String subtituloDelDetalle(ItemDelHistorial item) {
    final c = item.concepto;
    return c == null
        ? lugarLargo(item.lugar)
        : '${lugarLargo(item.lugar)} · ${concepto(c).toLowerCase()}';
  }

  static const filaFecha = 'Fecha';
  static const filaAutorizacion = 'Autorización';
  static const filaTarjeta = 'Tarjeta';
  static const cargarDeNuevo = 'Cargar de nuevo';

  /// 38B·02: «Tu coordinador lo rechazó: «La foto no se lee». No se acreditó.» Sin motivo se dice solo lo que
  /// pasó.
  static String rechazado(String? motivo) => motivo == null
      ? 'Tu coordinador lo rechazó. No se acreditó.'
      : 'Tu coordinador lo rechazó: «$motivo». No se acreditó.';

  /// 38B·03: «Validado por Marta Pérez el 16/10. Se acreditó al alquiler.» El teléfono no tiene el
  /// nombre del coordinador (no baja con el sync): dice la fecha (el nombre va en el seguimiento #728).
  static String validado(ItemDelHistorial item) {
    final cuando = item.validadoEn == null ? '' : ' el ${FormatoCuenta.fecha(item.validadoEn!)}';
    final destino = switch (item.concepto) {
      ConceptoDeDeposito.alquiler => ' Se acreditó al alquiler.',
      ConceptoDeDeposito.casaEditora => ' Se acreditó a tu deuda con la casa editora.',
      null => ' Se acreditó.',
    };
    return 'Validado$cuando.$destino';
  }

  /// El canvas no dibuja el detalle de un ticket que espera.
  static const porValidarConTicket =
      'Queda por validar: se acredita cuando tu coordinador valide el ticket.';
  static const porValidarSinTicket =
      'Queda por validar: se acredita cuando tu coordinador confirme el retiro.';

  /// El coordinador devolvió un pago de alquiler que había validado: ya no suma (decisión del 23/11).
  static const devueltoDelDetalle = 'Tu coordinador te devolvió el pago. No suma a tu cuenta.';
  static const enColaDelDetalle =
      'Todavía no llegó al servidor. Se envía cuando vuelva la conexión.';

  // --- La foto del detalle ------------------------------------------------------------------
  static const foto = 'Foto del ticket';
  static const cargandoLaFoto = 'Cargando la foto';
  static const fotoVencida =
      'La foto ya no está disponible: se guarda 4 meses. Los datos del ticket siguen acá.';
  static const fotoSinRed = 'Sin conexión. La foto se ve cuando vuelva la red.';
  static const fotoNoDisponible = 'No pudimos traer la foto.';
  static const fotoSinEnviar = 'La foto todavía no se envió. Se envía cuando vuelva la conexión.';
  static const fotoRechazada =
      'La foto no se pudo enviar y ya no se puede reintentar. Avisale a tu coordinador.';
}
