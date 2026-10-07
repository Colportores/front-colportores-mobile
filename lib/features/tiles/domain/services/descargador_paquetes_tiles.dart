import 'dart:async';
import 'dart:math';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/estado_descarga.dart';
import '../entities/paquete_tiles.dart';
import '../repositories/paquetes_tiles_repository.dart';
import 'puertos_descarga.dart';

/// Descarga paquetes PMTiles al directorio de la app (HU-SYNC-010, ADR-011).
///
/// Reglas:
/// - Solo con Wi-Fi, salvo que el colportor autorice datos móviles para esa descarga. Sin red o
///   con datos móviles sin autorizar, [descargar] devuelve `Left` sin tocar nada, salvo con
///   `esperarConexion`: entonces la descarga queda **en cola** (en pausa, `sigueSola`) y arranca
///   sola con la primera conexión permitida.
/// - Antes de arrancar compara el espacio libre con lo que falta bajar (más lo que les falta a las
///   otras descargas en curso): si no alcanza, `Left(FailureEspacioInsuficiente)`.
/// - Un paquete tiene una o más partes (una ciudad grande se parte en dos archivos). Baja las
///   partes de a una, cada una a su `.part`. Reanudar pide desde el tamaño del `.part` (HTTP
///   Range); si el servidor no soporta `Range` y manda el archivo entero (200 en vez de 206), el
///   `.part` se reescribe.
/// - Un 416 con `.part` borra el `.part` y pide una vez más desde cero. Un 206 con otro rango que
///   el pedido falla con `FailureServidor(status: 206)`.
/// - Cada parte se valida al terminar de bajar (tamaño y SHA-256 del catálogo): una parte corrupta
///   se borra y la descarga falla sin bajar las que faltan. Con todas las partes validadas se
///   renombran sus `.part` a `.pmtiles` y se registra el paquete en el repositorio: desde ahí el
///   mapa lo usa. Un corte nunca deja un archivo que se tome por válido ni un paquete a medias.
/// - Si se va el Wi-Fi (sin datos móviles autorizados) o se corta la red, queda en pausa y sigue
///   sola cuando vuelve una conexión permitida. La pausa del colportor ([pausar]) la levanta él
///   llamando otra vez a [descargar].
/// - Un corte sin cambio de conectividad (el servidor cerró la conexión con el Wi-Fi arriba) queda
///   en la misma pausa (`sinConexion`, `sigueSola`) y reintenta solo mientras la conexión siga
///   permitida: espera 30 s, 1 min, 2 min y 5 min, y de ahí cada 5 min, sin tope de intentos con
///   la app abierta. Un cambio de conectividad permitido reintenta ya y vuelve a empezar en 30 s;
///   pausar, eliminar, cerrar o perder la conexión permitida cancelan la espera.
///
/// Guarda el estado de las descargas en memoria: va una sola instancia por app (el provider la
/// mantiene viva) y escucha la conectividad desde la primera descarga hasta [cerrar].
final class DescargadorPaquetesTiles {
  DescargadorPaquetesTiles({
    required this._conectividad,
    required this._espacio,
    required this._cliente,
    required this._archivos,
    required this._checksum,
    required this._repository,
    List<Duration> esperasDeReintento = esperasDeReintentoPorDefecto,
  }) : assert(esperasDeReintento.isNotEmpty, 'hace falta al menos una espera'),
       _esperasDeReintento = esperasDeReintento;

  /// Cuánto espera antes de cada reintento de una descarga cortada; la última se repite.
  static const esperasDeReintentoPorDefecto = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  final MonitorConectividad _conectividad;
  final MedidorEspacioDisco _espacio;
  final ClienteDescargaRango _cliente;
  final ArchivosTiles _archivos;
  final CalculadorChecksum _checksum;
  final PaquetesTilesRepository _repository;
  final List<Duration> _esperasDeReintento;

  final _descargas = <String, _Descarga>{};
  final _cambios = StreamController<EstadoDescarga>.broadcast();
  StreamSubscription<TipoConexion>? _escuchaConectividad;

  /// Cada cambio de estado de cualquier descarga.
  Stream<EstadoDescarga> get cambios => _cambios.stream;

  /// El último estado de la descarga de [paqueteId]; `null` si no se descargó en esta sesión.
  EstadoDescarga? estadoDe(String paqueteId) => _descargas[paqueteId]?.estado;

  /// Termina cuando termina el intento en curso de [paqueteId] (completo, en pausa o fallido).
  Future<void> esperar(String paqueteId) async {
    await _descargas[paqueteId]?.intento?.future;
  }

  /// Arranca o reanuda la descarga de [paquete].
  ///
  /// `Left` sin tocar nada si no se puede arrancar: sin red ([FailureSinConexion]), con datos
  /// móviles sin [permitirDatosMoviles] ([FailureDescargaRequiereWifi]) o sin espacio
  /// ([FailureEspacioInsuficiente]). Con [esperarConexion] la falta de red o de Wi-Fi no es un
  /// error: la descarga queda en cola y arranca sola con la primera conexión permitida (el toque
  /// de «Descargar mapa» es el override manual: [permitirDatosMoviles] y [esperarConexion] juntos;
  /// lo que la app baja sola espera el Wi-Fi: solo [esperarConexion]). `Right` si arrancó o quedó
  /// en cola: el progreso y el final llegan por [cambios].
  ///
  /// Si ya está en curso no hace nada (salvo darle el permiso de datos móviles si lo trae el
  /// llamado). Si ya está en cola, no se encola otra: una llamada de la app no le quita el
  /// permiso que dio el colportor. Si ya estaba descargado lo baja de nuevo (sirve para pasar a
  /// otra versión del catálogo).
  Future<Either<Failure, Unit>> descargar(
    PaqueteTiles paquete, {
    bool permitirDatosMoviles = false,
    bool esperarConexion = false,
  }) {
    // Un pedido del colportor (o de la app) empieza de nuevo la cuenta de los reintentos.
    _descargas[paquete.id]?.reintentosSeguidos = 0;
    return _descargar(
      paquete,
      permitirDatosMoviles: permitirDatosMoviles,
      esperarConexion: esperarConexion,
    );
  }

  Future<Either<Failure, Unit>> _descargar(
    PaqueteTiles paquete, {
    required bool permitirDatosMoviles,
    required bool esperarConexion,
  }) async {
    final previa = _descargas[paquete.id];
    if (previa != null && previa.ocupada) {
      if (permitirDatosMoviles) previa.permitirDatosMoviles = true;
      return const Right(unit);
    }
    final descarga = previa ?? _Descarga(paquete);
    descarga.cancelarReintento();
    final enCola = switch (previa?.estado) {
      DescargaPausada(sigueSola: true) => true,
      _ => false,
    };
    final intento = Completer<void>();
    descarga
      ..paquete = paquete
      ..permitirDatosMoviles = permitirDatosMoviles || (enCola && descarga.permitirDatosMoviles)
      ..esperarConexion = esperarConexion || (enCola && descarga.esperarConexion)
      ..pausaPedida = null
      ..intento = intento;
    _descargas[paquete.id] = descarga;
    Failure? bloqueo;
    try {
      bloqueo = await _preparar(descarga);
    } on Object catch (e) {
      bloqueo = FailureInesperado(causa: e);
    }
    if (bloqueo != null) {
      final sinConexion = bloqueo is FailureSinConexion;
      if (descarga.esperarConexion && (sinConexion || bloqueo is FailureDescargaRequiereWifi)) {
        _ponerEnCola(descarga, sinConexion ? MotivoPausa.sinConexion : MotivoPausa.sinWifi);
        intento.complete();
        _escucharConectividad();
        return const Right(unit);
      }
      intento.complete();
      if (previa == null) _descargas.remove(paquete.id);
      return Left(bloqueo);
    }
    _escucharConectividad();
    unawaited(_transferir(descarga, intento));
    return const Right(unit);
  }

  /// Pausa la descarga de [paqueteId] y deja los `.part` para reanudarla con [descargar]. Si
  /// estaba en pausa esperando la conexión, deja de seguir sola. Si ya terminó de bajar y está
  /// validando el checksum (`DescargaVerificando`), no la corta: termina en `DescargaCompletada`
  /// (o `DescargaFallida` si el checksum no coincide).
  Future<void> pausar(String paqueteId) async {
    final descarga = _descargas[paqueteId];
    if (descarga == null) return;
    if (descarga.ocupada) return _detener(descarga, MotivoPausa.usuario);
    if (descarga.estado is DescargaPausada) _emitirPausa(descarga, MotivoPausa.usuario);
    descarga.cancelarReintento();
  }

  /// Elimina el paquete [paqueteId] (HU-SYNC-010: de a uno, para liberar espacio). Corta la
  /// descarga si estaba en curso, lo saca del repositorio (el mapa deja de usarlo) y borra todos
  /// sus `.part` y `.pmtiles`, de cualquier versión. Si falla a mitad, se puede repetir.
  Future<Either<Failure, Unit>> eliminar(String paqueteId) async {
    final descarga = _descargas.remove(paqueteId);
    if (descarga != null) await _detener(descarga, MotivoPausa.usuario);
    final quitado = await _repository.quitar(paqueteId);
    if (quitado.isLeft()) return quitado;
    try {
      final propios = RegExp(
        '^${RegExp.escape(paqueteId)}-p\\d+-[0-9a-f]{1,12}\\.pmtiles(\\.part)?\$',
      );
      for (final archivo in await _archivos.listar()) {
        if (propios.hasMatch(archivo.nombre)) await _archivos.borrar(archivo.ruta);
      }
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e));
    }
    if (!_cambios.isClosed) _cambios.add(DescargaEliminada(paqueteId));
    return const Right(unit);
  }

  /// Corta las descargas en curso (los `.part` quedan para la próxima) y deja de escuchar la
  /// conectividad.
  Future<void> cerrar() async {
    // Antes de cualquier espera: un reintento que vence mientras se cierra no arranca otro intento.
    for (final descarga in _descargas.values) {
      descarga.cancelarReintento();
    }
    await _escuchaConectividad?.cancel();
    _escuchaConectividad = null;
    for (final descarga in _descargas.values.toList()) {
      await _detener(descarga, MotivoPausa.usuario);
    }
    await _cambios.close();
  }

  /// Deja en `bytes` lo que ya hay en cada `.part` y chequea conexión y espacio. Devuelve por qué
  /// no se puede arrancar, o `null`.
  Future<Failure?> _preparar(_Descarga d) async {
    final paquete = d.paquete;
    final yaBajados = <int>[];
    for (var i = 0; i < paquete.partes.length; i++) {
      final enDisco = await _archivos.tamano(_archivos.rutaParcial(paquete.claveDeParte(i)));
      // Un `.part` más grande que la parte no sirve para reanudar: se reescribe desde cero.
      yaBajados.add(enDisco > paquete.partes[i].tamanoBytes ? 0 : enDisco);
    }
    d.bytes = yaBajados;
    final conexion = await _conectividad.actual();
    final bloqueo = _bloqueoPor(conexion, datosMoviles: d.permitirDatosMoviles);
    if (bloqueo != null) return bloqueo;
    final faltan = paquete.tamanoBytes - d.recibidos;
    final libres = await _espacio.bytesLibres() - _faltanDeLasOtras(paquete.id);
    if (libres < faltan) {
      return FailureEspacioInsuficiente(megabytesRequeridos: megabytesDe(faltan));
    }
    return null;
  }

  int _faltanDeLasOtras(String paqueteId) {
    var total = 0;
    for (final otra in _descargas.values) {
      if (otra.paquete.id == paqueteId || !otra.ocupada) continue;
      total += otra.paquete.tamanoBytes - otra.recibidos;
    }
    return total;
  }

  /// Baja y valida cada parte, y deja el paquete disponible.
  Future<void> _transferir(_Descarga d, Completer<void> intento) async {
    final paquete = d.paquete;
    try {
      for (var i = 0; i < paquete.partes.length; i++) {
        if (!await _completarParte(d, i)) return;
      }
      // Todas validadas: recién ahora los `.part` pasan a `.pmtiles`.
      final rutas = <String>[];
      for (var i = 0; i < paquete.partes.length; i++) {
        final clave = paquete.claveDeParte(i);
        final destino = _archivos.rutaFinal(clave);
        await _archivos.renombrar(_archivos.rutaParcial(clave), destino);
        rutas.add(destino);
      }
      final descargado = PaqueteDescargado(paquete: paquete, rutas: rutas);
      final registro = await _repository.registrar(descargado);
      final estado = registro.fold<EstadoDescarga>(
        (failure) => DescargaFallida(paquete.id, failure),
        (_) => DescargaCompletada(descargado),
      );
      _emitir(d, estado);
    } on ErrorServidorTiles catch (e) {
      _emitir(d, DescargaFallida(paquete.id, FailureServidor(status: e.status)));
    } on ErrorEspacioTiles {
      final faltan = paquete.tamanoBytes - d.recibidos;
      final failure = FailureEspacioInsuficiente(megabytesRequeridos: megabytesDe(faltan));
      _emitir(d, DescargaFallida(paquete.id, failure));
    } on Object catch (e) {
      _emitir(d, DescargaFallida(paquete.id, FailureInesperado(causa: e)));
    } finally {
      intento.complete();
    }
  }

  /// Baja lo que falta de la parte [indice] y la valida. `true` si quedó entera y válida; `false`
  /// si quedó en pausa o falló (el estado ya se emitió).
  Future<bool> _completarParte(_Descarga d, int indice) async {
    final paquete = d.paquete;
    final parte = paquete.partes[indice];
    final parcial = _archivos.rutaParcial(paquete.claveDeParte(indice));
    if (d.bytes[indice] < parte.tamanoBytes && !await _bajar(d, indice, parcial)) return false;
    // Una pausa pedida desde acá no corta: la validación sigue y termina en completada o
    // fallida (o, si no es la última parte, en la pausa al empezar la que sigue).
    if (indice == paquete.partes.length - 1) _emitir(d, DescargaVerificando(paquete.id));
    final enDisco = await _archivos.tamano(parcial);
    final calculado = enDisco == parte.tamanoBytes ? await _checksum.calcular(parcial) : null;
    if (calculado == null || _normalizado(calculado) != _normalizado(parte.sha256)) {
      await _archivos.borrar(parcial);
      d.bytes[indice] = 0;
      _emitir(d, DescargaFallida(paquete.id, const FailurePaqueteTilesCorrupto()));
      return false;
    }
    return true;
  }

  /// Baja al `.part` de la parte [indice] lo que falta. `true` si llegó entera; `false` si quedó
  /// en pausa o falló (el estado ya se emitió).
  Future<bool> _bajar(_Descarga d, int indice, String parcial) async {
    final paquete = d.paquete;
    if (d.pausaPedida case final motivo?) {
      _emitirPausa(d, motivo);
      return false;
    }
    final RespuestaDescarga respuesta;
    try {
      respuesta = await _pedir(d, indice, parcial);
    } on ErrorRedTiles {
      _emitirPausa(d, d.pausaPedida ?? MotivoPausa.sinConexion);
      _reintentarMasTarde(d);
      return false;
    }
    if (d.pausaPedida case final motivo?) {
      await respuesta.bytes.listen(null).cancel();
      _emitirPausa(d, motivo);
      return false;
    }
    if (respuesta.desde != 0 && respuesta.desde != d.bytes[indice]) {
      // Un 206 con otro rango que el pedido no se puede anexar: se descarta y falla como error
      // del servidor.
      await respuesta.bytes.listen(null).cancel();
      throw const ErrorServidorTiles(206);
    }
    // Con 200 (sin soporte de Range) llega el archivo entero: el `.part` se reescribe desde cero.
    final anexar = respuesta.desde > 0;
    if (!anexar) d.bytes[indice] = 0;
    final escritura = await _archivos.abrir(parcial, anexar: anexar);
    _emitir(d, DescargaEnCurso(paquete.id, recibidos: d.recibidos, total: paquete.tamanoBytes));
    final _Fin fin;
    try {
      fin = await _recibir(d, indice, respuesta.bytes, escritura);
    } on Object {
      // Una escritura falló (disco lleno, por ejemplo): se cierra el archivo y el error sale.
      try {
        await escritura.cerrar();
      } on Object {
        // Es el mismo error: sale el primero.
      }
      rethrow;
    }
    await escritura.cerrar();
    switch (fin) {
      case _Fin.completo:
        return true;
      case _Fin.cortado:
        _emitirPausa(d, MotivoPausa.sinConexion);
        _reintentarMasTarde(d);
      case _Fin.pausado:
        _emitirPausa(d, d.pausaPedida ?? MotivoPausa.usuario);
      case _Fin.excedido:
        await _archivos.borrar(parcial);
        d.bytes[indice] = 0;
        _emitir(d, DescargaFallida(paquete.id, const FailurePaqueteTilesCorrupto()));
    }
    return false;
  }

  /// Pide lo que falta de la parte [indice]. Un 416 con `.part` (el archivo cambió en el servidor,
  /// o el `.part` no es de este archivo) borra el `.part` y pide una sola vez más, desde cero.
  Future<RespuestaDescarga> _pedir(_Descarga d, int indice, String parcial) async {
    final origen = d.paquete.partes[indice].origen;
    try {
      return await _cliente.pedir(origen, desde: d.bytes[indice]);
    } on ErrorServidorTiles catch (e) {
      if (e.status != 416 || d.bytes[indice] == 0) rethrow;
      await _archivos.borrar(parcial);
      d.bytes[indice] = 0;
      return _cliente.pedir(origen, desde: 0);
    }
  }

  /// Escribe los pedazos en el `.part` hasta que el cuerpo termina, se corta, se pasa del tamaño
  /// de la parte o alguien corta la bajada (`_Descarga.cortar`). Espera a que cada pedazo salga al
  /// disco antes de pedir el que sigue (contrapresión). Si una escritura falla, lanza.
  Future<_Fin> _recibir(
    _Descarga d,
    int indice,
    Stream<List<int>> bytes,
    EscrituraArchivo escritura,
  ) async {
    final tamano = d.paquete.partes[indice].tamanoBytes;
    final fin = Completer<_Fin>();
    void terminar(_Fin motivo) {
      if (!fin.isCompleted) fin.complete(motivo);
    }

    late final StreamSubscription<List<int>> suscripcion;
    suscripcion = bytes.listen(
      (pedazo) async {
        if (fin.isCompleted) return;
        suscripcion.pause();
        try {
          await escritura.agregar(pedazo);
        } on Object catch (e, st) {
          if (!fin.isCompleted) fin.completeError(e, st);
          return;
        }
        if (fin.isCompleted) return;
        d.bytes[indice] += pedazo.length;
        if (d.bytes[indice] > tamano) {
          terminar(_Fin.excedido);
          return;
        }
        _emitir(
          d,
          DescargaEnCurso(d.paquete.id, recibidos: d.recibidos, total: d.paquete.tamanoBytes),
        );
        suscripcion.resume();
      },
      onError: (Object _) => terminar(_Fin.cortado),
      onDone: () => terminar(d.bytes[indice] == tamano ? _Fin.completo : _Fin.cortado),
      cancelOnError: true,
    );
    d.cortar = terminar;
    if (d.pausaPedida != null) terminar(_Fin.pausado);
    try {
      return await fin.future;
    } finally {
      d.cortar = null;
      await suscripcion.cancel();
    }
  }

  /// Corta el intento en curso de [d] con una pausa por [motivo] y espera a que cierre el `.part`.
  /// Una pausa del colportor no se pisa: si mientras se cierra se va la red, sigue siendo suya y
  /// no se retoma sola.
  Future<void> _detener(_Descarga d, MotivoPausa motivo) async {
    if (d.pausaPedida != MotivoPausa.usuario) d.pausaPedida = motivo;
    d.cancelarReintento();
    d.cortar?.call(_Fin.pausado);
    await d.intento?.future;
  }

  void _escucharConectividad() {
    _escuchaConectividad ??= _conectividad.cambios.listen(_alCambiarConexion);
  }

  void _alCambiarConexion(TipoConexion conexion) {
    for (final d in _descargas.values.toList()) {
      final permitida = _bloqueoPor(conexion, datosMoviles: d.permitirDatosMoviles) == null;
      if (d.ocupada) {
        if (!permitida) unawaited(_detener(d, _motivoPorPerder(conexion)));
      } else if (!permitida) {
        // Sin una conexión permitida no hay a qué reintentar: vuelve con el próximo cambio.
        d.cancelarReintento();
      } else if (d.estado case DescargaPausada(sigueSola: true)) {
        // Una conexión permitida reintenta ya, y la espera de los reintentos vuelve a ser la corta.
        d.cancelarReintento();
        d.reintentosSeguidos = 0;
        unawaited(_reanudarSola(d));
      }
    }
  }

  Future<void> _reanudarSola(_Descarga d) async {
    final resultado = await _descargar(
      d.paquete,
      permitirDatosMoviles: d.permitirDatosMoviles,
      esperarConexion: d.esperarConexion,
    );
    final failure = resultado.fold<Failure?>((f) => f, (_) => null);
    // Si la conexión se volvió a ir, sigue en pausa esperando la próxima.
    final sigueEnPausa = failure is FailureSinConexion || failure is FailureDescargaRequiereWifi;
    if (failure != null && !sigueEnPausa) _emitir(d, DescargaFallida(d.paquete.id, failure));
  }

  /// Una descarga que se cortó sin que cambiara la conectividad (el servidor cerró la conexión con
  /// el Wi-Fi arriba) no tiene qué la despierte: reintenta sola con una espera creciente (30 s,
  /// 1 min, 2 min, 5 min y de ahí cada 5 min). Si la pausa la pidió alguien (el colportor o la
  /// pérdida de la conexión) no se reintenta: la levanta él o el próximo cambio de conectividad.
  void _reintentarMasTarde(_Descarga d) {
    if (d.pausaPedida != null) return;
    d.cancelarReintento();
    final indice = min(d.reintentosSeguidos, _esperasDeReintento.length - 1);
    d.reintentosSeguidos++;
    d.reintento = Timer(_esperasDeReintento[indice], () {
      d.reintento = null;
      unawaited(_reintentarSola(d));
    });
  }

  /// Vence la espera: si sigue en la pausa del corte, vuelve a pedir lo que falta. Si en el medio
  /// se fue la conexión permitida, no pide nada: el próximo cambio de conectividad la retoma.
  Future<void> _reintentarSola(_Descarga d) async {
    if (d.ocupada || _cambios.isClosed) return;
    if (d.estado case DescargaPausada(motivo: MotivoPausa.sinConexion)) await _reanudarSola(d);
  }

  /// Anota la descarga como en cola, en pausa por [motivo]. Si ya estaba así no emite otra vez: un
  /// segundo toque no encola nada nuevo.
  void _ponerEnCola(_Descarga d, MotivoPausa motivo) {
    final actual = d.estado;
    if (actual is DescargaPausada && actual.motivo == motivo) return;
    _emitirPausa(d, motivo);
  }

  void _emitirPausa(_Descarga d, MotivoPausa motivo) {
    final pausa = DescargaPausada(
      d.paquete.id,
      motivo: motivo,
      recibidos: d.recibidos,
      total: d.paquete.tamanoBytes,
    );
    _emitir(d, pausa);
  }

  void _emitir(_Descarga d, EstadoDescarga estado) {
    d.estado = estado;
    // La espera de un reintento solo tiene sentido mientras siga la pausa por corte.
    final pausaPorCorte = estado is DescargaPausada && estado.motivo == MotivoPausa.sinConexion;
    if (!pausaPorCorte) d.cancelarReintento();
    if (estado is DescargaCompletada) d.reintentosSeguidos = 0;
    if (!_cambios.isClosed) _cambios.add(estado);
  }

  static Failure? _bloqueoPor(TipoConexion conexion, {required bool datosMoviles}) {
    return switch (conexion) {
      TipoConexion.wifi => null,
      TipoConexion.datosMoviles => datosMoviles ? null : const FailureDescargaRequiereWifi(),
      TipoConexion.sinConexion => const FailureSinConexion(),
    };
  }

  /// Los checksums se comparan en hex minúscula, sin espacios, para que un hex en mayúsculas no
  /// cuente como distinto.
  static String _normalizado(String checksum) => checksum.trim().toLowerCase();

  static MotivoPausa _motivoPorPerder(TipoConexion conexion) => switch (conexion) {
    TipoConexion.sinConexion => MotivoPausa.sinConexion,
    _ => MotivoPausa.sinWifi,
  };
}

/// Cómo terminó la bajada de bytes de un intento.
enum _Fin { completo, cortado, pausado, excedido }

/// Lo que el descargador sabe de la descarga de un paquete.
final class _Descarga {
  _Descarga(this.paquete);

  PaqueteTiles paquete;
  bool permitirDatosMoviles = false;

  /// Si no se puede arrancar por falta de conexión, queda en cola en vez de fallar.
  bool esperarConexion = false;
  EstadoDescarga? estado;

  /// Bytes que ya están en el `.part` de cada parte.
  List<int> bytes = const [];

  /// Bytes que ya están en los `.part` de todas las partes.
  int get recibidos => bytes.fold(0, (suma, parte) => suma + parte);

  /// El intento en curso (preparar, bajar y validar); completado si no hay ninguno.
  Completer<void>? intento;

  /// Corta la bajada de bytes en curso; `null` si no está bajando.
  void Function(_Fin fin)? cortar;

  /// La pausa pedida mientras el intento seguía en curso.
  MotivoPausa? pausaPedida;

  /// La espera del próximo reintento de una descarga cortada; `null` si no hay ninguna.
  Timer? reintento;

  /// Cuántos reintentos seguidos se programaron desde el último pedido o cambio de conectividad:
  /// elige la espera del próximo.
  int reintentosSeguidos = 0;

  void cancelarReintento() {
    reintento?.cancel();
    reintento = null;
  }

  bool get ocupada {
    final actual = intento;
    return actual != null && !actual.isCompleted;
  }
}
