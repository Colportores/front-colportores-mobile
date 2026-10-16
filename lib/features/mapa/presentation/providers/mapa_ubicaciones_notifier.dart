import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/consulta_lista_ubicaciones.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import 'alta_ubicacion_providers.dart';
import 'lista_ubicaciones_providers.dart';
import 'mapa_ubicaciones_state.dart';

export 'mapa_ubicaciones_state.dart';

/// El estado y las reglas del mapa de ubicaciones (vista 06, HU-UBI-003): todas las ubicaciones
/// activas del colportor por cercanía, el GPS y la ubicación seleccionada.
///
/// Reusa la consulta de la lista (`ConsultarListaUbicacionesUseCase`, reactiva) sin filtros ni
/// páginas: el mapa dibuja todas, y la hoja las muestra de la más cercana a la más lejana. Lo mismo
/// que la lista, el GPS se pide la primera vez que la pestaña se abre (no al arrancar la app) y se
/// refresca cada vez que se vuelve a abrir; sin GPS el mapa funciona igual, sin cercanía.
///
/// Es un estado propio, no el de la lista: filtrar o buscar en «Lista» no cambia el mapa.
final class MapaUbicacionesNotifier extends Notifier<MapaUbicacionesState> {
  MapaUbicacionesNotifier(this.colportorId);

  /// UUID del colportor con la sesión iniciada (`created_by`).
  final String colportorId;

  /// «Todas»: la consulta resuelve todo en memoria sobre las ubicaciones del colportor (cientos).
  static const _todas = 1 << 20;

  StreamSubscription<ListaUbicaciones>? _suscripcion;

  /// Cuál es la última lectura del GPS que se pidió: una que llega cuando ya se pidió otra se
  /// ignora, así la posición con la que se ordena es siempre la última.
  int _secuenciaGps = 0;

  /// El colportor tocó «Activar GPS» y se lo mandó al permiso o a los ajustes del sistema: solo
  /// entonces tiene sentido volver a leer el GPS cuando regrese a la app. Cualquier otro regreso
  /// (volver de WhatsApp) no puede volver a mostrarle el diálogo del permiso.
  bool _enAjustes = false;

  /// «Activar GPS» ya está en curso: un segundo toque no abre otro diálogo del sistema encima.
  bool _activando = false;

  final _log = AppLogger.instance;

  @override
  MapaUbicacionesState build() {
    // Si la base se abre (o se cierra) después de montar la pestaña, el estado se rearma desde cero.
    ref.watch(dbLocalProvider);
    _enAjustes = false;
    ref.onDispose(() => unawaited(_suscripcion?.cancel()));
    // Todavía no hay `state` dentro de `build`: la primera lectura sale en el microtask que sigue.
    scheduleMicrotask(() {
      if (ref.mounted) _suscribir();
    });
    return const MapaUbicacionesState();
  }

  // ---------------------------------------------------------------- lectura

  /// Abre la lista con la posición de ahora. La anterior se cancela antes: nunca hay dos vivas.
  void _suscribir() {
    unawaited(_suscripcion?.cancel());
    _suscripcion = null;
    final consulta = ConsultaListaUbicaciones(
      colportorId: colportorId,
      orden: OrdenListaUbicaciones.cercania,
      posicion: state.posicion,
      limite: _todas,
    );
    try {
      _suscripcion = ref
          .read(consultarListaUbicacionesUseCaseProvider)(consulta)
          .listen(
            (lista) {
              if (!ref.mounted) return;
              state = state.copyWith(lista: lista, fallaLectura: false);
            },
            onError: (Object error, StackTrace pila) {
              _log.error(
                LogModulo.db,
                'MAPA_UBICACIONES_FAIL',
                'no se pudo leer las ubicaciones del mapa',
                const {},
                error,
                pila,
              );
              if (!ref.mounted) return;
              state = state.copyWith(fallaLectura: true);
            },
          );
    } on Object catch (error, pila) {
      // Sin base abierta el caso de uso ni se arma.
      _log.error(
        LogModulo.db,
        'MAPA_UBICACIONES_FAIL',
        'no se pudo abrir las ubicaciones del mapa',
        const {},
        error,
        pila,
      );
      state = state.copyWith(fallaLectura: true);
    }
  }

  /// «Reintentar» tras un error de lectura.
  void reintentar() {
    state = state.copyWith(fallaLectura: false);
    _suscribir();
  }

  // ---------------------------------------------------------------- selección

  /// El colportor tocó el marcador de [ubicacionId] (o volvió del alta con esa ubicación): se abre
  /// su vista previa.
  void seleccionar(String ubicacionId) => state = state.copyWith(seleccionadaId: ubicacionId);

  /// La ✕ de la vista previa: la hoja vuelve a la lista.
  void cerrarSeleccion() => state = state.copyWith(borrarSeleccion: true);

  // ---------------------------------------------------------------- GPS

  /// La pestaña se abrió: se pide el GPS la primera vez y se refresca las siguientes. Si la última
  /// vez falló por el permiso o por la ubicación apagada, **no** se vuelve a pedir sola (cada
  /// apertura mostraría el diálogo del permiso): se reintenta al volver de los ajustes
  /// ([reintentarGpsSiHaceFalta]).
  Future<void> alAbrirPestana() async {
    final sinPermisoOApagado =
        state.gps == EstadoGpsLista.sinGps && state.motivoSinGps != MotivoSinGps.sinSenal;
    if (sinPermisoOApagado || state.gps == EstadoGpsLista.buscando) return;
    await _leerGps();
  }

  /// Al volver a la app después de los ajustes (o del diálogo del permiso): si seguía sin GPS, se
  /// vuelve a intentar. Solo si el colportor había tocado «Activar GPS»; el regreso de cualquier
  /// otra app no hace nada.
  Future<void> reintentarGpsSiHaceFalta() async {
    if (!_enAjustes || state.gps != EstadoGpsLista.sinGps) return;
    _enAjustes = false;
    await _leerGps();
  }

  /// «Mi ubicación»: vuelve a leer el GPS (el colportor se movió desde la última lectura). Una lectura
  /// que falla no tira la última buena.
  Future<void> refrescarGps() => _leerGps();

  /// «Activar GPS»: pide el permiso o abre el ajuste que corresponda y vuelve a leer.
  Future<void> activarGps() async {
    if (_activando) return;
    _activando = true;
    try {
      final motivo = state.motivoSinGps;
      if (motivo != null) {
        _enAjustes = true;
        try {
          await ref.read(activadorGpsProvider).activar(motivo);
        } on Object catch (error, pila) {
          // El sistema no pudo abrir el permiso o los ajustes: se lee igual (puede que el
          // colportor lo haya dado por su cuenta) y «Activar GPS» sigue disponible.
          _log.error(
            LogModulo.map,
            'MAPA_UBICACIONES_GPS_FAIL',
            'no se pudo activar el GPS',
            const {},
            error,
            pila,
          );
        }
      }
      await _leerGps();
    } finally {
      _activando = false;
    }
  }

  Future<void> _leerGps() async {
    if (!ref.mounted) return;
    final numero = ++_secuenciaGps;
    if (state.gps != EstadoGpsLista.conLectura) {
      state = state.copyWith(gps: EstadoGpsLista.buscando, borrarMotivo: true);
    }
    final resultado = await ref.read(capturarPosicionGpsUseCaseProvider)(const NoParams());
    if (!ref.mounted || numero != _secuenciaGps) return;
    final antes = state.posicion;
    resultado.fold<void>(
      (falla) {
        // Un refresco que falla no tira la última posición buena: las distancias siguen sirviendo.
        if (state.lectura != null) {
          state = state.copyWith(gps: EstadoGpsLista.conLectura);
          return;
        }
        final motivo = falla is FailureGpsNoDisponible ? falla.motivo : MotivoSinGps.sinSenal;
        state = state.copyWith(gps: EstadoGpsLista.sinGps, motivoSinGps: motivo);
      },
      (lectura) {
        state = state.copyWith(
          gps: EstadoGpsLista.conLectura,
          lectura: lectura,
          borrarMotivo: true,
        );
      },
    );
    // Solo si cambió la posición la lista se vuelve a pedir: ordena y mide con ella.
    if (state.posicion != antes) _suscribir();
  }
}

/// El estado del mapa de ubicaciones del colportor [colportorId]. Se descarta cuando la pestaña
/// deja de estar montada.
final mapaUbicacionesProvider = NotifierProvider.autoDispose
    .family<MapaUbicacionesNotifier, MapaUbicacionesState, String>(MapaUbicacionesNotifier.new);
