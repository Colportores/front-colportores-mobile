import '../domain/entities/franja_horaria.dart';
import '../domain/entities/tipo_agenda.dart';
import '../domain/entities/visita.dart';

/// Los textos del detalle y de «Modificar agenda» (vista 23, grupo C, HU-VIS-003, 23C·01, 23C·02,
/// 23C·03, 23C·06 y 23C·07).
///
/// Los del canvas van letra por letra. Los que el canvas no dibuja son propuestas: quedan marcadas en
/// el PR como «para confirmar» (mapa §2: texto/aviso).
abstract final class TextosDetalleAgenda {
  // 23C·01: el detalle.
  static const rotulo = 'AGENDA';
  static const volver = 'Volver';
  static const registrarResultado = 'Registrar resultado';
  static const modificar = 'Modificar';
  static const etiquetaEstado = 'Estado';
  static const etiquetaCuando = 'Cuándo';
  static const etiquetaFranja = 'Franja';
  static const etiquetaRecordatorio = 'Recordatorio';
  static const etiquetaNota = 'Nota';
  static const programada = 'Programada';
  static const cumplida = 'Cumplida';
  static const noCumplida = 'No cumplida';
  static const cancelada = 'Cancelada';

  /// El valor de un renglón que no se aplica (23C·06: «Recordatorio —»).
  static const sinValor = '—';

  // Lo que el canvas no dibuja: renglones vacíos y recordatorio.
  static const sinFranja = 'Sin franja';
  static const sinNota = 'Sin nota';
  static const recordatorioApagado = 'Apagado';
  static const recordatorioYaPaso = 'Ya pasó';

  // 23C·06: cumplida.
  static const yaTieneResultado =
      'Esta visita ya tiene resultado: no se puede modificar ni cancelar.';

  /// Una agenda cancelada: el canvas no la dibuja (la HU: «solo editable si PROGRAMADA»).
  static const estaCancelada = 'Esta agenda está cancelada: no se puede modificar.';

  // Leer el detalle.
  static const cargando = 'Cargando la agenda…';
  static const noPudimosLeer = 'No pudimos leer la agenda en tu teléfono.';
  static const reintentar = 'Reintentar';
  static const noEstaMas = 'Esa agenda ya no está en tu teléfono. Volvé a la lista de agendados.';

  /// El resultado de la visita que cerró la agenda: «Entrevista hecha», «No contestó»…
  static String resultado(TipoResultadoVisita r) => switch (r) {
    TipoResultadoVisita.venta => 'Venta',
    TipoResultadoVisita.entrevista => 'Entrevista hecha',
    TipoResultadoVisita.cobranza => 'Cobranza',
    TipoResultadoVisita.rechazo => 'Rechazó',
    TipoResultadoVisita.noContesto => 'No contestó',
  };

  /// El tipo como título del detalle.
  static String tipo(TipoAgenda t) => switch (t) {
    TipoAgenda.entrevista => 'Entrevista',
    TipoAgenda.cobranza => 'Cobranza',
    TipoAgenda.entrega => 'Entrega',
  };

  /// La franja en el detalle: «Primera tarde».
  static String franja(FranjaHoraria f) => f.etiqueta;

  /// El renglón del lector de pantalla: «Estado: Programada».
  static String lectorFila(String etiqueta, String valor) => '$etiqueta: $valor';

  // 23C·02: modificar.
  static const modificarRotulo = 'MODIFICAR AGENDA';
  static const modificarTitulo = 'Modificar agenda';
  static const guardarCambios = 'Guardar cambios';

  /// 23C·02.
  static const guardando = 'Guardando…';

  /// 23C·02: lo que dice debajo del formulario; [hora] ya es «10:00».
  static String reprogramamos(String hora) => 'Reprogramamos el recordatorio para las $hora.';

  /// La hora del aviso cae otro día que la visita: «lun 12/10 a las 23:40».
  static String reprogramamosOtroDia(String dia, String hora) =>
      'Reprogramamos el recordatorio para el $dia a las $hora.';

  /// Con los recordatorios apagados en las preferencias.
  static const recordatoriosApagados =
      'Los recordatorios de agenda están apagados: no te vamos a avisar. '
      'Los prendés en Preferencias de notificaciones.';

  /// Debajo del formulario: la hora nueva ya pasó, así que no habrá recordatorio.
  static const horaPasadaSinRecordatorio =
      'Si la guardás igual, no te vamos a avisar: la hora ya pasó.';

  /// La visita es en menos que la anticipación: no hay recordatorio.
  static String sinTiempoDeAviso(int minutos) =>
      'Falta menos de $minutos min para la visita: no hay recordatorio.';

  /// «Hoy a las 11:00 ya pasó (son las 14:35). ¿La guardás igual?».
  static String horaPasadaTexto(String cuando, String ahora) =>
      '$cuando ya pasó (son las $ahora). ¿La guardás igual?';

  static const guardarIgual = 'Guardar igual';

  // 23C·03: el aviso de éxito; [hora] ya es «10:00».
  static String guardado(String hora) => 'Guardado. El recordatorio pasó a las $hora.';

  static String guardadoOtroDia(String dia, String hora) =>
      'Guardado. El recordatorio pasó al $dia a las $hora.';

  /// Decidido el 26/10 (mapa §2, desde #453): no se promete un recordatorio que no hay.
  static String guardadoSinTiempoDeAviso(int minutos) =>
      'Guardado. Falta menos de $minutos min para la visita: no hay recordatorio.';

  static const guardadoSinPermiso =
      'Guardado. Las notificaciones están apagadas: no te va a llegar el recordatorio.';
  static const guardadoConRecordatoriosApagados =
      'Guardado. Los recordatorios están apagados: no te vamos a avisar.';
  static const guardadoSinAviso =
      'Guardado, pero no pudimos reprogramar el recordatorio. Revisá la visita en tu agenda.';
  static const guardadoSinAvisoHoraPasada =
      'Guardado. La hora ya había pasado: no hay recordatorio.';

  /// Nada cambió: no se escribió nada.
  static const guardadoSinCambios = 'Guardado. No había nada para cambiar.';

  // 23C·07: error al guardar el cambio.
  static const noPudimosGuardar = 'No pudimos guardar el cambio. La agenda sigue como estaba.';

  // Leer la casa del formulario.
  static const noPudimosLeerLaCasa = 'No pudimos leer la casa en tu teléfono.';
  static const guardarEsperaLaCasa = 'Esperá a que carguemos la casa para guardar.';
}
