import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/consulta_lista_ubicaciones.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import 'alta_ubicacion_providers.dart';
import 'lista_ubicaciones_providers.dart';
import 'lista_ubicaciones_state.dart';

export 'lista_ubicaciones_state.dart';

/// El estado y las reglas de la lista de ubicaciones (vista 05, HU-UBI-002): filtros, búsqueda,
/// orden, carga de a 50 y GPS.
///
/// - La lista es **reactiva**: se suscribe a `ConsultarListaUbicacionesUseCase` y cualquier alta,
///   baja o edición la vuelve a emitir. Cada cambio de filtro, orden, búsqueda, posición o página
///   cancela la suscripción anterior y abre otra: nunca quedan dos vivas.
/// - Al cambiar la consulta se **conserva la lista anterior** hasta que llega la nueva.
/// - El GPS se pide la primera vez que la pestaña se abre (no al arrancar la app, que lo
///   pediría detrás del login) y se refresca cada vez que se vuelve a abrir. Si no hay GPS la lista
///   funciona igual: sin cercanía ni proximidad.
final class ListaUbicacionesNotifier extends Notifier<ListaUbicacionesState> {
  ListaUbicacionesNotifier(this.colportorId);

  /// UUID del colportor con la sesión iniciada (`created_by`).
  final String colportorId;

  StreamSubscription<ListaUbicaciones>? _suscripcion;

  /// Cuál es la última lectura del GPS que se pidió: una que llega cuando ya se pidió otra se
  /// ignora, así la posición con la que se ordena es siempre la última.
  int _secuenciaGps = 0;

  /// Ya se pidió la página siguiente y todavía no llegó: un segundo pedido no hace nada.
  bool _cargandoMas = false;

  /// El colportor tocó «Activar GPS» y se lo mandó al permiso o a los ajustes del sistema: solo
  /// entonces tiene sentido volver a leer el GPS cuando regrese a la app. Cualquier otro regreso
  /// (volver de WhatsApp) no puede volver a mostrarle el diálogo del permiso.
  bool _enAjustes = false;

  final _log = AppLogger.instance;

  @override
  ListaUbicacionesState build() {
    // Si la base se abre (o se cierra) después de montar la pestaña, el estado se rearma desde cero.
    ref.watch(dbLocalProvider);
    _cargandoMas = false;
    _enAjustes = false;
    ref.onDispose(() => unawaited(_suscripcion?.cancel()));
    // Todavía no hay `state` dentro de `build`: la primera lectura sale en el microtask que sigue.
    scheduleMicrotask(() {
      if (ref.mounted) _suscribir();
    });
    return const ListaUbicacionesState();
  }

  // ---------------------------------------------------------------- lectura

  /// Abre la lista de la consulta actual. La anterior se cancela antes: nunca hay dos.
  void _suscribir() {
    unawaited(_suscripcion?.cancel());
    _suscripcion = null;
    final consulta = state.filtros.consulta(colportorId: colportorId, posicion: state.posicion);
    try {
      _suscripcion = ref
          .read(consultarListaUbicacionesUseCaseProvider)(consulta)
          .listen(
            (lista) {
              if (!ref.mounted) return;
              _cargandoMas = false;
              state = state.copyWith(lista: lista, fallaLectura: false);
            },
            onError: (Object error, StackTrace pila) {
              _log.error(
                LogModulo.db,
                'LISTA_UBICACIONES_FAIL',
                'no se pudo leer la lista de ubicaciones',
                const {},
                error,
                pila,
              );
              if (!ref.mounted) return;
              _cargandoMas = false;
              state = state.copyWith(fallaLectura: true);
            },
          );
    } on Object catch (error, pila) {
      // Sin base abierta el caso de uso ni se arma.
      _log.error(
        LogModulo.db,
        'LISTA_UBICACIONES_FAIL',
        'no se pudo abrir la lista de ubicaciones',
        const {},
        error,
        pila,
      );
      _cargandoMas = false;
      state = state.copyWith(fallaLectura: true);
    }
  }

  /// «Reintentar» tras un error de lectura.
  void reintentar() {
    state = state.copyWith(fallaLectura: false);
    _suscribir();
  }

  // ---------------------------------------------------------------- filtros

  /// Cambia los filtros y vuelve a la primera página.
  void _cambiarFiltros(FiltrosLista nuevos) {
    // Pedir lo mismo que ya se ve (aplicar sin tocar nada, Enter con el texto ya buscado) no hace
    // nada: la comparación no cuenta las páginas cargadas, así la lista no vuelve a las primeras 50.
    if (nuevos.copyWith(limite: state.filtros.limite) == state.filtros) return;
    final conPaginaInicial = nuevos.copyWith(limite: ConsultaListaUbicaciones.tamanoPagina);
    _cargandoMas = false;
    state = state.copyWith(filtros: conPaginaInicial);
    _suscribir();
  }

  /// La búsqueda por calle y número (solo local).
  void buscar(String texto) => _cambiarFiltros(state.filtros.copyWith(busqueda: texto));

  /// «Ver N ubicaciones»: aplica todo lo que se armó en la hoja. La búsqueda y el orden no se tocan.
  void aplicar({
    required Set<TipoUbicacion> tipos,
    required Set<EstadoCasa> estados,
    required String? ciudadId,
    required ProximidadLista proximidad,
    required bool incluirBajas,
  }) => _cambiarFiltros(
    state.filtros.copyWith(
      tipos: tipos,
      estados: estados,
      ciudadId: ciudadId,
      sinCiudad: ciudadId == null,
      proximidad: proximidad,
      incluirBajas: incluirBajas,
    ),
  );

  /// La ✕ del chip de un tipo.
  void quitarTipo(TipoUbicacion tipo) =>
      _cambiarFiltros(state.filtros.copyWith(tipos: {...state.filtros.tipos}..remove(tipo)));

  /// La ✕ del chip de un estado.
  void quitarEstado(EstadoCasa estado) =>
      _cambiarFiltros(state.filtros.copyWith(estados: {...state.filtros.estados}..remove(estado)));

  void quitarCiudad() => _cambiarFiltros(state.filtros.copyWith(sinCiudad: true));

  void quitarProximidad() =>
      _cambiarFiltros(state.filtros.copyWith(proximidad: ProximidadLista.cualquiera));

  void quitarBajas() => _cambiarFiltros(state.filtros.copyWith(incluirBajas: false));

  /// «Mostrar bajas» del vacío de quien solo tiene bajas: prende el mismo filtro que la hoja.
  void mostrarBajas() => _cambiarFiltros(state.filtros.copyWith(incluirBajas: true));

  /// «Limpiar filtros» del «sin resultados»: saca los filtros **y** la búsqueda.
  void limpiarTodo() => _cambiarFiltros(FiltrosLista(orden: state.filtros.orden));

  /// El orden de la lista. «Por cercanía» sin GPS no se puede elegir: la hoja de orden lo
  /// deshabilita, y si llegara igual, el dominio cae a «Última actualización».
  void ordenar(OrdenListaUbicaciones orden) =>
      _cambiarFiltros(state.filtros.copyWith(orden: orden));

  /// Pide la página siguiente (el «Cargando 50 más…» entró en pantalla). Dos pedidos seguidos antes
  /// de que llegue la primera suman una sola página.
  void cargarMas() {
    final lista = state.lista;
    if (_cargandoMas || lista == null || !lista.hayMas) return;
    _cargandoMas = true;
    state = state.copyWith(
      filtros: state.filtros.copyWith(
        limite: state.filtros.limite + ConsultaListaUbicaciones.tamanoPagina,
      ),
    );
    _suscribir();
  }

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

  /// «Activar GPS» (el chip de arriba cuando no hay): pide el permiso o abre el ajuste que
  /// corresponda y vuelve a leer.
  Future<void> activarGps() async {
    final motivo = state.motivoSinGps;
    if (motivo != null) {
      _enAjustes = true;
      await ref.read(activadorGpsProvider).activar(motivo);
    }
    await _leerGps();
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

/// El estado de la lista de ubicaciones del colportor [colportorId]. Se descarta cuando la pestaña
/// deja de estar montada.
final listaUbicacionesProvider = NotifierProvider.autoDispose
    .family<ListaUbicacionesNotifier, ListaUbicacionesState, String>(ListaUbicacionesNotifier.new);
