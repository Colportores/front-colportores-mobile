import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../tiles/domain/entities/estado_descarga.dart';
import '../../../tiles/domain/entities/paquete_tiles.dart';
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
/// vuelve a preguntar solo cuando la conexión vuelve.
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
    if (conectado != true) return const PaqueteSinRed();
    try {
      final sugerido = await ref.read(sugerirPaqueteTilesUseCaseProvider)(ambito);
      return sugerido.fold<PaqueteDelAmbito>(
        (_) => const PaqueteNoDisponible(),
        (paquete) => paquete == null ? const PaqueteNoDisponible() : PaqueteHallado(paquete),
      );
    } on Object {
      return const PaqueteNoDisponible();
    }
  },
);

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
final class SolicitudMapaNotifier extends Notifier<EstadoSolicitudMapa> {
  SolicitudMapaNotifier(this.ambito);

  final AmbitoTrabajo ambito;

  /// El último paquete que el catálogo trajo para el ámbito: con él se puede encolar la descarga
  /// aunque ahora no haya conexión.
  PaqueteTiles? _paquete;

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
      final paquete = _paquete;
      if (paquete == null) return;
      if (nuevo case AsyncData(:final value) when value.paqueteId == paquete.id) {
        state = _segunEstado(state, value);
      }
    });
    return const EstadoSolicitudMapa();
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
    // El descargador aceptó el pedido: o quedó en cola (sin conexión) o ya está bajando. Se lee su
    // estado ahora, sin esperar el próximo cambio, para que el botón no se habilite en el medio. Una
    // falla vieja no cuenta: si esta vez falla, llega como cambio de estado.
    var siguiente = state.copiar(ocupada: false, sinFalla: true);
    final actual = _estadoDelDescargador(paquete);
    if (actual != null && actual is! DescargaFallida) siguiente = _segunEstado(siguiente, actual);
    state = siguiente;
  }

  EstadoDescarga? _estadoDelDescargador(PaqueteTiles paquete) {
    try {
      return ref.read(descargadorPaquetesTilesProvider).estadoDe(paquete.id);
    } on Object {
      return null;
    }
  }
}

final solicitudMapaProvider =
    NotifierProvider.family<SolicitudMapaNotifier, EstadoSolicitudMapa, AmbitoTrabajo>(
      SolicitudMapaNotifier.new,
    );
