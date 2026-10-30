import '../domain/entities/contexto_notas_persona.dart';
import '../domain/entities/nota_de_texto.dart';
import '../domain/services/validador_nota.dart';

/// Los textos de las vistas de las notas de una persona (vista 32E, HU-UBI-012). Los del canvas van
/// tal cual; los que el canvas no dibuja (marcados «a confirmar») dicen qué pasa y qué hacer, y se
/// listan en el PR para que Cristian los apruebe.
abstract final class TextosNotas {
  static const rotulo = 'NOTAS';
  static const privacidad = 'Estas notas viven solo en tu celular.';
  static const nuevaNota = '+ Nueva nota';
  static const tituloNueva = 'Nueva nota';
  static const guardarNota = 'Guardar nota';
  static const guardando = 'Guardando…';
  static const reintentar = 'Reintentar';
  static const noPudimosGuardar = 'No pudimos guardar la nota. El texto sigue acá.';
  static const editar = 'Editar';
  static const borrar = 'Borrar';
  static const cerrar = 'Cerrar';
  static const volver = 'Volver';
  static const borrada = 'Nota borrada.';
  static const deshacer = 'Deshacer';
  static const borradasRotulo = 'BORRADAS';
  static const restaurar = 'Restaurar';
  static const sinNotas = 'Todavía no hay notas';
  static const sinNotasAyuda = 'Anotá lo que te sirva para la próxima visita.';

  /// A confirmar: lo que el canvas 32E no dibuja.
  static const tituloGenerico = 'Notas';
  static const tituloEditar = 'Editar nota';
  static const sugerenciaNota = 'Lo que te sirva para la próxima visita';
  static const etiquetaCampo = 'Nota';
  static const opcionesDeLaNota = 'Opciones de la nota';
  static const guardada = 'Guardamos la nota en este teléfono.';
  static const cambiosGuardados = 'Cambios guardados en tu teléfono.';
  static const restaurada = 'Nota restaurada.';
  static const sinBorradas = 'No hay notas borradas.';
  static const sinBorradasAyuda = 'Las que borres van a aparecer acá para poder restaurarlas.';
  static const cargando = 'Cargando las notas';
  static const personaNoEncontrada = 'La persona ya no está en tu teléfono. Volvé atrás.';
  static const noPudimosBorrar = 'No pudimos borrar la nota. Probá de nuevo.';
  static const noPudimosRestaurar = 'No pudimos restaurar la nota. Probá de nuevo.';
  static const noPudimosDeshacer =
      'No pudimos deshacer el borrado. La nota sigue en «Ver borradas»: podés restaurarla desde ahí.';

  /// Las notas de un lugar (vista 39, C·05). `notaDelLugar` es el del canvas; el resto, a confirmar.
  static const notaDelLugar = '+ Nota del lugar';
  static const tituloDelLugar = 'Notas del lugar';
  static const noPudimosLeerDelLugar = 'No pudimos leer las notas del lugar en tu teléfono.';
  static const soloLecturaDelLugar =
      'Este lugar está dado de baja. Podés ver sus notas, pero no agregar, editar ni borrar ninguna.';

  static String titulo(String nombre) => 'Notas de $nombre';

  static String noPudimosLeer(String? nombre) => nombre == null || nombre.trim().isEmpty
      ? 'No pudimos leer las notas en tu teléfono.'
      : 'No pudimos leer las notas de $nombre en tu teléfono.';

  /// Lo que se puede hacer en solo lectura; va después de la causa.
  static const soloLecturaAyuda = 'Podés ver sus notas, pero no agregar, editar ni borrar ninguna.';

  /// El aviso de solo lectura (mapa §2, P3 de #144): la causa y qué se puede hacer.
  static String soloLectura(ContextoNotasPersona contexto, DateTime ahora) =>
      '${causaSoloLectura(contexto, ahora)} $soloLecturaAyuda';

  /// Por qué una persona está en solo lectura, como la ficha (32B·04: «María está de baja desde el
  /// 22/10.», 32B·08: «El depto 3B de Mataojo 2044 está dado de baja.»). «De baja» y no «dada de
  /// baja»: no depende del género de la persona. Lo usan las notas y la edición de la persona.
  static String causaSoloLectura(ContextoNotasPersona contexto, DateTime ahora) {
    final nombre = contexto.nombre;
    return switch (contexto.causa) {
      CausaSoloLectura.personaDeBaja => () {
        final desde = contexto.bajaDesde;
        return desde == null
            ? '$nombre está de baja.'
            : '$nombre está de baja desde el ${FormatoNotas.diaMes(desde, ahora)}.';
      }(),
      CausaSoloLectura.espacioDeBaja => () {
        final depto = contexto.numeroDepto;
        final donde = contexto.direccion;
        if (depto != null && donde != null) return 'El depto $depto de $donde está dado de baja.';
        if (donde != null) return 'El espacio de $donde está dado de baja.';
        if (depto != null) return 'El depto $depto está dado de baja.';
        return 'El espacio de $nombre está dado de baja.';
      }(),
      CausaSoloLectura.sinEspacioActivo => '$nombre ya no está en ningún depto activo.',
      null => '',
    };
  }

  static String verBorradas(int cantidad) => 'Ver borradas ($cantidad)';

  /// Lo que lee el lector de pantalla del botón «Restaurar» de una nota borrada: «Restaurar la nota
  /// del 05/10» o «Restaurar la nota de hoy a las 14:20». [fechaParaLector] es
  /// `FormatoNotas.fechaParaLector` («el 05/10», «hoy a las 14:20»): con «el» va «del».
  static String restaurarLaNota(String fechaParaLector) {
    final fecha = fechaParaLector.startsWith('el ')
        ? 'del ${fechaParaLector.substring(3)}'
        : 'de $fechaParaLector';
    return 'Restaurar la nota $fecha';
  }

  /// La advertencia del límite blando de la HU (5000 caracteres): avisa y deja guardar.
  static String notaLarga(int largo) =>
      'La nota tiene $largo caracteres y lo recomendado es hasta ${ValidadorNota.largoSuave}. '
      'Podés guardarla igual.';
}

/// Cómo se escribe la fecha de una nota (canvas 32E: «HOY 14:20», «05/10»).
abstract final class FormatoNotas {
  static String _dos(int n) => n.toString().padLeft(2, '0');

  static bool _esHoy(DateTime local, DateTime ahora) =>
      local.year == ahora.year && local.month == ahora.month && local.day == ahora.day;

  static String _hora(DateTime local) => '${_dos(local.hour)}:${_dos(local.minute)}';

  static String _dia(DateTime local, DateTime ahora) {
    final base = '${_dos(local.day)}/${_dos(local.month)}';
    return local.year == ahora.year ? base : '$base/${_dos(local.year % 100)}';
  }

  /// «22/10»: el día y el mes, con el año de dos dígitos si no es el actual.
  static String diaMes(DateTime fecha, DateTime ahora) => _dia(fecha.toLocal(), ahora.toLocal());

  /// «HOY 14:20» si se escribió hoy; «05/10» (o «05/10/25» de otro año) si no. Con la hora local.
  static String fecha(NotaDeTexto nota, DateTime ahora) {
    final local = nota.auditoria.createdAt.toLocal();
    final hoy = ahora.toLocal();
    return _esHoy(local, hoy) ? 'HOY ${_hora(local)}' : _dia(local, hoy);
  }

  /// Lo que lee el lector de pantalla: «hoy a las 14:20», «el 05/10».
  static String fechaParaLector(NotaDeTexto nota, DateTime ahora) {
    final local = nota.auditoria.createdAt.toLocal();
    final hoy = ahora.toLocal();
    return _esHoy(local, hoy) ? 'hoy a las ${_hora(local)}' : 'el ${_dia(local, hoy)}';
  }

  /// El título de la hoja de una nota: «Nota de hoy 14:20», «Nota del 05/10».
  static String tituloDelMenu(NotaDeTexto nota, DateTime ahora) {
    final local = nota.auditoria.createdAt.toLocal();
    final hoy = ahora.toLocal();
    return _esHoy(local, hoy) ? 'Nota de hoy ${_hora(local)}' : 'Nota del ${_dia(local, hoy)}';
  }
}
