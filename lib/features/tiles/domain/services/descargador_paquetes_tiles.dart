import 'dart:async';

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
///   con datos móviles sin autorizar, [descargar] devuelve `Left` sin tocar nada.
/// - Antes de arrancar compara el espacio libre con lo que falta bajar (más lo que les falta a las
///   otras descargas en curso): si no alcanza, `Left(FailureEspacioInsuficiente)`.
/// - Baja al `.part`. Reanudar pide desde el tamaño del `.part` (HTTP Range); si el servidor no
///   soporta `Range` y manda el archivo entero (200 en vez de 206), el `.part` se reescribe.
/// - Un 416 con `.part` borra el `.part` y pide una vez más desde cero. Un 206 con otro rango que
///   el pedido falla con `FailureServidor(status: 206)`.
/// - Al terminar valida el checksum. Si coincide, renombra el `.part` al `.pmtiles` y lo registra
///   en el repositorio: desde ahí el mapa lo usa. Si no, borra el `.part`. Un corte nunca deja un
///   archivo que se tome por válido.
/// - Si se va el Wi-Fi (sin datos móviles autorizados) o se corta la red, queda en pausa y sigue
///   sola cuando vuelve una conexión permitida. La pausa del colportor ([pausar]) la levanta él
///   llamando otra vez a [descargar]. Un corte sin cambio de conectividad (el servidor cerró la
///   conexión) también queda en pausa: sigue con el próximo cambio o con [descargar].
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
  });

  final MonitorConectividad _conectividad;
  final MedidorEspacioDisco _espacio;
  final ClienteDescargaRango _cliente;
  final ArchivosTiles _archivos;
  final CalculadorChecksum _checksum;
  final PaquetesTilesRepository _repository;

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
  /// ([FailureEspacioInsuficiente]). `Right` si arrancó: el progreso y el final llegan por
  /// [cambios]. Si ya está en curso no hace nada; si ya estaba descargado lo baja de nuevo (sirve
  /// para pasar a otra versión del catálogo).
  Future<Either<Failure, Unit>> descargar(
    PaqueteTiles paquete, {
    bool permitirDatosMoviles = false,
  }) async {
    final previa = _descargas[paquete.id];
    if (previa != null && previa.ocupada) return const Right(unit);
    final descarga = previa ?? _Descarga(paquete);
    final intento = Completer<void>();
    descarga
      ..paquete = paquete
      ..permitirDatosMoviles = permitirDatosMoviles
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
      intento.complete();
      if (previa == null) _descargas.remove(paquete.id);
      return Left(bloqueo);
    }
    _escucharConectividad();
    unawaited(_transferir(descarga, intento));
    return const Right(unit);
  }

  /// Pausa la descarga de [paqueteId] y deja el `.part` para reanudarla con [descargar]. Si estaba
  /// en pausa esperando la conexión, deja de seguir sola. Si ya terminó de bajar y está validando
  /// el checksum (`DescargaVerificando`), no la corta: termina en `DescargaCompletada` (o
  /// `DescargaFallida` si el checksum no coincide).
  Future<void> pausar(String paqueteId) async {
    final descarga = _descargas[paqueteId];
    if (descarga == null) return;
    if (descarga.ocupada) return _detener(descarga, MotivoPausa.usuario);
    if (descarga.estado is DescargaPausada) _emitirPausa(descarga, MotivoPausa.usuario);
  }

  /// Elimina el paquete [paqueteId] (HU-SYNC-010: de a uno, para liberar espacio). Corta la
  /// descarga si estaba en curso, lo saca del repositorio (el mapa deja de usarlo) y borra el
  /// `.part` y el `.pmtiles`. Si falla a mitad, se puede repetir.
  Future<Either<Failure, Unit>> eliminar(String paqueteId) async {
    final descarga = _descargas.remove(paqueteId);
    if (descarga != null) await _detener(descarga, MotivoPausa.usuario);
    final quitado = await _repository.quitar(paqueteId);
    if (quitado.isLeft()) return quitado;
    try {
      await _archivos.borrar(_archivos.rutaParcial(paqueteId));
      await _archivos.borrar(_archivos.rutaFinal(paqueteId));
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e));
    }
    if (!_cambios.isClosed) _cambios.add(DescargaEliminada(paqueteId));
    return const Right(unit);
  }

  /// Corta las descargas en curso (el `.part` queda para la próxima) y deja de escuchar la
  /// conectividad.
  Future<void> cerrar() async {
    await _escuchaConectividad?.cancel();
    _escuchaConectividad = null;
    for (final descarga in _descargas.values.toList()) {
      await _detener(descarga, MotivoPausa.usuario);
    }
    await _cambios.close();
  }

  /// Chequea conexión y espacio y deja en `recibidos` lo que ya hay en el `.part`. Devuelve por
  /// qué no se puede arrancar, o `null`.
  Future<Failure?> _preparar(_Descarga d) async {
    final conexion = await _conectividad.actual();
    final bloqueo = _bloqueoPor(conexion, datosMoviles: d.permitirDatosMoviles);
    if (bloqueo != null) return bloqueo;
    final paquete = d.paquete;
    final parcial = _archivos.rutaParcial(paquete.id);
    var yaBajados = await _archivos.tamano(parcial);
    if (yaBajados > paquete.tamanoBytes) {
      // Un `.part` más grande que el paquete no sirve para reanudar: se descarta.
      await _archivos.borrar(parcial);
      yaBajados = 0;
    }
    final faltan = paquete.tamanoBytes - yaBajados;
    final libres = await _espacio.bytesLibres() - _faltanDeLasOtras(paquete.id);
    if (libres < faltan) {
      return FailureEspacioInsuficiente(megabytesRequeridos: megabytesDe(faltan));
    }
    d.recibidos = yaBajados;
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

  /// Baja lo que falta, valida el checksum y deja el paquete disponible.
  Future<void> _transferir(_Descarga d, Completer<void> intento) async {
    final paquete = d.paquete;
    final parcial = _archivos.rutaParcial(paquete.id);
    try {
      if (d.recibidos < paquete.tamanoBytes && !await _bajar(d, parcial)) return;
      // Una pausa pedida desde acá no corta: la validación sigue y termina en completada o
      // fallida.
      _emitir(d, DescargaVerificando(paquete.id));
      final calculado = await _checksum.calcular(parcial);
      if (_normalizado(calculado) != _normalizado(paquete.checksum)) {
        await _archivos.borrar(parcial);
        d.recibidos = 0;
        _emitir(d, DescargaFallida(paquete.id, const FailurePaqueteTilesCorrupto()));
        return;
      }
      final destino = _archivos.rutaFinal(paquete.id);
      await _archivos.renombrar(parcial, destino);
      final descargado = PaqueteDescargado(paquete: paquete, ruta: destino);
      final registro = await _repository.registrar(descargado);
      final estado = registro.fold<EstadoDescarga>(
        (failure) => DescargaFallida(paquete.id, failure),
        (_) => DescargaCompletada(descargado),
      );
      _emitir(d, estado);
    } on ErrorServidorTiles catch (e) {
      _emitir(d, DescargaFallida(paquete.id, FailureServidor(status: e.status)));
    } on Object catch (e) {
      _emitir(d, DescargaFallida(paquete.id, FailureInesperado(causa: e)));
    } finally {
      intento.complete();
    }
  }

  /// Baja al `.part` lo que falta. `true` si llegó entero; `false` si quedó en pausa o falló (el
  /// estado ya se emitió).
  Future<bool> _bajar(_Descarga d, String parcial) async {
    final paquete = d.paquete;
    final RespuestaDescarga respuesta;
    try {
      respuesta = await _pedir(d, parcial);
    } on ErrorRedTiles {
      _emitirPausa(d, d.pausaPedida ?? MotivoPausa.sinConexion);
      return false;
    }
    if (d.pausaPedida case final motivo?) {
      await respuesta.bytes.listen(null).cancel();
      _emitirPausa(d, motivo);
      return false;
    }
    if (respuesta.desde != 0 && respuesta.desde != d.recibidos) {
      // Un 206 con otro rango que el pedido no se puede anexar: se descarta y falla como error
      // del servidor.
      await respuesta.bytes.listen(null).cancel();
      throw const ErrorServidorTiles(206);
    }
    // Con 200 (sin soporte de Range) llega el archivo entero: el `.part` se reescribe desde cero.
    final anexar = respuesta.desde > 0;
    if (!anexar) d.recibidos = 0;
    final escritura = await _archivos.abrir(parcial, anexar: anexar);
    _emitir(d, DescargaEnCurso(paquete.id, recibidos: d.recibidos, total: paquete.tamanoBytes));
    final fin = await _recibir(d, respuesta.bytes, escritura);
    await escritura.cerrar();
    switch (fin) {
      case _Fin.completo:
        return true;
      case _Fin.cortado:
        _emitirPausa(d, MotivoPausa.sinConexion);
      case _Fin.pausado:
        _emitirPausa(d, d.pausaPedida ?? MotivoPausa.usuario);
      case _Fin.excedido:
        await _archivos.borrar(parcial);
        d.recibidos = 0;
        _emitir(d, DescargaFallida(paquete.id, const FailurePaqueteTilesCorrupto()));
    }
    return false;
  }

  /// Pide lo que falta. Un 416 con `.part` (el archivo cambió en el servidor, o el `.part` no es de
  /// este archivo) borra el `.part` y pide una sola vez más, desde cero.
  Future<RespuestaDescarga> _pedir(_Descarga d, String parcial) async {
    final origen = d.paquete.origen;
    try {
      return await _cliente.pedir(origen, desde: d.recibidos);
    } on ErrorServidorTiles catch (e) {
      if (e.status != 416 || d.recibidos == 0) rethrow;
      await _archivos.borrar(parcial);
      d.recibidos = 0;
      return _cliente.pedir(origen, desde: 0);
    }
  }

  /// Escribe los pedazos en el `.part` hasta que el cuerpo termina, se corta, se pasa del tamaño
  /// del paquete o alguien corta la bajada (`_Descarga.cortar`).
  Future<_Fin> _recibir(_Descarga d, Stream<List<int>> bytes, EscrituraArchivo escritura) async {
    final total = d.paquete.tamanoBytes;
    final fin = Completer<_Fin>();
    void terminar(_Fin motivo) {
      if (!fin.isCompleted) fin.complete(motivo);
    }

    final suscripcion = bytes.listen(
      (pedazo) {
        if (fin.isCompleted) return;
        escritura.agregar(pedazo);
        d.recibidos += pedazo.length;
        if (d.recibidos > total) {
          terminar(_Fin.excedido);
          return;
        }
        _emitir(d, DescargaEnCurso(d.paquete.id, recibidos: d.recibidos, total: total));
      },
      onError: (Object _) => terminar(_Fin.cortado),
      onDone: () => terminar(d.recibidos == total ? _Fin.completo : _Fin.cortado),
      cancelOnError: true,
    );
    d.cortar = terminar;
    if (d.pausaPedida != null) terminar(_Fin.pausado);
    final motivo = await fin.future;
    d.cortar = null;
    await suscripcion.cancel();
    return motivo;
  }

  /// Corta el intento en curso de [d] con una pausa por [motivo] y espera a que cierre el `.part`.
  /// Una pausa del colportor no se pisa: si mientras se cierra se va la red, sigue siendo suya y
  /// no se retoma sola.
  Future<void> _detener(_Descarga d, MotivoPausa motivo) async {
    if (d.pausaPedida != MotivoPausa.usuario) d.pausaPedida = motivo;
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
      } else if (d.estado case DescargaPausada(sigueSola: true) when permitida) {
        unawaited(_reanudarSola(d));
      }
    }
  }

  Future<void> _reanudarSola(_Descarga d) async {
    final resultado = await descargar(d.paquete, permitirDatosMoviles: d.permitirDatosMoviles);
    final failure = resultado.fold<Failure?>((f) => f, (_) => null);
    // Si la conexión se volvió a ir, sigue en pausa esperando la próxima.
    final sigueEnPausa = failure is FailureSinConexion || failure is FailureDescargaRequiereWifi;
    if (failure != null && !sigueEnPausa) _emitir(d, DescargaFallida(d.paquete.id, failure));
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
  /// cuente como distinto. El algoritmo y el formato del catálogo siguen abiertos (#189).
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
  EstadoDescarga? estado;

  /// Bytes que ya están en el `.part`.
  int recibidos = 0;

  /// El intento en curso (preparar, bajar y validar); completado si no hay ninguno.
  Completer<void>? intento;

  /// Corta la bajada de bytes en curso; `null` si no está bajando.
  void Function(_Fin fin)? cortar;

  /// La pausa pedida mientras el intento seguía en curso.
  MotivoPausa? pausaPedida;

  bool get ocupada {
    final actual = intento;
    return actual != null && !actual.isCompleted;
  }
}
