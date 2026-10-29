import '../../mapa/domain/entities/ubicacion.dart';
import '../domain/entities/estado_agenda.dart';
import '../domain/entities/filtros_agenda.dart';
import '../domain/entities/item_agenda.dart';
import '../domain/entities/tipo_agenda.dart';
import '../domain/entities/vista_agenda.dart';

/// Los textos de la pestaña Agenda (vista 23B, HU-VIS-002). Los literales son los del canvas; los
/// que el canvas no dibuja están marcados en el pendiente de la HU.
abstract final class TextosAgenda {
  static const eyebrow = 'AGENDA';
  static const titulo = 'Agenda';
  static const subtitulo = 'Hoy y los próximos 7 días';
  static const subtituloCampania = 'En esta campaña';
  static const verMas = 'Ver más';

  static const chipTodas = 'Todas';
  static const chipEntrevistas = 'Entrevistas';
  static const chipCobranzas = 'Cobranzas';
  static const filtroTipo = 'Filtrar por tipo';

  static const agendar = '+ Agendar';
  static const visitasAgendadas = 'VISITAS AGENDADAS';
  static const registrar = 'Registrar';
  static const atrasadas = 'ATRASADAS';
  static const pasoLaHora = 'Pasó la hora · registrá qué pasó';

  static const tagEntrevista = 'Entrevista';
  static const tagCobranza = 'Cobranza';
  static const tagCumplida = 'Cumplida';
  static const tagNoCumplida = 'No cumplida';
  static const tagCancelada = 'Cancelada';

  static const hojaEstadoTitulo = 'Estado';
  static const aplicar = 'Aplicar';

  static const vaciaTitulo = 'No tenés visitas en los próximos 7 días';
  static const vaciaCuerpo =
      'Agendá una entrevista o una cobranza desde la ficha de la persona o desde acá.';

  static const sinResultadosTitulo = 'Ninguna agenda con estos filtros';
  static const limpiarFiltros = 'Limpiar filtros';

  static const errorLectura = 'No pudimos leer tu agenda.';
  static const reintentar = 'Reintentar';

  static const cargando = 'Cargando tu agenda';
  static const noPudimosAbrir = 'No pudimos abrir eso. Probá de nuevo.';
  static const sinDireccion = 'Sin dirección';
  static const sinDatos = 'Visita sin datos';
}

/// Cómo se escribe cada cosa de la agenda: hora, día, dirección y etiquetas. Todo en hora local.
abstract final class FormatoAgenda {
  static const _dias = ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO', 'DOMINGO'];

  /// «09:30».
  static String hora(DateTime momento) {
    final l = momento.toLocal();
    return '${_dos(l.hour)}:${_dos(l.minute)}';
  }

  /// «22/10».
  static String diaMes(DateTime momento) {
    final l = momento.toLocal();
    return '${_dos(l.day)}/${_dos(l.month)}';
  }

  /// El año de [momento] si no es el de [ahora] («2025»), o `null` si es el actual: la lista de la
  /// campaña puede juntar más de un año (campaña permanente, o sin campaña conocida) y «15/12» solo
  /// no dice de cuál.
  static String? anioSiEsOtro(DateTime momento, DateTime ahora) {
    final anio = momento.toLocal().year;
    return anio == ahora.toLocal().year ? null : anio.toString();
  }

  /// «22/10», o «22/10/2025» si el año no es el de [ahora].
  static String diaMesConAnio(DateTime momento, DateTime ahora) {
    final anio = anioSiEsOtro(momento, ahora);
    return anio == null ? diaMes(momento) : '${diaMes(momento)}/$anio';
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');

  /// «HOY · MIÉRCOLES 23», «MAÑANA · JUEVES 24», «VIERNES 25».
  static String rotuloDelDia(DiaDeAgenda dia) {
    final nombre = '${_dias[dia.dia.weekday - 1]} ${dia.dia.day}';
    if (dia.esHoy) return 'HOY · $nombre';
    if (dia.esManana) return 'MAÑANA · $nombre';
    return nombre;
  }

  /// El subtítulo de la pestaña: la ventana de siempre, o la campaña con un estado cerrado o «Todas».
  static String subtituloDe(FiltrosAgenda filtros) =>
      filtros.estado.miraLaCampania ? TextosAgenda.subtituloCampania : TextosAgenda.subtitulo;

  static const _diasCortos = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];

  /// «JUE 24/10 · 14:30» (con el año si no es el de [ahora]): cuándo es una visita en la lista de la
  /// hoja de la casa (23B·10).
  static String cuandoCorto(DateTime momento, DateTime ahora) {
    final l = momento.toLocal();
    return '${_diasCortos[l.weekday - 1]} ${diaMesConAnio(momento, ahora)} · ${hora(momento)}';
  }

  /// La segunda línea de una visita en la hoja de la casa: con quién («María Fernández»), «en» la
  /// dirección si la cobranza es en otra, o el depto si la casa es un edificio. `null` si no hay nada
  /// que decir (la casa ya es el título de la hoja).
  static String? subtituloDeVisitaDeLaCasa(ItemAgenda item) {
    final alternativa = item.alternativa == null ? null : direccion(item);
    final depto = item.numeroDepto?.trim() ?? '';
    final partes = [
      ?item.nombrePersona,
      if (alternativa != null) 'en $alternativa',
      if (alternativa == null && depto.isNotEmpty && item.casa?.tipo == TipoUbicacion.edificio)
        'Depto $depto',
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  /// El rótulo con el conteo del día (HU-VIS-002: «Hoy (3)», «Mañana (5)»).
  static String rotuloConConteo(DiaDeAgenda dia) => '${rotuloDelDia(dia)} (${dia.cantidad})';

  /// «ATRASADAS (2)»: las programadas de días anteriores que siguen sin resultado.
  static String rotuloAtrasadas(int cantidad) => '${TextosAgenda.atrasadas} ($cantidad)';

  /// «Av. Italia 1234», con «· Depto 101» si la casa es un edificio y la cita tiene depto. `null`
  /// si no hay ninguna dirección.
  static String? direccion(ItemAgenda item) {
    final lugar = item.lugar;
    if (lugar == null) return null;
    final partes = [
      for (final p in [lugar.calle, lugar.numero])
        if (p != null && p.trim().isNotEmpty) p.trim(),
    ];
    if (partes.isEmpty) return null;
    final base = partes.join(' ');
    final depto = item.numeroDepto?.trim() ?? '';
    final conDepto = item.alternativa == null && lugar.tipo == TipoUbicacion.edificio;
    return conDepto && depto.isNotEmpty ? '$base · Depto $depto' : base;
  }

  /// El título de la fila: la persona; sin persona, la dirección; sin ninguna, «Visita sin datos».
  static String titulo(ItemAgenda item) =>
      item.nombrePersona ?? direccion(item) ?? TextosAgenda.sinDatos;

  /// El subtítulo: la dirección, salvo que ya sea el título.
  static String? subtitulo(ItemAgenda item) {
    if (item.nombrePersona == null) return null;
    return direccion(item) ?? TextosAgenda.sinDireccion;
  }

  static String tipo(TipoAgenda tipo) => switch (tipo) {
    TipoAgenda.entrevista => TextosAgenda.tagEntrevista,
    TipoAgenda.cobranza => TextosAgenda.tagCobranza,
  };

  /// La etiqueta de la fila: el tipo mientras está programada; el estado cuando ya se cerró.
  static String etiqueta(ItemAgenda item) => switch (item.agenda.estado) {
    EstadoAgenda.programada => tipo(item.agenda.tipo),
    EstadoAgenda.cumplida => TextosAgenda.tagCumplida,
    EstadoAgenda.noCumplida => TextosAgenda.tagNoCumplida,
    EstadoAgenda.cancelada => TextosAgenda.tagCancelada,
  };

  /// «Cancelada el 22/10», o `null` si la agenda sigue programada.
  static String? cierre(ItemAgenda item) {
    final fecha = diaMes(item.agenda.auditoria.updatedAt);
    return switch (item.agenda.estado) {
      EstadoAgenda.programada => null,
      EstadoAgenda.cumplida => 'Cumplida el $fecha',
      EstadoAgenda.noCumplida => 'No cumplida el $fecha',
      EstadoAgenda.cancelada => 'Cancelada el $fecha',
    };
  }

  /// Lo que dice el lector de pantalla de una fila.
  static String etiquetaDeFila(
    ItemAgenda item, {
    required bool vencida,
    bool conFecha = false,
    DateTime? ahora,
  }) {
    final partes = [
      if (conFecha)
        ahora == null
            ? diaMes(item.agenda.fechaProgramada)
            : diaMesConAnio(item.agenda.fechaProgramada, ahora),
      hora(item.agenda.fechaProgramada),
      tipo(item.agenda.tipo),
      titulo(item),
      ?subtitulo(item),
      if (item.agenda.estado != EstadoAgenda.programada) etiqueta(item),
      ?cierre(item),
      if (vencida) TextosAgenda.pasoLaHora,
    ];
    return partes.join('. ');
  }

  static String estado(EstadoFiltroAgenda estado) => switch (estado) {
    EstadoFiltroAgenda.pendientes => 'Pendientes',
    EstadoFiltroAgenda.cumplidas => 'Cumplidas',
    EstadoFiltroAgenda.noCumplidas => 'No cumplidas',
    EstadoFiltroAgenda.canceladas => 'Canceladas',
    EstadoFiltroAgenda.todas => 'Todas',
  };

  /// La segunda línea de cada opción de la hoja «Estado» (solo la tienen «Pendientes»).
  static String? detalleDeEstado(EstadoFiltroAgenda estado) => switch (estado) {
    EstadoFiltroAgenda.pendientes => 'Programadas, de hoy en adelante',
    _ => null,
  };
}
