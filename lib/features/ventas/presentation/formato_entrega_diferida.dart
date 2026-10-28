import '../../agenda/domain/services/recordatorios.dart' show ResultadoRecordatorio;
import '../../agenda/presentation/formato_agendar_visita.dart';
import '../domain/entities/entrega_pendiente.dart';

/// Los textos de la entrega diferida y de «Entregas pendientes» (vista 27, grupo C, HU-VEN-003,
/// 27C·01 a 27C·08): los del canvas tal cual, y los que el canvas no dibuja, que dicen qué pasa y qué
/// hacer y quedan marcados en el PR como «para confirmar» (mapa §2: texto/aviso).
abstract final class TextosEntregaDiferida {
  // --- Del canvas ---
  // 27C·01
  static const tituloOtroDia = 'Entregar otro día';
  static const queEntregas = 'QUÉ ENTREGÁS';
  static const fechaPrevista = 'FECHA PREVISTA';
  static const agendamosLaVisita =
      'Agendamos una visita de entrega para ese día, con recordatorio.';
  static const guardarEntrega = 'Guardar entrega';
  // 27C·02
  static const eyebrowVentas = 'VENTAS';
  static const tituloPendientes = 'Entregas pendientes';
  static const atrasadas = 'ATRASADAS';
  static const proximas = 'PRÓXIMAS';
  static const sinFecha = 'SIN FECHA';
  static const ponerFecha = 'Poner fecha';
  // 27C·03 y 27C·04
  static const tituloMarcar = 'Marcar entregado';
  static const nuevaFecha = 'NUEVA FECHA';
  static const placeholderNuevaFecha = 'Sin fecha';
  // 27C·05 y 27C·07
  static const sinPendientes = 'No tenés entregas pendientes';
  static const noPudimosLeer = 'No pudimos leer tus entregas.';

  // --- Aceptados (mapa §2: texto/aviso), a confirmar ---
  static const reintentar = 'Reintentar';
  static const cargandoPendientes = 'Cargando tus entregas';
  static const cargandoLoVendido = 'Cargando lo que vendiste';
  static const elegirCuando = 'Elegí el día y la hora';
  static const elegiCuando = 'Elegí cuándo vas a entregar.';
  static const sinProductos = 'Esta venta no tiene productos para entregar.';
  static const nadaPendiente = 'Esta venta no tiene nada pendiente de entregar.';
  static const productoSinNombre = 'Producto sin nombre';
  static const personaSinNombre = 'Persona sin nombre';
  static const elegiUnProducto = 'Elegí al menos un producto para marcar como entregado.';
  static const noPudimosLeerLoVendido = 'No pudimos leer qué se vendió. Probá de nuevo.';
  static const entregaMarcada = 'Entrega marcada.';
  static const entregaMarcadaQuedaAlgo = 'Entrega marcada. Lo que falta sigue pendiente.';
  static const yaEstabaEntregada = 'Esa entrega ya estaba marcada como entregada.';
  static const entregadoHoy = 'Entregado hoy';
  static const volver = 'Volver';

  /// El campo de fecha para el lector: «Fecha prevista: sábado 26/10 · 16:30. Tocá para cambiar».
  static String lectorCampo(String rotulo, String valor) =>
      '${rotulo[0]}${rotulo.substring(1).toLowerCase()}: $valor. Tocá para cambiar';

  /// «Nuestros Hijos sigue pendiente. ¿Para cuándo?» (27C·04).
  static String sigueFaltando(List<String> nombres) => nombres.length == 1
      ? '${nombres.single} sigue pendiente. ¿Para cuándo?'
      : '${_lista(nombres)} siguen pendientes. ¿Para cuándo?';

  /// «Marcar 1 entregado» (27C·04) cuando se destilda algo; «Marcar entregado» si va todo.
  static String marcarN(int n, {required bool todo}) =>
      todo ? tituloMarcar : 'Marcar $n ${n == 1 ? 'entregado' : 'entregados'}';

  /// Lo que se confirma al guardar «Entregar otro día»: cuándo y qué pasa con el recordatorio.
  static String entregaGuardada(String cuando, ResultadoRecordatorio? recordatorio) {
    final base = 'Entrega guardada para $cuando.';
    return switch (recordatorio) {
      ResultadoRecordatorio.programado => '$base Te vamos a avisar antes.',
      ResultadoRecordatorio.sinPermiso =>
        '$base Las notificaciones están apagadas: no te va a llegar el recordatorio.',
      ResultadoRecordatorio.apagados =>
        '$base Los recordatorios están apagados: no te vamos a avisar.',
      ResultadoRecordatorio.noSePudo =>
        '$base No pudimos programar el recordatorio. Revisá la entrega en tu agenda.',
      ResultadoRecordatorio.yaPaso || null => '$base La hora ya pasó: no hay recordatorio.',
    };
  }

  static String _lista(List<String> nombres) =>
      '${nombres.sublist(0, nombres.length - 1).join(', ')} y ${nombres.last}';
}

/// Cómo se escriben las fechas y los renglones de las entregas pendientes.
abstract final class FormatoEntregaDiferida {
  /// «Sábado 26/10 · 16:30», o «Hoy · 11:00» / «Mañana · 09:00».
  static String cuando(DateTime fecha, DateTime ahora) =>
      FormatoAgendarVisita.cuando(fecha.toLocal(), ahora.toLocal());

  /// «SÁB 26/10 · 16:30»: el rótulo de la tarjeta de 27C·02.
  static String rotuloDeLaTarjeta(DateTime fecha) {
    final local = fecha.toLocal();
    return '${FormatoAgendarVisita.diaCortoYMes(local).toUpperCase()} · '
        '${FormatoAgendarVisita.hora(local)}';
  }

  /// «Grecia 3310 · Nuestros Hijos × 1» o «Mataojo 2044 · Depto 3B · 2 productos». Con un solo
  /// producto y su nombre se dice cuál; si no se sabe el nombre o son varios, cuántos.
  static String detalleDeLaTarjeta(
    EntregaPendiente entrega, {
    required String direccion,
    required Map<String, String>? nombres,
  }) {
    final lineas = entrega.lineas;
    final String productos;
    final nombre = lineas.length == 1 ? (nombres?[lineas.single.productoId]) : null;
    if (nombre != null) {
      productos = '$nombre × ${lineas.single.cantidad}';
    } else {
      productos = '${lineas.length} ${lineas.length == 1 ? 'producto' : 'productos'}';
    }
    return [direccion, productos].where((t) => t.isNotEmpty).join(' · ');
  }
}
