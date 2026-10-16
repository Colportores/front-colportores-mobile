import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../tiles/domain/entities/estado_descarga.dart';
import '../../../tiles/domain/entities/paquete_tiles.dart';
import '../../../tiles/domain/services/descargador_paquetes_tiles.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../../tiles/domain/usecases/descarga_paquete_tiles_use_cases.dart';
import '../../../tiles/presentation/providers/tiles_providers.dart';
import '../../domain/entities/situacion_mapa.dart';

// El mapa de fondo y su aviso según la conexión, lo descargado y el catálogo (HU-UBI-003,
// HU-SYNC-010; #190). Las vistas 03 (alta) y 06 (mapa) leen de acá: `fuenteMapaProvider`
// (en `mapa_base_providers.dart`) para el mapa y `situacionMapaProvider` para el aviso.
//
// Ningún provider de acá lanza: cada fallo (sin catálogo, descargador sin cablear) se convierte en un
// valor, porque Riverpod 3 reintenta solo los que lanzan una excepción. Y mientras no se sabe algo
// (la conexión, lo descargado) no se afirma nada: nunca «Sin conexión» sin saberlo.

/// El valor de un [AsyncValue] mientras se lo sabe, aunque se esté recargando; `null` si todavía no
/// hay o falló antes de dar uno.
T? _lectura<T>(AsyncValue<T> asincrono) => asincrono.hasValue ? asincrono.value : null;

/// Los `.pmtiles` descargados que cubren [AmbitoTrabajo] (uno por parte); vacío si no hay ninguno o
/// no se pudo leer el registro de descargas.
final rutasDescargadasProvider = StreamProvider.autoDispose.family<List<String>, AmbitoTrabajo>((
  ref,
  ambito,
) {
  if (!ambito.conocido) return Stream.value(const <String>[]);
  return ref
      .watch(observarPaqueteOfflineUseCaseProvider)(ambito)
      .map((paquete) => paquete?.rutas ?? const <String>[])
      .handleError((Object _) {});
});

/// Qué dice el catálogo del paquete que cubre [AmbitoTrabajo]. Sin conexión no se le pregunta: se
/// vuelve a preguntar solo cuando la conexión vuelve, y cuando aparece o desaparece lo descargado
/// (el caso de uso contesta `null` tanto si el paquete ya está descargado como si el catálogo no
/// trae ninguno; sin mirar el registro, un mapa recién borrado quedaría como «no disponible»).
final paqueteDelAmbitoProvider = FutureProvider.autoDispose.family<PaqueteDelAmbito, AmbitoTrabajo>(
  (ref, ambito) async {
    if (!ambito.conocido) return const PaqueteSinAmbito();
    final conectado = ref.watch(
      conexionProvider.select(
        (conexion) => switch (conexion) {
          AsyncData(:final value) => value != TipoConexion.sinConexion,
          _ => null,
        },
      ),
    );
    final hayDescargado = ref.watch(
      rutasDescargadasProvider(ambito).select((rutas) => rutas.value?.isNotEmpty ?? false),
    );
    if (conectado != true) return const PaqueteSinRed();
    try {
      final sugerido = await ref.read(sugerirPaqueteTilesUseCaseProvider)(ambito);
      return sugerido.fold<PaqueteDelAmbito>(
        (_) => const PaqueteNoDisponible(),
        (paquete) => switch (paquete) {
          final PaqueteTiles hallado => PaqueteHallado(hallado),
          null when hayDescargado => const PaqueteYaDescargado(),
          null => const PaqueteNoDisponible(),
        },
      );
    } on Object {
      return const PaqueteNoDisponible();
    }
  },
);

/// La prueba del archivo del mapa en línea de [AmbitoTrabajo] (#299, «Mapa caído»): al abrir el mapa
/// con conexión, si el mapa que va a mostrar no está en el teléfono, se le pide 1 byte (`Range`) a
/// cada `.pmtiles` del paquete del catálogo. Una prueba por apertura: el provider se descarta con la
/// pantalla, y «Reintentar» lo invalida para probar de nuevo.
///
/// `null`: no corresponde probar (sin conexión, sin ámbito, el catálogo no trae el paquete o ya está
/// descargado) o la prueba no se pudo hacer (la sonda sin cablear, un error de programación): sin
/// saberlo no se afirma nada. Si el paquete tiene varias partes se prueban todas a la vez, y alcanza
/// que una falle para que las calles no se vean completas.
///
/// No demora a [paqueteDelAmbitoProvider]: «Descargar mapa» y el peso del botón salen del catálogo
/// aunque la prueba siga en curso o haya fallado. Mientras la prueba no termina el mapa se pide en
/// línea como siempre; el aviso sale recién si falla.
final pruebaDelMapaProvider = FutureProvider.autoDispose.family<PruebaDelMapa?, AmbitoTrabajo>((
  ref,
  ambito,
) async {
  // Solo cambia cuando cambia el paquete (o aparece/desaparece): pasar de Wi-Fi a datos móviles, o
  // releer el catálogo, no vuelve a probar.
  final paquete = ref.watch(
    paqueteDelAmbitoProvider(ambito).select(
      (consulta) => switch (_lectura(consulta)) {
        PaqueteHallado(:final paquete) => paquete,
        _ => null,
      },
    ),
  );
  if (paquete == null) return null;
  // Se completa cuando a nadie le importa más lo que contesten los pedidos en vuelo: salió del mapa
  // o se pidió otra prueba (el provider se descarta), o la prueba ya tiene su respuesta (si una
  // parte falló, las demás no se siguen esperando). La sonda aborta entonces los pedidos que queden
  // y cierra las conexiones, en vez de dejarlas abiertas contra un servidor que no contesta.
  final cancelar = Completer<void>();
  void cancelarLoQueQuede() {
    if (!cancelar.isCompleted) cancelar.complete();
  }

  ref.onDispose(cancelarLoQueQuede);
  try {
    final sonda = ref.read(sondaArchivoTilesProvider);
    await Future.wait([
      for (final parte in paquete.partes) sonda.probar(parte.origen, cancelacion: cancelar.future),
    ], eagerError: true);
    return PruebaDelMapa.respondio;
  } on ErrorRedTiles {
    return PruebaDelMapa.fallo;
  } on ErrorServidorTiles {
    return PruebaDelMapa.fallo;
  } on Object {
    return null;
  } finally {
    cancelarLoQueQuede();
  }
});

/// El mapa y el aviso de [AmbitoTrabajo]. Sin lo que hace falta saber (la conexión, lo descargado)
/// es el color liso sin aviso.
final situacionMapaProvider = Provider.autoDispose.family<SituacionMapa, AmbitoTrabajo>((
  ref,
  ambito,
) {
  final rutas = ref.watch(rutasDescargadasProvider(ambito));
  return ResolutorSituacionMapa.resolver(
    conexion: _lectura(ref.watch(conexionProvider)),
    // Un error al leer el registro de descargas cuenta como «sin descargas»: el mapa en línea sigue.
    rutasDescargadas: rutas.hasError && !rutas.hasValue ? const <String>[] : _lectura(rutas),
    consulta: _lectura(ref.watch(paqueteDelAmbitoProvider(ambito))),
    prueba: _lectura<PruebaDelMapa?>(ref.watch(pruebaDelMapaProvider(ambito))),
  );
});

/// Lo que el colportor ya descartó en esta sesión (la sesión es lo que dura la app abierta).
final class DescartesAvisoMapa extends Equatable {
  const DescartesAvisoMapa({this.sinConexionMinimizado = false, this.datosMovilesOculto = false});

  /// Tocó la ✕ del aviso rojo: de ahí en más solo se ve la píldora (06C·06).
  final bool sinConexionMinimizado;

  /// Tocó «Ahora no» del aviso de datos móviles (06C·07).
  final bool datosMovilesOculto;

  @override
  List<Object?> get props => [sinConexionMinimizado, datosMovilesOculto];
}

final class DescartesAvisoMapaNotifier extends Notifier<DescartesAvisoMapa> {
  @override
  DescartesAvisoMapa build() => const DescartesAvisoMapa();

  void minimizarSinConexion() {
    state = DescartesAvisoMapa(
      sinConexionMinimizado: true,
      datosMovilesOculto: state.datosMovilesOculto,
    );
  }

  void ocultarDatosMoviles() {
    state = DescartesAvisoMapa(
      sinConexionMinimizado: state.sinConexionMinimizado,
      datosMovilesOculto: true,
    );
  }
}

final descartesAvisoMapaProvider = NotifierProvider<DescartesAvisoMapaNotifier, DescartesAvisoMapa>(
  DescartesAvisoMapaNotifier.new,
);

/// Hay un aviso del mapa a la vista (la tarjeta o, minimizado, la píldora): la vista 06 saca de
/// ahí lo que se le encimaría, como «Referencias» (el canvas no lo dibuja junto a los avisos).
final avisoMapaVisibleProvider = Provider.autoDispose.family<bool, AmbitoTrabajo>((ref, ambito) {
  final aviso = ref.watch(situacionMapaProvider(ambito).select((situacion) => situacion.aviso));
  final descartes = ref.watch(descartesAvisoMapaProvider);
  return switch (aviso) {
    null => false,
    AvisoSinConexion() || AvisoMapaNoCarga() => true,
    AvisoDatosMoviles() => !descartes.datosMovilesOculto,
  };
});

/// El pedido de «Descargar mapa» de un ámbito.
final class EstadoSolicitudMapa extends Equatable {
  const EstadoSolicitudMapa({
    this.ocupada = false,
    this.enEspera = false,
    this.enCola = false,
    this.bajando = false,
    this.falla,
  });

  /// El pedido se está haciendo ahora: los botones esperan (no se pide dos veces).
  final bool ocupada;

  /// El colportor pidió el mapa pero todavía no se sabe cuál (no hubo conexión para leer el
  /// catálogo): en cuanto el catálogo responde, la descarga arranca sola.
  final bool enEspera;

  /// El descargador lo tiene en cola: baja solo con la primera conexión que vuelva.
  final bool enCola;

  /// El descargador lo está bajando (o validando) ahora.
  final bool bajando;

  /// Por qué no se pudo pedir o falló la descarga; los botones vuelven a estar habilitados.
  final Failure? falla;

  /// El pedido ya salió y no falta que el colportor toque nada: los botones de «Descargar mapa»
  /// quedan deshabilitados hasta que termine o falle.
  bool get enMarcha => ocupada || enEspera || enCola || bajando;

  /// Se pidió y espera la señal: «Se descarga sola cuando vuelva la señal.»
  bool get esperaSenal => enEspera || enCola;

  EstadoSolicitudMapa copiar({
    bool? ocupada,
    bool? enEspera,
    bool? enCola,
    bool? bajando,
    Failure? falla,
    bool sinFalla = false,
  }) => EstadoSolicitudMapa(
    ocupada: ocupada ?? this.ocupada,
    enEspera: enEspera ?? this.enEspera,
    enCola: enCola ?? this.enCola,
    bajando: bajando ?? this.bajando,
    falla: sinFalla ? null : (falla ?? this.falla),
  );

  @override
  List<Object?> get props => [ocupada, enEspera, enCola, bajando, falla];
}

/// «Descargar mapa» (06C·05, 06C·06 y 06C·07): pide el paquete con la primera conexión que vuelva,
/// incluso datos móviles (`permitirDatosMoviles` y `esperarConexion`: el override manual de
/// HU-SYNC-010); lo que la app baja sola espera al Wi-Fi.
///
/// Vive toda la sesión (no se descarta con la pantalla): un pedido en espera sigue aunque el
/// colportor salga y vuelva. Pedir de nuevo un mapa que ya está en cola no lo encola otra vez
/// (`DescargadorPaquetesTiles` ya deduplica), y mientras está en cola o bajando los botones quedan
/// deshabilitados.
///
/// Arranca desde lo que el descargador ya tiene en marcha para el ámbito: una descarga que se
/// retomó al abrir la app (HU-SYNC-010, «La descarga sigue después de cerrar la app») está en cola
/// o bajando antes de que exista la vista, y sin conexión el catálogo no dice qué paquete era.
final class SolicitudMapaNotifier extends Notifier<EstadoSolicitudMapa> {
  SolicitudMapaNotifier(this.ambito);

  final AmbitoTrabajo ambito;

  /// El último paquete que el catálogo trajo para el ámbito: con él se puede encolar la descarga
  /// aunque ahora no haya conexión.
  PaqueteTiles? _paquete;

  /// Las descargas que ya se vieron de este ámbito. Una descarga retomada al abrir la app puede ser
  /// de una versión que el catálogo ya no trae, o el catálogo puede no haber llegado todavía: se la
  /// reconoce por lo que el descargador sabe de ella, y se la recuerda para no perder el aviso de
  /// su final (el descargador la olvida al eliminarla).
  final _ids = <String>{};

  @override
  EstadoSolicitudMapa build() {
    ref.listen(paqueteDelAmbitoProvider(ambito), (_, nuevo) {
      final paquete = _delCatalogo(nuevo);
      if (paquete == null) return;
      _paquete = paquete;
      if (state.enEspera) unawaited(_iniciar(paquete));
    });
    _paquete = _delCatalogo(ref.read(paqueteDelAmbitoProvider(ambito))) ?? _paquete;
    ref.listen(estadosDescargaTilesProvider, (_, nuevo) {
      if (nuevo case AsyncData(:final value) when _esDeEsteAmbito(value.paqueteId)) {
        state = _segunEstado(state, value);
      }
    });
    return _delDescargador();
  }

  /// En qué está la descarga que el descargador ya tiene en marcha para el ámbito, si hay alguna.
  EstadoSolicitudMapa _delDescargador() {
    const vacio = EstadoSolicitudMapa();
    final descargador = _descargador();
    final paquete = descargador?.paqueteEnMarchaQueCubre(ambito);
    if (descargador == null || paquete == null) return vacio;
    _ids.add(paquete.id);
    if (descargador.estaDescargando(paquete.id)) return vacio.copiar(bajando: true);
    final estado = descargador.estadoDe(paquete.id);
    return estado == null ? vacio : _segunEstado(vacio, estado);
  }

  /// `true` si [paqueteId] es la descarga de este ámbito: la del paquete que trajo el catálogo, o
  /// una que el descargador tiene y cubre el lugar (la retomada al abrir la app).
  bool _esDeEsteAmbito(String paqueteId) {
    if (_ids.contains(paqueteId)) return true;
    final delCatalogo = _paquete?.id == paqueteId;
    final delDescargador = _descargador()?.paqueteDe(paqueteId)?.cubre(ambito) ?? false;
    if (!delCatalogo && !delDescargador) return false;
    _ids.add(paqueteId);
    return true;
  }

  DescargadorPaquetesTiles? _descargador() {
    try {
      return ref.read(descargadorPaquetesTilesProvider);
    } on Object {
      return null;
    }
  }

  static PaqueteTiles? _delCatalogo(AsyncValue<PaqueteDelAmbito> consulta) => switch (consulta) {
    AsyncData(value: PaqueteHallado(:final paquete)) => paquete,
    _ => null,
  };

  /// Qué ve el colportor según en qué está la descarga del paquete.
  static EstadoSolicitudMapa _segunEstado(EstadoSolicitudMapa actual, EstadoDescarga estado) {
    return switch (estado) {
      DescargaFallida(:final failure) => actual.copiar(
        enCola: false,
        bajando: false,
        falla: failure,
      ),
      DescargaPausada(:final sigueSola) => actual.copiar(
        enCola: sigueSola,
        bajando: false,
        sinFalla: true,
      ),
      DescargaEnCurso() ||
      DescargaVerificando() => actual.copiar(enCola: false, bajando: true, sinFalla: true),
      DescargaCompletada() ||
      DescargaEliminada() => actual.copiar(enCola: false, bajando: false, sinFalla: true),
    };
  }

  /// El colportor tocó «Descargar mapa».
  Future<void> pedir() async {
    if (state.ocupada || state.enCola || state.bajando) return;
    if (!ambito.conocido) {
      state = state.copiar(falla: const FailureCiudadRequerida());
      return;
    }
    final paquete = _paquete;
    if (paquete == null) {
      state = state.copiar(enEspera: true, sinFalla: true);
      return;
    }
    await _iniciar(paquete);
  }

  Future<void> _iniciar(PaqueteTiles paquete) async {
    if (state.ocupada) return;
    state = state.copiar(ocupada: true, enEspera: false, sinFalla: true);
    Failure? falla;
    try {
      final resultado = await ref.read(descargarPaqueteTilesUseCaseProvider)(
        DescargarPaqueteTilesParams(
          paquete: paquete,
          permitirDatosMoviles: true,
          esperarConexion: true,
        ),
      );
      falla = resultado.fold((f) => f, (_) => null);
    } on Object catch (error) {
      falla = FailureInesperado(causa: error);
    }
    if (!ref.mounted) return;
    if (falla != null) {
      state = state.copiar(ocupada: false, falla: falla);
      return;
    }
    // El descargador aceptó el pedido: o quedó en cola (sin conexión) o ya está bajando. Se le
    // pregunta ahora, sin esperar el próximo cambio, para que el botón no se habilite en el medio:
    // hasta el primer `DescargaEnCurso` (la espera de los encabezados, hasta 30 s) su último estado
    // es el de antes o ninguno, así que no se lo lee de ahí. Una falla que llegó mientras tanto se
    // conserva; una vieja ya se limpió al empezar.
    final siguiente = state.copiar(ocupada: false);
    if (_estaDescargando(paquete)) {
      state = siguiente.copiar(enCola: false, bajando: true);
      return;
    }
    final actual = _estadoDelDescargador(paquete);
    state = actual == null || actual is DescargaFallida
        ? siguiente
        : _segunEstado(siguiente, actual);
  }

  bool _estaDescargando(PaqueteTiles paquete) =>
      _descargador()?.estaDescargando(paquete.id) ?? false;

  EstadoDescarga? _estadoDelDescargador(PaqueteTiles paquete) =>
      _descargador()?.estadoDe(paquete.id);
}

final solicitudMapaProvider =
    NotifierProvider.family<SolicitudMapaNotifier, EstadoSolicitudMapa, AmbitoTrabajo>(
      SolicitudMapaNotifier.new,
    );
