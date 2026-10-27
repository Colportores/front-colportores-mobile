import 'dart:async';

import 'package:dartz/dartz.dart' show Either, Left;
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/cobertura_tiles.dart';
import '../../domain/entities/estado_descarga.dart';
import '../../domain/entities/lugar_de_trabajo.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../../domain/services/descargador_paquetes_tiles.dart';
import '../../domain/services/fuente_lugar_de_trabajo.dart';
import '../../domain/services/puertos_descarga.dart';
import '../../domain/usecases/descarga_paquete_tiles_use_cases.dart';
import '../textos_mapas_offline.dart';
import 'tiles_providers.dart';

/// De dónde sale la zona y la ciudad del colportor. Hasta la réplica local (#274) no hay fuente: ver
/// [FuenteLugarDeTrabajoSinFuente].
final fuenteLugarDeTrabajoProvider = Provider<FuenteLugarDeTrabajo>(
  (ref) => const FuenteLugarDeTrabajoSinFuente(),
);

/// El espacio libre del teléfono. Sin default, como el descargador: `main.dart` lo sobreescribe con
/// el medidor real y los tests con uno falso.
final medidorEspacioDiscoProvider = Provider<MedidorEspacioDisco>((ref) {
  throw UnimplementedError('medidorEspacioDiscoProvider se sobreescribe en main.dart');
});

/// El reloj con el que se estima cuánto falta para terminar una descarga. Un test lo reemplaza.
final ahoraMapasOfflineProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Los mapas que se ven en la lista de «Mapas offline» (pantalla 02): descargados, bajando o en cola.
final class TarjetaMapa extends Equatable {
  const TarjetaMapa({required this.paquete, this.descargado, this.estado, this.nuevo});

  /// El paquete que se muestra (el descargado, o el que se está bajando).
  final PaqueteTiles paquete;

  /// Lo que ya está en el teléfono, si hay.
  final PaqueteDescargado? descargado;

  /// En qué está la descarga: `null` si no hay ninguna en curso, en pausa o en cola.
  final EstadoDescarga? estado;

  /// La versión nueva que trae el catálogo, si cambió respecto de la descargada.
  final PaqueteTiles? nuevo;

  bool get bajando => estado != null && estado is! DescargaCompletada;

  @override
  List<Object?> get props => [paquete, descargado, estado, nuevo];
}

/// Lo que hace falta mostrar antes de achicar la cobertura (pantalla 02, «Achicar la cobertura»).
final class PlanAchicar extends Equatable {
  const PlanAchicar({required this.elegido, required this.sobran, required this.liberanBytes});

  final OpcionCobertura elegido;

  /// Los mapas más grandes que cubren el mismo lugar y se borran al terminar.
  final List<PaqueteDescargado> sobran;

  /// Lo que queda libre al final: lo que pesan [sobran] menos lo que hay que bajar.
  final int liberanBytes;

  @override
  List<Object?> get props => [elegido, sobran, liberanBytes];
}

/// Todo lo que dibuja «Mapas offline» (vista 35, HU-SYNC-010).
final class EstadoMapasOffline extends Equatable {
  const EstadoMapasOffline({
    this.cargando = true,
    this.lugar,
    this.falloLugar,
    this.cobertura,
    this.bytesLibres,
    this.conexion = TipoConexion.wifi,
    this.elegido,
    this.cambiando = false,
    this.descargas = const {},
    this.paquetesEnMarcha = const {},
    this.restante = const {},
    this.falla,
    this.pidiendo = false,
    this.aviso,
  });

  /// Mientras se lee dónde trabaja, el catálogo y lo descargado.
  final bool cargando;
  final LugarDeTrabajo? lugar;

  /// Por qué no se pudo saber dónde trabaja; `null` si se supo.
  final Failure? falloLugar;
  final CoberturaTiles? cobertura;

  /// `null` si no se pudo medir.
  final int? bytesLibres;
  final TipoConexion conexion;

  /// El nivel que eligió el colportor; `null` hasta que toca uno (rige el que sugiere la pantalla).
  final NivelCobertura? elegido;

  /// Viendo la pantalla 01 aunque haya mapas descargados («Cambiar cobertura»).
  final bool cambiando;

  /// En qué está cada descarga que el descargador conoce (sin las terminadas ni las eliminadas).
  final Map<String, EstadoDescarga> descargas;
  final Map<String, PaqueteTiles> paquetesEnMarcha;

  /// Cuánto falta, estimado con lo que viene bajando.
  final Map<String, Duration> restante;

  /// La falla del último pedido o de una descarga: se muestra donde se tocó.
  final Failure? falla;

  /// Mientras se arranca una descarga o se borra: corta el segundo toque.
  final bool pidiendo;

  /// Un aviso de una sola vez (un mapa quedó listo, se borró): la pantalla lo muestra y lo consume.
  final String? aviso;

  bool get sinCatalogo => cobertura?.falloCatalogo != null;

  List<OpcionCobertura> get opciones => cobertura?.opciones ?? const [];

  OpcionCobertura? opcion(NivelCobertura nivel) {
    for (final opcion in opciones) {
      if (opcion.nivel == nivel) return opcion;
    }
    return null;
  }

  /// Un nivel se puede elegir para bajarlo: el catálogo trae su paquete y el lugar lo permite.
  bool seOfrece(NivelCobertura nivel) {
    if (opcion(nivel)?.paquete == null) return false;
    if (nivel == NivelCobertura.zona && lugar?.ambito.zonaId == null) return false;
    return true;
  }

  /// El nivel que rige: el que eligió el colportor o, sin elección, el primero que se ofrece y no
  /// está bajado (zona antes que ciudad; departamento y Uruguay solo si los elige).
  NivelCobertura? get nivelVigente {
    final pedido = elegido;
    if (pedido != null && seOfrece(pedido)) return pedido;
    for (final nivel in const [NivelCobertura.zona, NivelCobertura.ciudad]) {
      if (seOfrece(nivel) && opcion(nivel)?.descargado == null) return nivel;
    }
    for (final nivel in NivelCobertura.values) {
      if (seOfrece(nivel)) return nivel;
    }
    return null;
  }

  /// Los mapas de la pantalla 02: lo descargado y lo que se está bajando, lo más chico primero.
  List<TarjetaMapa> get tarjetas {
    final porId = <String, TarjetaMapa>{};
    void agregar(PaqueteDescargado descargado, PaqueteTiles? nuevo) {
      porId[descargado.id] = TarjetaMapa(
        paquete: descargado.paquete,
        descargado: descargado,
        estado: descargas[descargado.id],
        nuevo: nuevo,
      );
    }

    for (final opcion in opciones) {
      final descargado = opcion.descargado;
      if (descargado != null) {
        agregar(descargado, opcion.hayActualizacion ? opcion.paquete : null);
      }
    }
    for (final descargado in cobertura?.otrosDescargados ?? const <PaqueteDescargado>[]) {
      agregar(descargado, null);
    }
    for (final MapEntry(key: id, value: estado) in descargas.entries) {
      if (porId.containsKey(id)) continue;
      final paquete = paquetesEnMarcha[id];
      if (paquete != null) porId[id] = TarjetaMapa(paquete: paquete, estado: estado);
    }
    return porId.values.toList()
      ..sort((a, b) => a.paquete.nivel.index.compareTo(b.paquete.nivel.index));
  }

  /// Se ve la pantalla 02: hay algo descargado o bajando y el colportor no pidió cambiar.
  bool get verDescargas => !cambiando && tarjetas.isNotEmpty;

  EstadoMapasOffline copiar({
    bool? cargando,
    LugarDeTrabajo? lugar,
    Failure? falloLugar,
    bool sinFalloLugar = false,
    CoberturaTiles? cobertura,
    int? bytesLibres,
    bool sinBytesLibres = false,
    TipoConexion? conexion,
    NivelCobertura? elegido,
    bool? cambiando,
    Map<String, EstadoDescarga>? descargas,
    Map<String, PaqueteTiles>? paquetesEnMarcha,
    Map<String, Duration>? restante,
    Failure? falla,
    bool sinFalla = false,
    bool? pidiendo,
    String? aviso,
    bool sinAviso = false,
  }) => EstadoMapasOffline(
    cargando: cargando ?? this.cargando,
    lugar: lugar ?? this.lugar,
    falloLugar: sinFalloLugar ? null : (falloLugar ?? this.falloLugar),
    cobertura: cobertura ?? this.cobertura,
    bytesLibres: sinBytesLibres ? null : (bytesLibres ?? this.bytesLibres),
    conexion: conexion ?? this.conexion,
    elegido: elegido ?? this.elegido,
    cambiando: cambiando ?? this.cambiando,
    descargas: descargas ?? this.descargas,
    paquetesEnMarcha: paquetesEnMarcha ?? this.paquetesEnMarcha,
    restante: restante ?? this.restante,
    falla: sinFalla ? null : (falla ?? this.falla),
    pidiendo: pidiendo ?? this.pidiendo,
    aviso: sinAviso ? null : (aviso ?? this.aviso),
  );

  @override
  List<Object?> get props => [
    cargando,
    lugar,
    falloLugar,
    cobertura,
    bytesLibres,
    conexion,
    elegido,
    cambiando,
    descargas,
    paquetesEnMarcha,
    restante,
    falla,
    pidiendo,
    aviso,
  ];
}

/// «Mapas offline»: elegir cuánto mapa bajar, ver cómo avanza, pausar, borrar, achicar y actualizar
/// (HU-SYNC-010). Las reglas de la descarga (Wi-Fi, espacio, Range, checksum, reintentos) son del
/// descargador; acá se decide qué se ofrece y qué se dice.
class MapasOfflineNotifier extends Notifier<EstadoMapasOffline> {
  StreamSubscription<TipoConexion>? _escuchaConexion;

  /// Para estimar lo que falta: lo último que se vio bajar de cada paquete y la velocidad.
  final _muestras = <String, ({DateTime cuando, int recibidos, double bytesPorSegundo})>{};

  /// Los mapas más grandes que se borran cuando termina de bajar el que los reemplaza.
  final _sobrantes = <String, List<String>>{};
  int _secuencia = 0;

  @override
  EstadoMapasOffline build() {
    ref.listen(estadosDescargaTilesProvider, (_, nuevo) {
      if (nuevo case AsyncData(:final value)) unawaited(_alEstado(value));
    });
    ref.onDispose(() => unawaited(_escuchaConexion?.cancel()));
    unawaited(Future<void>.microtask(cargar));
    return const EstadoMapasOffline();
  }

  /// Lee dónde trabaja, el catálogo, lo descargado, el espacio libre y la conexión.
  Future<void> cargar() async {
    final numero = ++_secuencia;
    state = state.copiar(cargando: true, sinFalla: true);
    final lugar = await _leerLugar();
    final ambito = lugar.fold((_) => const AmbitoTrabajo(), (l) => l.ambito);
    final cobertura = await _leerCobertura(ambito);
    final libres = await _leerLibres();
    final conexion = await _leerConexion();
    if (!ref.mounted || numero != _secuencia) return;
    _escuchaConexion ??= _monitor()?.cambios.listen(
      (nueva) => state = state.copiar(conexion: nueva),
      onError: (Object _) {},
    );
    final descargador = _descargador();
    final descargas = <String, EstadoDescarga>{};
    final enMarcha = <String, PaqueteTiles>{};
    void mirar(String id) {
      if (descargador == null) return;
      final estado = descargador.estadoDe(id);
      final paquete = descargador.paqueteDe(id);
      if (estado == null || paquete == null) return;
      if (estado is DescargaCompletada || estado is DescargaEliminada) return;
      descargas[id] = estado;
      enMarcha[id] = paquete;
    }

    for (final opcion in cobertura.opciones) {
      if (opcion.paquete case final paquete?) mirar(paquete.id);
      if (opcion.descargado case final d?) mirar(d.id);
    }
    for (final descargado in cobertura.otrosDescargados) {
      mirar(descargado.id);
    }
    if (descargador?.paqueteEnMarchaQueCubre(ambito) case final propio?) mirar(propio.id);
    state = state.copiar(
      cargando: false,
      lugar: lugar.fold((_) => null, (l) => l),
      falloLugar: lugar.fold((f) => f, (_) => null),
      sinFalloLugar: lugar.isRight(),
      cobertura: cobertura,
      bytesLibres: libres,
      sinBytesLibres: libres == null,
      conexion: conexion,
      descargas: descargas,
      paquetesEnMarcha: enMarcha,
    );
  }

  /// El descargador, o `null` si la app no lo cableó (la carpeta de mapas no se pudo preparar): la
  /// pantalla igual abre y dice qué falta, en vez de quedarse esperando.
  DescargadorPaquetesTiles? _descargador() {
    try {
      return ref.read(descargadorPaquetesTilesProvider);
    } on Object {
      return null;
    }
  }

  /// Entre el pedido y el primer `DescargaEnCurso` (los encabezados HTTP pueden tardar hasta 30 s)
  /// el descargador ya está ocupado pero todavía no emitió nada: se muestra la tarjeta en «0 %» para
  /// que el colportor vea que la descarga arrancó y no vuelva a tocar el botón.
  void _marcarArrancando(PaqueteTiles paquete) {
    if (!ref.mounted) return;
    final id = paquete.id;
    if (_descargador()?.estaDescargando(id) != true) return;
    final actual = state.descargas[id];
    if (actual is DescargaEnCurso || actual is DescargaVerificando) return;
    _muestras.remove(id);
    state = state.copiar(
      descargas: {
        ...state.descargas,
        id: DescargaEnCurso(id, recibidos: 0, total: paquete.tamanoBytes),
      },
      paquetesEnMarcha: {...state.paquetesEnMarcha, id: paquete},
      restante: {...state.restante}..remove(id),
    );
  }

  MonitorConectividad? _monitor() {
    try {
      return ref.read(monitorConectividadProvider);
    } on Object {
      return null;
    }
  }

  Future<Either<Failure, LugarDeTrabajo>> _leerLugar() async {
    try {
      return await ref.read(fuenteLugarDeTrabajoProvider).leer();
    } on Object {
      return const Left(FailureLugarDeTrabajoNoDisponible());
    }
  }

  Future<CoberturaTiles> _leerCobertura(AmbitoTrabajo ambito) async {
    try {
      final resultado = await ref.read(listarCoberturaTilesUseCaseProvider)(ambito);
      return resultado.fold(
        (f) => CoberturaTiles(opciones: _vacias, otrosDescargados: const [], falloCatalogo: f),
        (c) => c,
      );
    } on Object catch (e) {
      return CoberturaTiles(
        opciones: _vacias,
        otrosDescargados: const [],
        falloCatalogo: FailureInesperado(causa: e),
      );
    }
  }

  static final _vacias = [for (final n in NivelCobertura.values) OpcionCobertura(nivel: n)];

  Future<int?> _leerLibres() async {
    try {
      return await ref.read(medidorEspacioDiscoProvider).bytesLibres();
    } on Object {
      return null;
    }
  }

  Future<TipoConexion> _leerConexion() async {
    try {
      return await ref.read(monitorConectividadProvider).actual();
    } on Object {
      return TipoConexion.wifi;
    }
  }

  Future<void> _recargarCobertura() async {
    final ambito = state.lugar?.ambito ?? const AmbitoTrabajo();
    final cobertura = await _leerCobertura(ambito);
    final libres = await _leerLibres();
    if (!ref.mounted) return;
    state = state.copiar(cobertura: cobertura, bytesLibres: libres, sinBytesLibres: libres == null);
  }

  Future<void> _alEstado(EstadoDescarga estado) async {
    final id = estado.paqueteId;
    final descargas = {...state.descargas};
    final enMarcha = {...state.paquetesEnMarcha};
    final restante = {...state.restante};
    switch (estado) {
      case DescargaCompletada(:final descargado):
        descargas.remove(id);
        enMarcha.remove(id);
        restante.remove(id);
        _muestras.remove(id);
        final nombre = TextosMapasOffline.nombreDe(
          descargado.paquete,
          nombreZona: state.lugar?.zonaNombre,
        );
        state = state.copiar(
          descargas: descargas,
          paquetesEnMarcha: enMarcha,
          restante: restante,
          cambiando: false,
          aviso: TextosMapasOffline.disponibleSinConexion(nombre),
          sinFalla: true,
        );
        await _recargarCobertura();
        await _borrarSobrantes(id);
        return;
      case DescargaEliminada():
        descargas.remove(id);
        enMarcha.remove(id);
        restante.remove(id);
        _muestras.remove(id);
        _sobrantes.remove(id);
        state = state.copiar(descargas: descargas, paquetesEnMarcha: enMarcha, restante: restante);
        await _recargarCobertura();
        return;
      case DescargaFallida(:final failure):
        descargas[id] = estado;
        final conocido = _descargador()?.paqueteDe(id);
        if (conocido != null) enMarcha[id] = conocido;
        state = state.copiar(descargas: descargas, paquetesEnMarcha: enMarcha, falla: failure);
        return;
      case DescargaEnCurso(:final recibidos, :final total):
        _estimar(id, recibidos, total, restante);
        descargas[id] = estado;
      case DescargaPausada() || DescargaVerificando():
        _muestras.remove(id);
        restante.remove(id);
        descargas[id] = estado;
    }
    final paquete = _descargador()?.paqueteDe(id);
    if (paquete != null) enMarcha[id] = paquete;
    state = state.copiar(descargas: descargas, paquetesEnMarcha: enMarcha, restante: restante);
  }

  void _estimar(String id, int recibidos, int total, Map<String, Duration> restante) {
    final ahora = ref.read(ahoraMapasOfflineProvider)();
    final antes = _muestras[id];
    var velocidad = antes?.bytesPorSegundo ?? 0;
    if (antes != null) {
      final segundos = ahora.difference(antes.cuando).inMilliseconds / 1000;
      if (segundos > 0 && recibidos > antes.recibidos) {
        final instantanea = (recibidos - antes.recibidos) / segundos;
        velocidad = velocidad == 0 ? instantanea : velocidad * 0.7 + instantanea * 0.3;
      }
    }
    _muestras[id] = (cuando: ahora, recibidos: recibidos, bytesPorSegundo: velocidad);
    if (velocidad > 0 && total > recibidos) {
      restante[id] = Duration(seconds: ((total - recibidos) / velocidad).ceil());
    }
  }

  Future<void> _borrarSobrantes(String idTerminado) async {
    final ids = _sobrantes.remove(idTerminado);
    if (ids == null) return;
    for (final id in ids) {
      final resultado = await ref.read(eliminarPaqueteTilesUseCaseProvider)(id);
      if (resultado.isLeft() && ref.mounted) {
        state = state.copiar(falla: resultado.fold((f) => f, (_) => null));
      }
    }
    if (ref.mounted) await _recargarCobertura();
  }

  /// El colportor tocó un nivel de la pantalla 01.
  void elegir(NivelCobertura nivel) {
    if (!state.seOfrece(nivel)) return;
    state = state.copiar(elegido: nivel, sinFalla: true);
  }

  /// «Cambiar cobertura»: la pantalla 01 con lo que ya hay descargado.
  void verCobertura() => state = state.copiar(cambiando: true, sinFalla: true);

  /// Vuelve a la lista de mapas.
  void verDescargas() => state = state.copiar(cambiando: false, sinFalla: true);

  /// Un aviso de una sola vez ya se mostró.
  void consumirAviso() {
    if (state.aviso != null) state = state.copiar(sinAviso: true);
  }

  /// Lo que se borraría si el colportor se queda con el nivel vigente, o `null` si no hay nada más
  /// grande descargado (entonces se baja directo).
  PlanAchicar? planDeAchicar() {
    final nivel = state.nivelVigente;
    final opcion = nivel == null ? null : state.opcion(nivel);
    if (opcion == null) return null;
    final sobran = [
      for (final o in state.opciones)
        if (o.nivel.index > opcion.nivel.index && o.descargado != null) o.descargado!,
    ];
    if (sobran.isEmpty) return null;
    final pesan = sobran.fold<int>(0, (suma, d) => suma + d.paquete.tamanoBytes);
    final hayQueBajar = opcion.descargado == null;
    final falta = hayQueBajar ? (opcion.paquete?.tamanoBytes ?? 0) : 0;
    return PlanAchicar(
      elegido: opcion,
      sobran: sobran,
      liberanBytes: pesan > falta ? pesan - falta : 0,
    );
  }

  /// «Descargar» del nivel vigente. Sin Wi-Fi queda en cola y arranca sola con el Wi-Fi: así lo
  /// dibuja el canvas («Descargar con Wi-Fi»). Con [achicar] baja el nivel elegido y, al terminar,
  /// borra los más grandes que sobran.
  Future<void> descargar({PlanAchicar? achicar}) async {
    final nivel = state.nivelVigente;
    final opcion = nivel == null ? null : state.opcion(nivel);
    if (opcion == null || state.pidiendo) return;
    final paquete = opcion.paquete;
    if (paquete == null) return;
    state = state.copiar(
      pidiendo: true,
      sinFalla: true,
      paquetesEnMarcha: {...state.paquetesEnMarcha, paquete.id: paquete},
    );
    try {
      if (opcion.descargado != null && !opcion.hayActualizacion) {
        if (achicar != null) await _borrarYa(achicar);
        return;
      }
      if (achicar != null) _sobrantes[paquete.id] = [for (final d in achicar.sobran) d.id];
      final resultado = await ref.read(descargarPaqueteTilesUseCaseProvider)(
        DescargarPaqueteTilesParams(paquete: paquete, esperarConexion: true),
      );
      if (resultado.isLeft()) {
        _sobrantes.remove(paquete.id);
        if (ref.mounted) state = state.copiar(falla: resultado.fold((f) => f, (_) => null));
      } else {
        _marcarArrancando(paquete);
      }
    } on Object {
      _sobrantes.remove(paquete.id);
      if (ref.mounted) state = state.copiar(falla: const FailureInesperado());
    } finally {
      if (ref.mounted) state = state.copiar(pidiendo: false);
    }
  }

  Future<void> _borrarYa(PlanAchicar plan) async {
    for (final d in plan.sobran) {
      final resultado = await ref.read(eliminarPaqueteTilesUseCaseProvider)(d.id);
      if (resultado.isLeft() && ref.mounted) {
        state = state.copiar(falla: resultado.fold((f) => f, (_) => null));
        return;
      }
    }
    await _recargarCobertura();
    if (ref.mounted) state = state.copiar(cambiando: false);
  }

  /// «Actualizar»: baja la versión nueva del catálogo (reemplaza a la descargada al terminar).
  Future<void> actualizar(TarjetaMapa tarjeta) async {
    final nuevo = tarjeta.nuevo;
    if (nuevo == null || state.pidiendo) return;
    state = state.copiar(pidiendo: true, sinFalla: true);
    try {
      final resultado = await ref.read(descargarPaqueteTilesUseCaseProvider)(
        DescargarPaqueteTilesParams(paquete: nuevo, esperarConexion: true),
      );
      if (resultado.isLeft() && ref.mounted) {
        state = state.copiar(falla: resultado.fold((f) => f, (_) => null));
      } else {
        _marcarArrancando(nuevo);
      }
    } on Object {
      if (ref.mounted) state = state.copiar(falla: const FailureInesperado());
    } finally {
      if (ref.mounted) state = state.copiar(pidiendo: false);
    }
  }

  /// «Pausar»: la descarga queda con lo que bajó y sigue cuando el colportor toca «Seguir».
  Future<void> pausar(String paqueteId) async {
    try {
      await ref.read(pausarDescargaTilesUseCaseProvider)(paqueteId);
    } on Object {
      if (ref.mounted) state = state.copiar(falla: const FailureInesperado());
    }
  }

  /// «Seguir» (o «Reintentar» tras una falla): reanuda desde el byte que quedó.
  Future<void> seguir(TarjetaMapa tarjeta) async {
    if (state.pidiendo) return;
    final paquete = tarjeta.nuevo ?? tarjeta.paquete;
    state = state.copiar(pidiendo: true, sinFalla: true);
    try {
      final resultado = await ref.read(descargarPaqueteTilesUseCaseProvider)(
        DescargarPaqueteTilesParams(paquete: paquete, esperarConexion: true),
      );
      if (resultado.isLeft() && ref.mounted) {
        state = state.copiar(falla: resultado.fold((f) => f, (_) => null));
      } else {
        _marcarArrancando(paquete);
      }
    } on Object {
      if (ref.mounted) state = state.copiar(falla: const FailureInesperado());
    } finally {
      if (ref.mounted) state = state.copiar(pidiendo: false);
    }
  }

  /// «Borrar mapa»: lo saca del teléfono y libera el espacio. Nada más se pierde: se vuelve a bajar
  /// cuando se quiera.
  Future<void> borrar(TarjetaMapa tarjeta) async {
    if (state.pidiendo) return;
    state = state.copiar(pidiendo: true, sinFalla: true);
    final liberado = tarjeta.paquete.megabytes;
    try {
      final resultado = await ref.read(eliminarPaqueteTilesUseCaseProvider)(tarjeta.paquete.id);
      if (!ref.mounted) return;
      resultado.fold(
        (f) => state = state.copiar(falla: f),
        (_) => state = state.copiar(aviso: TextosMapasOffline.mapaBorrado(liberado)),
      );
    } on Object {
      if (ref.mounted) state = state.copiar(falla: const FailureInesperado());
    } finally {
      if (ref.mounted) state = state.copiar(pidiendo: false);
    }
  }
}

final mapasOfflineProvider = NotifierProvider.autoDispose<MapasOfflineNotifier, EstadoMapasOffline>(
  MapasOfflineNotifier.new,
);
