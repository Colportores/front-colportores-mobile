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

  static const chipTodas = 'Todas';
  static const chipEntrevistas = 'Entrevistas';
  static const chipCobranzas = 'Cobranzas';
  static const filtroTipo = 'Filtrar por tipo';

  static const agendar = '+ Agendar';
  static const registrar = 'Registrar';
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

  static String _dos(int n) => n.toString().padLeft(2, '0');

  /// «HOY · MIÉRCOLES 23», «MAÑANA · JUEVES 24», «VIERNES 25».
  static String rotuloDelDia(DiaDeAgenda dia) {
    final nombre = '${_dias[dia.dia.weekday - 1]} ${dia.dia.day}';
    if (dia.esHoy) return 'HOY · $nombre';
    if (dia.esManana) return 'MAÑANA · $nombre';
    return nombre;
  }

  /// El rótulo con el conteo del día (HU-VIS-002: «Hoy (3)», «Mañana (5)»).
  static String rotuloConConteo(DiaDeAgenda dia) => '${rotuloDelDia(dia)} (${dia.cantidad})';

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
  static String etiquetaDeFila(ItemAgenda item, {required bool vencida}) {
    final partes = [
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
