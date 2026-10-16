import '../../../../core/error/failure.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_ubicaciones.dart';

/// Los textos de «Posibles duplicados» (vista 10, HU-UBI-006). Los del canvas y los literales de la
/// HU van tal cual; los que ninguno de los dos dice (estados vacío, cargando y error, «Ignorar» y
/// «Editar uno») son provisorios y quedan en el archivo de pendientes del PR.
abstract final class TextosPosiblesDuplicados {
  // ------------------------------------------------------------ la lista (10·01)
  static const titulo = 'Posibles duplicados';
  static const etiquetaBarra = 'POSIBLES DUPLICADOS';
  static const volver = 'Volver';
  // Espacio sin corte entre «5» y «m» en todos los textos que lo llevan: a 360 px con texto grande la
  // «m» no queda sola en un renglón.
  static const _cincoMetros = '5${FormatoUbicaciones.espacioDuro}m';
  static const subtitulo =
      'Son ubicaciones tuyas con la misma calle y número, o a menos de $_cincoMetros.';
  static const revisar = 'Revisar';

  /// «3 para revisar».
  static String paraRevisar(int cantidad) => '$cantidad para revisar';

  /// El aviso de la Lista: «3 posibles duplicados» (el «Revisar» lo agrega el aviso).
  static String avisoEnLista(int cantidad) =>
      cantidad == 1 ? '1 posible duplicado' : '$cantidad posibles duplicados';

  /// El aviso de la Lista cuando una unión falló después de salir de la pantalla: «No pudimos unir
  /// Av. Italia 1234» (el «Revisar» lo agrega el aviso, como en [avisoEnLista]). Si ninguna de las dos
  /// ubicaciones tiene calle ni número ([direccion] vacía): «No pudimos unir dos ubicaciones sin
  /// dirección».
  static String noPudimosUnir(String direccion) => direccion.isEmpty
      ? 'No pudimos unir dos ubicaciones sin dirección'
      : 'No pudimos unir $direccion';

  /// Lo mismo con más de una unión fallida: «No pudimos unir 2 pares».
  static String noPudimosUnirVarios(int cantidad) => 'No pudimos unir $cantidad pares';

  /// El aviso de la Lista para las uniones fallidas de [direcciones] (al menos una): con una dice
  /// la dirección, con más dice cuántos pares.
  static String avisoUnionesFallidas(List<String> direcciones) => direcciones.length == 1
      ? noPudimosUnir(direcciones.single)
      : noPudimosUnirVarios(direcciones.length);

  /// «Misma calle y número» / «A menos de 5 m».
  static String motivo(MotivoDuplicado motivo) => switch (motivo) {
    MotivoDuplicado.mismaDireccion => 'Misma calle y número',
    MotivoDuplicado.cercania => 'A menos de $_cincoMetros',
  };

  /// «a 12 m».
  static String aDistancia(double metros) => 'a ${FormatoUbicaciones.distancia(metros)}';

  /// «Casa · 2 espacios» / «Edificio · 6 deptos». Las visitas todavía no están en el teléfono y no
  /// se inventan.
  static String resumen(Ubicacion ubicacion, int espacios) {
    final tipo = FormatoUbicaciones.tipo(ubicacion.tipo);
    if (ubicacion.tipo == TipoUbicacion.edificio) {
      return '$tipo · ${espacios == 1 ? '1 depto' : '$espacios deptos'}';
    }
    return '$tipo · ${FormatoListaUbicaciones.espacios(espacios)}';
  }

  // ------------------------------------------------------------ comparar el par (10·02)
  static const esElMismoLugar = '¿Es el mismo lugar?';
  static const cualConservar = '¿CUÁL CONSERVAR?';
  static const avisoUnion =
      'Las visitas y los clientes de B pasan a A. B queda como baja con motivo “Duplicado”.';
  static const conservarYUnir = 'Conservar A y unir';
  static const sonDistintos = 'Son distintos';
  static const despues = 'Después';

  /// Provisorios: el canvas solo dibuja «Después».
  static const ignorar = 'Ignorar';
  static const ignorarAyuda = 'Esconde el par 30 días.';
  static const editarUno = 'Editar uno';
  static const editarCual = '¿Cuál querés editar?';
  static const cancelar = 'Cancelar';

  /// D1: misma dirección a menos de 100 m (HU-UBI-006).
  static const direccionUnica =
      'Estas dos ubicaciones tienen la misma dirección y no pueden quedar las dos. '
      'Marcá cuál es el duplicado o corregí la dirección de una.';

  /// «¿Es el mismo lugar?» va seguido de «Misma calle y número, a 12 m.».
  static String detalle(ParDuplicado par) =>
      '${motivo(par.motivo)}, ${aDistancia(par.distanciaMetros)}.';

  static String conservada(String letra) => 'Ubicación $letra, la que se conserva';
  static String duplicada(String letra) => 'Ubicación $letra, la que queda como baja';

  // ------------------------------------------------------------ par resuelto (10·03)
  static const deshacer = 'Deshacer';

  /// «Las dos Av. Italia 1234 quedaron unidas en una.»; sin dirección ([direccion] vacía): «Las dos
  /// ubicaciones quedaron unidas en una.»
  static String unidas(String direccion) => direccion.isEmpty
      ? 'Las dos ubicaciones quedaron unidas en una.'
      : 'Las dos $direccion quedaron unidas en una.';

  // ------------------------------------------------------------ estados que el canvas no dibuja
  static const cargando = 'Buscando posibles duplicados';
  static const vacioTitulo = 'No hay posibles duplicados';
  static const vacioCuerpo =
      'Cuando dos de tus ubicaciones tengan la misma calle y número, o estén a menos de '
      '$_cincoMetros, aparecen acá.';
  static const errorLectura = 'No pudimos revisar tus ubicaciones.';
  static const reintentar = 'Reintentar';
  static const entendido = 'Entendido';
  static const noSePudoGuardar = 'No pudimos guardar tu decisión. Probá de nuevo.';

  // ------------------------------------------------------------ cuando la unión falla (HU-UBI-006)
  static const noSePudoUnir = 'No se pudo marcar como duplicado. Probá de nuevo.';

  /// El texto del aviso rojo según la falla de la unión: con la que se iba a conservar de baja, el
  /// suyo («La ubicación que ibas a conservar ya está dada de baja. Revisá el par de nuevo.»).
  static String falloUnion(Failure falla) =>
      falla is FailureConservadaDeBaja ? falla.mensaje : noSePudoUnir;

  /// «No se pudieron marcar 2 pares como duplicados. Probá de nuevo.»
  static String noSePudieronUnir(int cantidad) =>
      'No se pudieron marcar $cantidad pares como duplicados. Probá de nuevo.';

  /// El texto del aviso rojo según las fallas que hay: con una, el suyo ([falloUnion]); con dos o más,
  /// cuántos pares son.
  static String falloUniones(List<Failure> fallas) =>
      fallas.length == 1 ? falloUnion(fallas.single) : noSePudieronUnir(fallas.length);
}
