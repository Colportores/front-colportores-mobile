import '../../ventas/domain/services/reglas_de_venta.dart';
import '../domain/entities/transferencia.dart';

/// Los textos de la vista 40 (HU-STK-005, #512), tal como los dibuja el canvas
/// `40 Transferencia de Materiales`. Lo que el canvas no dice va en «A confirmar (mapa §2: texto)».
abstract final class TextosTransferencias {
  // --- 40A · Pedir la transferencia -----------------------------------------------------------

  static const eyebrow = 'TRANSFERENCIA';
  static const titulo = 'Pedir materiales a otro colportor';

  /// El nombre de la acción (decisión de Cristian, 28/10): «cambia de pedir prestado a pedir
  /// transferencia de materiales».
  static const accionPedir = 'Pedir transferencia de materiales';
  static const accionVer = 'Transferencias';
  static const quePedis = 'QUÉ PEDÍS';
  static const aQuien = 'A QUIÉN';
  static const sePediAEsta = 'SE LO PEDÍS A';
  static const elegirColportor = 'Elegir colportor';
  static const deTuCampania = 'De tu campaña';
  static const cambiar = 'Cambiar';
  static const pedirTransferencia = 'Pedir transferencia';
  static const pedirCuandoHayConexion = 'Pedir cuando haya conexión';
  static const enviando = 'Enviando…';
  static const reintentar = 'Reintentar';
  static const elegiAQuien = 'Elegí a quién se lo pedís.';
  static const sumaUnMaterial = 'Sumá al menos un material.';
  static const tenes = 'Tenés';
  static const bonificable = '◆ Bonificable';

  /// 40A·03: lo que le pasa a lo pedido. [nombre] es quien entrega.
  static String laTieneQueAutorizar(String nombre) =>
      'Tu coordinadora la tiene que autorizar. $nombre la ve desde que la enviás.';

  /// 40A·07.
  static const sinConexionQuedaEnCola =
      'Sin conexión. La transferencia queda en cola y sube sola cuando vuelva.';

  /// 40A·08 (la causa verdadera de la falla: no se guardó nada; ver [FailureTransferenciaNoGuardada]).
  static const errorAlEnviar =
      'No pudimos enviar la transferencia. No se envió nada: probá de nuevo.';

  /// Las pestañas de materiales (las de Precios sin colecciones).
  static const libros = 'Libros';
  static const misioneros = 'Misioneros';
  static const revistas = 'Revistas';

  /// A confirmar (mapa §2: texto): el canvas no dibuja la categoría sin materiales.
  static const sinMaterialesEnLaCategoria = 'No hay materiales en esta categoría.';

  /// A confirmar (mapa §2: texto): el catálogo todavía no bajó al teléfono.
  static const sinCatalogo =
      'Todavía no bajó el catálogo a tu teléfono. Conectate para verlo y volvé a intentar.';

  static String chipConCantidad(String categoria, int cuantos) =>
      cuantos > 0 ? '$categoria · $cuantos' : categoria;

  // --- 40A·02 · El selector de colportor ------------------------------------------------------

  static const aQuienLePedis = '¿A quién le pedís?';
  static const listo = 'Listo';
  static String colportoresDe(String campania) => 'Colportores de $campania.';

  /// A confirmar (mapa §2: texto): el canvas no dibuja la lectura ni su falla.
  static const cargandoColportores = 'Buscando a los colportores de tu campaña…';
  static const errorColportores =
      'No pudimos traer a los colportores de tu campaña. Probá de nuevo con conexión.';

  // --- 40A·06 · Enviada -----------------------------------------------------------------------

  static const tituloEnviada = 'Transferencia pedida';
  static const enviadaTitulo = 'Tu coordinadora la tiene que autorizar';
  static const enviadaTexto = 'Te avisamos cuando la autorice o la rechace.';
  static const lePediste = 'Le pediste a';
  static const verTransferencias = 'Ver transferencias';

  // --- 40A·09 · No hay a quién pedirle --------------------------------------------------------

  static const sinCompanierosTitulo = 'No hay otro colportor en tu campaña';
  static const sinCompanierosTexto = 'Para sumar materiales, hacé un pedido a la casa editora.';
  static const hacerUnPedido = 'Hacer un pedido';

  /// A confirmar (mapa §2: coherencia entre pantallas): el pedido a la casa editora (vista 37, #387) no
  /// está en la app; mientras tanto la pantalla se cierra.
  static const volver = 'Volver';

  // --- 40B · Ver las transferencias -----------------------------------------------------------

  static const eyebrowLista = 'MI CUENTA';
  static const tituloLista = 'Transferencias';
  static const pedirOtra = '+ Pedir transferencia';
  static const filtroTodas = 'Todas';
  static const filtroPorAutorizar = 'Por autorizar';
  static const filtroAutorizadas = 'Autorizadas';
  static const filtroCerradas = 'Cerradas';

  static const sinTransferenciasTitulo = 'Todavía no hay transferencias';
  static const sinTransferenciasTexto =
      'Si te falta un material y otro colportor de tu campaña tiene, pedíselo acá.';

  /// A confirmar (mapa §2: texto): el filtro no muestra ninguna.
  static const sinEnElFiltro = 'No hay transferencias con este filtro.';

  /// 40B·10.
  static const errorAlTraer = 'No pudimos traer tus transferencias.';
  static const cargando = 'Cargando tus transferencias';

  /// 40B·11: «Sin conexión. Ves las transferencias como estaban ayer a las 21:00.» Sin hora guardada no
  /// se afirma ninguna.
  static String sinConexionLista(DateTime? bajadoEn, DateTime ahora) => bajadoEn == null
      ? 'Sin conexión. Ves las transferencias que tenés en el teléfono.'
      : 'Sin conexión. Ves las transferencias como estaban ${_cuandoYHora(bajadoEn, ahora)}.';

  static String estado(EstadoDeTransferencia e, {bool enCola = false}) => switch (e) {
    _ when enCola && e == EstadoDeTransferencia.porAutorizar => 'En cola',
    EstadoDeTransferencia.porAutorizar => 'Por autorizar',
    EstadoDeTransferencia.autorizada => 'Autorizada',
    EstadoDeTransferencia.rechazada => 'Rechazada',
    EstadoDeTransferencia.cancelada => 'Cancelada',
  };

  static const glifoPorAutorizar = '◷';
  static const glifoAutorizada = '✓';
  static const glifoRechazada = '✕';
  static const glifoCancelada = '–';

  /// «Salud y Hogar × 2» o, con varias líneas, «Salud y Hogar × 2 y 1 más».
  static String resumenDeLineas(List<(String nombre, int cantidad)> lineas) {
    if (lineas.isEmpty) return sinLineas;
    final (nombre, cantidad) = lineas.first;
    final primera = '$nombre × $cantidad';
    return lineas.length == 1 ? primera : '$primera y ${lineas.length - 1} más';
  }

  /// A confirmar (mapa §2: texto): una transferencia cuyas líneas todavía no bajaron del servidor.
  static const sinLineas = 'Materiales sin detallar';

  /// A confirmar (mapa §2: texto): el producto de la línea no está en el catálogo del teléfono.
  static const materialSinNombre = 'Material';

  /// La línea chica de arriba de cada fila («HOY · LE PEDISTE A ANA PEREIRA»).
  ///
  /// El canvas dibuja «LE PEDISTE A …» (la pidió quien ve) y «TE PIDIÓ …» (le piden a quien ve). Las
  /// otras (la que arma la coordinadora, o la que alguien ofrece) son a confirmar (mapa §2: texto).
  static String lineaDeArriba(
    DateTime cuando,
    DateTime ahora,
    String quien,
    CaraDeLaTransferencia cara,
  ) => '${_diaCorto(cuando, ahora)} · ${textoDeLaCara(cara, quien)}'.toUpperCase();

  static String textoDeLaCara(CaraDeLaTransferencia cara, String quien) => switch (cara) {
    CaraDeLaTransferencia.lePediste => 'Le pediste a $quien',
    CaraDeLaTransferencia.tePidio => 'Te pidió $quien',
    CaraDeLaTransferencia.leOfreciste => 'Le ofreciste a $quien',
    CaraDeLaTransferencia.teOfrecio => 'Te ofreció $quien',
    CaraDeLaTransferencia.paraVos => 'Tu coordinadora la armó: te entrega $quien',
    CaraDeLaTransferencia.entregasA => 'Tu coordinadora la armó: le entregás a $quien',
  };

  /// Sin el nombre de la otra punta (el servidor no lo da a este teléfono, ver
  /// [CompanierosDeCampaniaSinFuente]): a confirmar (mapa §2: texto).
  static const otroColportor = 'otro colportor';

  // --- 40B·02..07 · El detalle ----------------------------------------------------------------

  static const eyebrowDetalle = 'TRANSFERENCIA';
  static const pide = 'Pide';
  static const entrega = 'Entrega';
  static const pedida = 'Pedida';

  /// A confirmar (mapa §2: texto): el canvas dice «Juan Duarte (vos)», pero el teléfono solo guarda el nombre
  /// de pila; se dice «Vos».
  static const vos = 'Vos';
  static const cancelarTransferencia = 'Cancelar transferencia';
  static const pedirOtraTransferencia = 'Pedir otra';
  static const volverAtras = 'Volver';

  /// El eyebrow del detalle: «TRANSFERENCIA DE HOY», «DE AYER» o «DEL 15/10».
  static String eyebrowDelDetalle(DateTime cuando, DateTime ahora) {
    final d = ReglasDeVenta.diaDeMontevideo(cuando);
    final h = ReglasDeVenta.diaDeMontevideo(ahora);
    final dias = h.difference(d).inDays;
    return switch (dias) {
      0 => 'TRANSFERENCIA DE HOY',
      1 => 'TRANSFERENCIA DE AYER',
      _ => 'TRANSFERENCIA DEL ${_dd(d.day)}/${_dd(d.month)}',
    };
  }

  /// «hoy 14:35», «ayer 09:12» o «15/10 09:12» (hora de Montevideo).
  static String cuando(DateTime instante, DateTime ahora) {
    final m = _montevideo(instante);
    final h = hora(instante);
    final dias = ReglasDeVenta.diaDeMontevideo(
      ahora,
    ).difference(ReglasDeVenta.diaDeMontevideo(instante)).inDays;
    return switch (dias) {
      0 => 'hoy $h',
      1 => 'ayer $h',
      _ => '${_dd(m.day)}/${_dd(m.month)} $h',
    };
  }

  static String hora(DateTime instante) {
    final m = _montevideo(instante);
    return '${_dd(m.hour)}:${_dd(m.minute)}';
  }

  /// Un renglón del subtítulo del detalle: el estado y, si se decidió, cuándo.
  static String subtituloDelDetalle(
    Transferencia t, {
    required String quien,
    required CaraDeLaTransferencia cara,
  }) {
    final estadoTexto = estado(t.estado, enCola: t.enCola);
    return switch (t.estado) {
      EstadoDeTransferencia.autorizada when t.decididoEn != null =>
        'Autorizada el ${_diaYHora(t.decididoEn!)}',
      EstadoDeTransferencia.rechazada when t.decididoEn != null =>
        'Rechazada el ${_diaYHora(t.decididoEn!)}',
      _
          when cara == CaraDeLaTransferencia.tePidio &&
              t.estado == EstadoDeTransferencia.porAutorizar =>
        'Te la pidió $quien · por autorizar',
      _ => estadoTexto,
    };
  }

  /// 40B·02.
  static const porAutorizarPedida = 'Tu coordinadora todavía no la autorizó.';

  /// A confirmar (mapa §2: texto): la que sigue en la cola de este teléfono (40A·07).
  static const enColaEnElDetalle =
      'Todavía no salió de tu teléfono. Sube sola cuando haya conexión.';

  /// 40B·05: [quien] es quien entrega.
  static String autorizada(String quien) =>
      'Tu coordinadora la autorizó. Coordiná con $quien la entrega.';

  /// A confirmar (mapa §2: texto): la que arma la coordinadora, vista por quien entrega o recibe.
  static const autorizadaSinPedirla =
      'Tu coordinadora la autorizó. Coordiná la entrega con la otra punta.';

  /// 40B·06: el motivo lo escribe la coordinadora (obligatorio, HU-STK-006).
  static String rechazada(String? motivo) => motivo == null || motivo.trim().isEmpty
      ? 'Tu coordinadora no la autorizó.'
      : 'Tu coordinadora no la autorizó: «${motivo.trim()}».';

  /// 40B·07: lo que ve quien entrega, con lo que tiene hoy. [tiene] es `null` si no se sabe.
  static String teLaPidenPorAutorizar(int? tiene) => tiene == null
      ? 'Si tu coordinadora la autoriza, salen de lo que tenés.'
      : 'Si tu coordinadora la autoriza, salen de lo que tenés. Hoy tenés $tiene.';

  /// 40B·04 / 40B·03: la cancelada.
  static const canceladaAviso = 'La cancelaron: nadie tiene que hacer nada.';

  static const transferenciaCancelada = 'Transferencia cancelada.';

  /// 40B·03: la hoja de confirmación.
  static const cancelarTitulo = '¿Cancelar la transferencia?';
  static String cancelarTexto(String quien) =>
      '$quien y tu coordinadora dejan de verla como pendiente. Si la necesitás después, la pedís de nuevo.';
  static const cancelarSi = 'Cancelar transferencia';
  static const cancelarNo = 'Volver';

  /// A confirmar (mapa §2: texto): el detalle de una transferencia que ya no está en el teléfono.
  static const sinLaTransferencia =
      'Esta transferencia ya no está en tu teléfono. Volvé atrás y elegí otra.';

  /// A confirmar (mapa §2: texto): se quiso cancelar y la coordinadora ya la había decidido.
  static const yaNoSePuedeCancelar = 'Tu coordinadora ya la decidió: ya no se puede cancelar.';

  static const cancelando = 'Cancelando…';

  // --- Auxiliares -----------------------------------------------------------------------------

  static String _dd(int n) => n.toString().padLeft(2, '0');

  static DateTime _montevideo(DateTime instante) =>
      instante.toUtc().subtract(const Duration(hours: 3));

  static String _diaYHora(DateTime instante) {
    final m = _montevideo(instante);
    return '${_dd(m.day)}/${_dd(m.month)} · ${hora(instante)}';
  }

  /// «HOY», «AYER» o «15/10» (día de Montevideo), para la línea de arriba de la fila.
  static String _diaCorto(DateTime cuando, DateTime ahora) {
    final d = ReglasDeVenta.diaDeMontevideo(cuando);
    final h = ReglasDeVenta.diaDeMontevideo(ahora);
    return switch (h.difference(d).inDays) {
      0 => 'hoy',
      1 => 'ayer',
      _ => '${_dd(d.day)}/${_dd(d.month)}',
    };
  }

  /// «ayer a las 21:00», «hoy a las 07:05» o «el 28/10 a las 09:00».
  static String _cuandoYHora(DateTime instante, DateTime ahora) {
    final d = ReglasDeVenta.diaDeMontevideo(instante);
    final h = ReglasDeVenta.diaDeMontevideo(ahora);
    final cuando = switch (h.difference(d).inDays) {
      0 => 'hoy',
      1 => 'ayer',
      _ => 'el ${_dd(d.day)}/${_dd(d.month)}',
    };
    return '$cuando a las ${hora(instante)}';
  }
}

/// Desde dónde la ve el colportor: quién la pidió y quién da o recibe. Decide la línea de arriba de la
/// fila y el aviso del detalle.
enum CaraDeLaTransferencia {
  /// La pidió quien la ve (recibe): «Le pediste a Ana».
  lePediste,

  /// Se la piden a quien la ve (entrega): «Te pidió Bruno».
  tePidio,

  /// La ofreció quien la ve (entrega, la pidió él): «Le ofreciste a Ana».
  leOfreciste,

  /// Se la ofrecen a quien la ve (recibe): «Te ofreció Bruno».
  teOfrecio,

  /// La armó la coordinadora y quien la ve recibe.
  paraVos,

  /// La armó la coordinadora y quien la ve entrega.
  entregasA;

  /// La cara de [t] para [usuarioId].
  static CaraDeLaTransferencia de(Transferencia t, String usuarioId) {
    final recibe = t.destinoId == usuarioId;
    if (t.laPidio(usuarioId)) return recibe ? lePediste : leOfreciste;
    if (t.solicitanteId != null) return recibe ? teOfrecio : tePidio;
    return recibe ? paraVos : entregasA;
  }
}
