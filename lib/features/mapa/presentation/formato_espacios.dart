import '../domain/entities/espacio.dart';
import '../domain/entities/ubicacion.dart';

/// Los textos de la hoja de una ubicación y de la gestión de sus deptos (vista 11, HU-UBI-007). Los
/// del canvas están letra por letra («TEXTOS PROPUESTA» de la vista 11); los que el canvas no dibuja
/// (cargando, vacío, error, la baja) van marcados como propuesta en el pendiente del issue.
abstract final class TextosEspacios {
  // Del canvas (11·01 a 11·03).
  static const masDepartamento = '+ Departamento';
  static const sinPiso = 'Sin piso';
  static const sinNumero = 'Sin número';
  static const nuevoDepartamento = 'Nuevo departamento';
  static const numeroObligatorio = 'NÚMERO · OBLIGATORIO';
  static const pisoOpcional = 'PISO · OPCIONAL';
  static const agregar = 'Agregar';
  static const agregarYCargarOtro = 'Agregar y cargar otro';

  /// «Editar edificio» (canvas); para una casa o un negocio, el mismo botón con su tipo.
  static String editarUbicacion(TipoUbicacion tipo) => switch (tipo) {
    TipoUbicacion.edificio => 'Editar edificio',
    TipoUbicacion.negocio => 'Editar negocio',
    TipoUbicacion.casa => 'Editar casa',
  };

  /// «Depto 101»; «Sin número» si el espacio no tiene número (solo en pantalla: `numero_depto` sigue
  /// nulo).
  static String depto(Espacio espacio) =>
      espacio.sinNumero ? sinNumero : 'Depto ${espacio.numeroDepto!.trim()}';

  /// «Depto 101» a secas, para los avisos que nombran un número.
  static String deptoNumero(String numero) => 'Depto ${numero.trim()}';

  /// «PISO 1» (canvas); el rótulo de un grupo.
  static String piso(String piso) => 'PISO ${piso.trim()}'.toUpperCase();

  static const grupoSinPiso = 'SIN PISO';

  /// «6 deptos» (canvas); «1 depto».
  static String cantidad(int total) => total == 1 ? '1 depto' : '$total deptos';

  /// «Ya existe el departamento 102 en este edificio.» (canvas 11·03).
  static String repetido(String numero, TipoUbicacion tipo) =>
      'Ya existe el departamento ${numero.trim()} en este '
      '${tipo == TipoUbicacion.negocio ? 'negocio' : 'edificio'}.';

  /// «Ver depto 102 ›» (canvas 11·03).
  static String verDepto(String numero) => 'Ver depto ${numero.trim()} ›';

  // Lo que el canvas no dibuja (propuestas).
  static const cerrar = 'Cerrar';
  static const cargando = 'Cargando los departamentos…';
  static const vacioTitulo = 'Todavía no hay departamentos';
  static const vacioCuerpo = 'Tocá «+ Departamento» para agregar los que vas a visitar.';
  static const errorLectura = 'No pudimos leer los departamentos de tu teléfono. Probá de nuevo.';
  static const noPudimosAbrirEdicion = 'No pudimos abrir la edición. Probá de nuevo.';
  static const errorUbicacion = 'No pudimos abrir esta ubicación. Probá de nuevo.';
  static const reintentar = 'Reintentar';
  static const editarDepartamento = 'Editar departamento';
  static const guardar = 'Guardar';
  static const cancelar = 'Cancelar';
  static const guardando = 'Guardando…';
  static const agregando = 'Agregando…';
  static const teclaLetras = 'ABC';
  static const teclaNumeros = '123';
  static const tecladoALetras = 'Teclado con letras';
  static const tecladoANumeros = 'Teclado numérico';
  static const noPudimosGuardar = 'No pudimos guardar el departamento. Probá de nuevo.';
  static const ubicacionDeBaja =
      'Esta ubicación está dada de baja: no se le pueden cambiar deptos.';

  /// Lo que dice el lector de pantalla cuando «Agregar y cargar otro» deja el formulario limpio.
  static String agregado(String numero) => '${deptoNumero(numero)} agregado.';

  // La baja de un depto.
  static const darDeBaja = 'Dar de baja este depto';
  static const darDeBajaAccion = 'Dar de baja';
  static const noSePuedeDarDeBaja = 'No se puede dar de baja';
  static const entendido = 'Entendido';
  static const dandoDeBaja = 'Dando de baja…';
  static const noPudimosDarDeBaja = 'No pudimos dar de baja el departamento. Probá de nuevo.';

  /// El título de la confirmación de la baja de un depto sin personas: «¿Dar de baja el depto 102?»;
  /// sin número no puede decir «el depto Sin número», dice «este depto sin número».
  static String preguntaBaja(Espacio espacio) => '¿Dar de baja ${_deLaLista(espacio)}?';

  static String cuerpoBaja(TipoUbicacion tipo) =>
      'Deja de aparecer en la lista del ${tipo == TipoUbicacion.negocio ? 'negocio' : 'edificio'}.';

  static String _deLaLista(Espacio espacio) =>
      espacio.sinNumero ? 'este depto sin número' : 'el ${depto(espacio).toLowerCase()}';

  /// Lo que dice el lector de pantalla de una fila de la lista.
  static String filaSemantica(Espacio espacio) => '${depto(espacio)}. Editar.';

  // Los dados de baja y «Reactivar» (#473, seguimiento de #211). Siguen los textos de la vista 09·03 y
  // 09·04 («Reactivar», «… reactivada. Vuelve a aparecer en el mapa.», «Deshacer»), dichos para un
  // depto; el «Deshacer» y su plazo de 8 s son los de `TextosReactivar`.
  static const dadosDeBaja = 'Dados de baja';
  static const reactivar = 'Reactivar';
  static const reactivando = 'Reactivando…';
  static const cerrarAviso = 'Cerrar el aviso';
  static const errorBajas = 'No pudimos leer los deptos dados de baja. Probá de nuevo.';
  static const noPudimosReactivar = 'No pudimos reactivar el departamento. Probá de nuevo.';
  static const noPudimosDeshacer =
      'No pudimos deshacer. Podés darlo de baja de nuevo desde su edición.';

  /// El rótulo de «Dados de baja» para el lector de pantalla: «Dados de baja, 2 deptos».
  static String dadosDeBajaSemantica(int total) => '$dadosDeBaja, ${cantidad(total)}';

  /// El renglón de piso de un depto dado de baja: «Piso 1».
  static String pisoDeLaFila(String piso) => 'Piso ${piso.trim()}';

  /// «Reactivar Depto 102», lo que dice el lector del botón de una fila.
  static String reactivarSemantica(Espacio espacio) => '$reactivar ${depto(espacio)}';

  /// «Reactivando… Depto 102», lo que dice el lector del botón mientras escribe.
  static String reactivandoSemantica(Espacio espacio) => '$reactivando ${depto(espacio)}';

  /// Lo que dice el lector de una fila de «Dados de baja».
  static String filaBajaSemantica(Espacio espacio) => '${depto(espacio)}. Dado de baja.';

  /// «Depto 102 reactivado. Vuelve a aparecer en el edificio.» (09·04, para un depto).
  static String reactivado(Espacio espacio, TipoUbicacion tipo) =>
      '${espacio.sinNumero ? 'Depto sin número' : depto(espacio)} reactivado. '
      'Vuelve a aparecer en el ${_delLugar(tipo)}.';

  /// Otro depto activo tomó el número mientras este estaba de baja: no se reactiva y se dice qué hacer.
  static String reactivarRepetido(Espacio espacio, TipoUbicacion tipo) =>
      'No se puede reactivar ${_deLaLista(espacio)}: ya hay otro con ese número en este '
      '${_delLugar(tipo)}. Cambiale el número al que está activo y probá de nuevo.';

  static String _delLugar(TipoUbicacion tipo) =>
      tipo == TipoUbicacion.negocio ? 'negocio' : 'edificio';
}
