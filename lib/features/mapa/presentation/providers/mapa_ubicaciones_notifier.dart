import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/consulta_lista_ubicaciones.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import 'lista_ubicaciones_providers.dart';
import 'mapa_ubicaciones_state.dart';
import 'ubicacion_colportor_provider.dart';

export 'mapa_ubicaciones_state.dart';

/// El estado y las reglas del mapa de ubicaciones (vista 06, HU-UBI-003): todas las ubicaciones
/// activas del colportor por cercanía, el GPS y la ubicación seleccionada.
///
/// Reusa la consulta de la lista (`ConsultarListaUbicacionesUseCase`, reactiva) sin filtros ni
/// páginas: el mapa dibuja todas, y la hoja las muestra de la más cercana a la más lejana. Lo mismo
/// que la lista, el GPS **no es suyo**: lo lee de [ubicacionColportorProvider] (#651), el único GPS
/// del colportor, que pide el permiso al entrar a la pestaña (`MapaUbicacionesPage`); sin GPS el mapa
/// funciona igual, sin cercanía.
///
/// Es un estado propio, no el de la lista: filtrar o buscar en «Lista» no cambia el mapa.
final class MapaUbicacionesNotifier extends Notifier<MapaUbicacionesState> {
  MapaUbicacionesNotifier(this.colportorId);

  /// UUID del colportor con la sesión iniciada (`created_by`).
  final String colportorId;

  /// «Todas»: la consulta resuelve todo en memoria sobre las ubicaciones del colportor (cientos).
  static const _todas = 1 << 20;

  StreamSubscription<ListaUbicaciones>? _suscripcion;

  final _log = AppLogger.instance;

  @override
  MapaUbicacionesState build() {
    // Si la base se abre (o se cierra) después de montar la pestaña, el estado se rearma desde cero.
    ref.watch(dbLocalProvider);
    ref.onDispose(() => unawaited(_suscripcion?.cancel()));
    // El GPS es el del colportor, uno solo: acá se refleja lo que él sabe (la última posición queda
    // al reabrir la pestaña) y se vuelve a ordenar si la posición cambia.
    final ubicacion = ref.read(ubicacionColportorProvider);
    ref.listen(ubicacionColportorProvider, (_, nueva) => _seguirAlGps(nueva));
    // Todavía no hay `state` dentro de `build`: la primera lectura sale en el microtask que sigue.
    scheduleMicrotask(() {
      if (ref.mounted) _suscribir();
    });
    return MapaUbicacionesState(
      gps: ubicacion.gps,
      lectura: ubicacion.lectura,
      motivoSinGps: ubicacion.motivoSinGps,
    );
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
  void seleccionar(String ubicacionId) =>
      state = state.copyWith(seleccionadaId: ubicacionId, borrarCandidatas: true);

  /// El toque cayó sobre varias ubicaciones que no se separan ni con el zoom máximo (vista 39, E·06):
  /// la hoja pide elegir entre [ubicacionIds], de la más cercana al toque a la más lejana.
  void elegirEntre(List<String> ubicacionIds) =>
      state = state.copyWith(candidatasIds: ubicacionIds, borrarSeleccion: true);

  /// La ✕ de la vista previa (o del «Elegí cuál»): la hoja vuelve a la lista.
  void cerrarSeleccion() => state = state.copyWith(borrarSeleccion: true, borrarCandidatas: true);

  // ---------------------------------------------------------------- GPS

  /// Lo que dice el GPS del colportor ([ubicacionColportorProvider]). Solo si cambió la posición la
  /// lista se vuelve a pedir: ordena y mide con ella.
  void _seguirAlGps(UbicacionColportorState ubicacion) {
    final antes = state.posicion;
    state = state.copyWith(
      gps: ubicacion.gps,
      lectura: ubicacion.lectura,
      motivoSinGps: ubicacion.motivoSinGps,
      borrarMotivo: ubicacion.motivoSinGps == null,
    );
    if (state.posicion != antes) _suscribir();
  }
}

/// El estado del mapa de ubicaciones del colportor [colportorId]. Se descarta cuando la pestaña
/// deja de estar montada.
final mapaUbicacionesProvider = NotifierProvider.autoDispose
    .family<MapaUbicacionesNotifier, MapaUbicacionesState, String>(MapaUbicacionesNotifier.new);
