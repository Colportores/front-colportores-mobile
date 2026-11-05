import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/consulta_lista_ubicaciones.dart';
import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/lista_ubicaciones.dart';
import '../../domain/entities/ubicacion.dart';
import 'lista_ubicaciones_providers.dart';
import 'lista_ubicaciones_state.dart';
import 'ubicacion_colportor_provider.dart';

export 'lista_ubicaciones_state.dart';

/// El estado y las reglas de la lista de ubicaciones (vista 05, HU-UBI-002): filtros, búsqueda,
/// orden, carga de a 50 y GPS.
///
/// - La lista es **reactiva**: se suscribe a `ConsultarListaUbicacionesUseCase` y cualquier alta,
///   baja o edición la vuelve a emitir. Cada cambio de filtro, orden, búsqueda, posición o página
///   cancela la suscripción anterior y abre otra: nunca quedan dos vivas.
/// - Al cambiar la consulta se **conserva la lista anterior** hasta que llega la nueva.
/// - El GPS **no es de la lista**: lo lee de [ubicacionColportorProvider] (#651), el único GPS del
///   colportor, que pide el permiso solo desde el mapa. Si no hay GPS la lista funciona igual: sin
///   cercanía ni proximidad.
final class ListaUbicacionesNotifier extends Notifier<ListaUbicacionesState> {
  /// [clave] es el UUID del colportor, o ese UUID con [sufijoDeSeleccion] cuando la lista es un selector
  /// (la pestaña Lista y el selector de casa de «+ Agendar» no comparten búsqueda ni filtros).
  ListaUbicacionesNotifier(String clave) : colportorId = clave.split(sufijoDeSeleccion).first;

  /// Lo que se le agrega al UUID para tener un estado propio, aparte del de la pestaña Lista.
  static const sufijoDeSeleccion = '#seleccion';

  /// La clave del estado de la lista usada como selector del colportor [colportorId].
  static String claveDeSeleccion(String colportorId) => '$colportorId$sufijoDeSeleccion';

  /// UUID del colportor con la sesión iniciada (`created_by`).
  final String colportorId;

  StreamSubscription<ListaUbicaciones>? _suscripcion;

  /// Ya se pidió la página siguiente y todavía no llegó: un segundo pedido no hace nada.
  bool _cargandoMas = false;

  final _log = AppLogger.instance;

  @override
  ListaUbicacionesState build() {
    // Si la base se abre (o se cierra) después de montar la pestaña, el estado se rearma desde cero.
    ref.watch(dbLocalProvider);
    _cargandoMas = false;
    ref.onDispose(() => unawaited(_suscripcion?.cancel()));
    // El GPS es el del colportor, uno solo: acá se refleja lo que él sabe y se vuelve a ordenar si
    // la posición cambia.
    final ubicacion = ref.read(ubicacionColportorProvider);
    ref.listen(ubicacionColportorProvider, (_, nueva) => _seguirAlGps(nueva));
    // Todavía no hay `state` dentro de `build`: la primera lectura sale en el microtask que sigue.
    scheduleMicrotask(() {
      if (ref.mounted) _suscribir();
    });
    return ListaUbicacionesState(
      gps: ubicacion.gps,
      lectura: ubicacion.lectura,
      motivoSinGps: ubicacion.motivoSinGps,
    );
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

/// El estado de la lista de ubicaciones del colportor [colportorId]. Se descarta cuando la pestaña
/// deja de estar montada.
final listaUbicacionesProvider = NotifierProvider.autoDispose
    .family<ListaUbicacionesNotifier, ListaUbicacionesState, String>(ListaUbicacionesNotifier.new);
