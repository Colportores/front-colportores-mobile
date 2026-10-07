import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../tiles/domain/entities/paquete_tiles.dart' show AmbitoTrabajo;
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/resultado_modificacion_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/services/geocodificador_inverso.dart';
import '../../domain/usecases/modificar_ubicacion_use_case.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';
import 'alta_ubicacion_providers.dart';
import 'modificar_ubicacion_providers.dart';

/// Con qué se abre la edición de una ubicación (vista 07).
final class ParametrosModificar extends Equatable {
  const ParametrosModificar({
    required this.colportorId,
    required this.ubicacionId,
    this.apertura = 0,
  });

  /// UUID del colportor con la sesión iniciada: quien la modifica.
  final String colportorId;

  /// La ubicación que se edita.
  final String ubicacionId;

  /// Qué apertura de la pantalla es: cada vez que se abre es una distinta, así que una edición nueva
  /// arranca desde lo que hay guardado aunque el borrador de la anterior todavía no se haya
  /// descartado.
  final int apertura;

  @override
  List<Object?> get props => [colportorId, ubicacionId, apertura];
}

/// Cómo va la lectura de la ubicación que se edita.
enum CargaEdicion {
  /// Leyéndola del teléfono.
  cargando,

  /// Está cargada: se puede editar.
  lista,

  /// No está en el teléfono (otra pantalla la sacó, o el id no es de acá).
  noExiste,

  /// No se pudo leer: se puede reintentar.
  noSePudoLeer,
}

/// Qué muestra la hoja de abajo: el formulario («Editar ubicación») o el ajuste del punto («Mover el
/// punto»).
enum ModoEdicion { datos, moverPunto }

/// Todo lo que muestra la edición de ubicación (vista 07): lo guardado, el borrador y el ajuste del
/// punto.
final class ModificarUbicacionState extends Equatable {
  const ModificarUbicacionState({
    this.carga = CargaEdicion.cargando,
    this.fallaCarga,
    this.original,
    this.espacios,
    this.tipo,
    this.ciudadId,
    this.ciudadNombre,
    this.calle = '',
    this.numero = '',
    this.punto,
    this.modo = ModoEdicion.datos,
    this.puntoMover,
    this.propuesta,
    this.movimientosCamara = 0,
    this.lectura,
    this.guardando = false,
    this.falla,
  });

  final CargaEdicion carga;

  /// Por qué no se pudo leer ([CargaEdicion.noSePudoLeer]).
  final Failure? fallaCarga;

  /// La ubicación como está guardada: lo que la pantalla leyó al abrirse. De acá sale la base del
  /// control de edición concurrente (`updated_at`).
  final Ubicacion? original;

  /// Cuántos espacios sin baja tiene; `null` si no se pudo contar (el caso de uso igual bloquea el
  /// cambio de edificio a otro tipo).
  final int? espacios;

  // El borrador: lo que quedaría guardado.
  final TipoUbicacion? tipo;
  final String? ciudadId;

  /// El nombre de [ciudadId]; `null` si no se pudo leer la campaña (hasta el adaptador real de
  /// #274): el campo dice «Ciudad» y el guardado sigue con el id.
  final String? ciudadNombre;
  final String calle;
  final String numero;
  final Coordenadas? punto;

  final ModoEdicion modo;

  /// El pin mientras se ajusta el punto («Mover el punto»): todavía no es el del borrador.
  final Coordenadas? puntoMover;

  /// La dirección que el mapa conoce de [puntoMover], para «El punto está en … Usar …».
  final DireccionDelPunto? propuesta;

  /// Cuántas veces la pantalla tiene que centrar el mapa en el punto que corresponde al modo.
  final int movimientosCamara;

  /// La última lectura del GPS que pidió «Volver a mi ubicación»; `null` si todavía no se pidió.
  final LecturaGps? lectura;

  final bool guardando;

  /// Por qué falló el último intento de guardar.
  final Failure? falla;

  /// De dónde salen los tiles del mapa: la zona de la ubicación y, si la ciudad cambió, la ciudad
  /// nueva (la zona de antes ya no es la suya).
  AmbitoTrabajo get ambitoMapa =>
      AmbitoTrabajo(zonaId: ciudadCambiada ? null : original?.zonaId, ciudadId: ciudadId);

  /// El punto que se ve en el mapa: el del ajuste, o el del borrador.
  Coordenadas? get puntoVisible => modo == ModoEdicion.moverPunto ? puntoMover : punto;

  /// Lo que se mueve el punto para que cuente como movido: menos de un metro es el mismo punto (la
  /// pantalla no dibuja ningún movimiento y «Guardar posición» no lo pasa al borrador).
  static const metrosParaMovido = 1.0;

  String _t(String? s) => (s ?? '').trim();

  bool get tipoCambiado => original != null && tipo != original!.tipo;
  bool get ciudadCambiada => original != null && ciudadId != original!.ciudadId;
  bool get calleCambiada => original != null && _t(calle) != _t(original!.calle);
  bool get numeroCambiado => original != null && _t(numero) != _t(original!.numero);
  bool get puntoCambiado => original != null && punto != original!.coordenadas;

  bool get hayCambios =>
      tipoCambiado || ciudadCambiada || calleCambiada || numeroCambiado || puntoCambiado;

  /// Cuántos metros se corrió el punto respecto de la ubicación guardada (lo que mide el aviso de
  /// más de 100 m), o `null` si todavía no hay punto.
  double? get metrosMovidos {
    final p = puntoVisible;
    final o = original;
    if (p == null || o == null) return null;
    return p.distanciaMetrosA(o.coordenadas);
  }

  /// S17: de edificio a otro tipo con espacios activos no se puede (HU-UBI-004). Es la cantidad de
  /// espacios, o `null` si el borrador no cae en el bloqueo.
  int? get bloqueoPorEspacios {
    final cantidad = espacios;
    if (original?.tipo == TipoUbicacion.edificio &&
        tipo != null &&
        tipo != TipoUbicacion.edificio &&
        cantidad != null &&
        cantidad > 0) {
      return cantidad;
    }
    return null;
  }

  /// La ubicación cambió mientras se editaba: el borrador ya no se puede guardar (hay que volver a
  /// partir de lo que hay).
  bool get desactualizada => falla is FailureUbicacionCambio;

  /// «Guardar cambios» se habilita recién cuando hay un cambio (canvas 07).
  bool get puedeGuardar =>
      carga == CargaEdicion.lista &&
      modo == ModoEdicion.datos &&
      !guardando &&
      hayCambios &&
      bloqueoPorEspacios == null &&
      !desactualizada &&
      punto != null &&
      tipo != null &&
      ciudadId != null;

  /// Qué cambió, para «Cambiaste el tipo y el número…» (artboard 07·04).
  List<String> get cambios => [
    if (tipoCambiado) 'el tipo',
    if (ciudadCambiada) 'la ciudad',
    if (calleCambiada) 'la calle',
    if (numeroCambiado) 'el número',
    if (puntoCambiado) 'la posición',
  ];

  ModificarUbicacionState copyWith({
    CargaEdicion? carga,
    Failure? fallaCarga,
    bool borrarFallaCarga = false,
    Ubicacion? original,
    int? espacios,
    bool borrarEspacios = false,
    TipoUbicacion? tipo,
    String? ciudadId,
    String? ciudadNombre,
    bool borrarCiudadNombre = false,
    String? calle,
    String? numero,
    Coordenadas? punto,
    ModoEdicion? modo,
    Coordenadas? puntoMover,
    DireccionDelPunto? propuesta,
    bool borrarPropuesta = false,
    int? movimientosCamara,
    LecturaGps? lectura,
    bool? guardando,
    Failure? falla,
    bool borrarFalla = false,
  }) => ModificarUbicacionState(
    carga: carga ?? this.carga,
    fallaCarga: borrarFallaCarga ? null : (fallaCarga ?? this.fallaCarga),
    original: original ?? this.original,
    espacios: borrarEspacios ? null : (espacios ?? this.espacios),
    tipo: tipo ?? this.tipo,
    ciudadId: ciudadId ?? this.ciudadId,
    ciudadNombre: borrarCiudadNombre ? null : (ciudadNombre ?? this.ciudadNombre),
    calle: calle ?? this.calle,
    numero: numero ?? this.numero,
    punto: punto ?? this.punto,
    modo: modo ?? this.modo,
    puntoMover: puntoMover ?? this.puntoMover,
    propuesta: borrarPropuesta ? null : (propuesta ?? this.propuesta),
    movimientosCamara: movimientosCamara ?? this.movimientosCamara,
    lectura: lectura ?? this.lectura,
    guardando: guardando ?? this.guardando,
    falla: borrarFalla ? null : (falla ?? this.falla),
  );

  @override
  List<Object?> get props => [
    carga,
    fallaCarga,
    original,
    espacios,
    tipo,
    ciudadId,
    ciudadNombre,
    calle,
    numero,
    punto,
    modo,
    puntoMover,
    propuesta,
    movimientosCamara,
    lectura,
    guardando,
    falla,
  ];
}

/// Qué pasó al tocar «Guardar cambios» (o «Crear igual» en el aviso de duplicado).
sealed class ResultadoGuardadoEdicion {
  const ResultadoGuardadoEdicion();
}

/// La ubicación quedó modificada en el teléfono (y el cambio, encolado para el sync): la pantalla
/// vuelve al mapa con ella seleccionada.
final class EdicionGuardada extends ResultadoGuardadoEdicion {
  const EdicionGuardada(this.ubicacion, {this.reactivada = false});

  final Ubicacion ubicacion;
  final bool reactivada;
}

/// Los valores del borrador son los que ya están guardados: no se escribió nada.
final class EdicionSinCambios extends ResultadoGuardadoEdicion {
  const EdicionSinCambios(this.ubicacion);

  final Ubicacion ubicacion;
}

/// Falta que el colportor confirme algo antes de escribir (vista 07: reactivar, cambiar la ciudad,
/// mover el punto más de 100 m). [pendientes] sale en el orden en que se preguntan.
final class EdicionRequiereConfirmacion extends ResultadoGuardadoEdicion {
  const EdicionRequiereConfirmacion(this.pendientes, {this.metros});

  final List<ConfirmacionModificacion> pendientes;

  /// Cuánto se movió el punto, si [pendientes] incluye el desplazamiento.
  final double? metros;
}

/// El cambio dejaría a la ubicación como otra o cerca de otra (aviso de duplicado, vista 04): no se
/// escribió nada.
final class EdicionConDuplicados extends ResultadoGuardadoEdicion {
  const EdicionConDuplicados(this.candidatas);

  final List<CandidataDuplicado> candidatas;
}

/// No se pudo guardar: el botón vuelve a quedar habilitado (salvo que la ubicación haya cambiado) y
/// [falla] es lo que se muestra.
final class EdicionFallida extends ResultadoGuardadoEdicion {
  const EdicionFallida(this.falla);

  final Failure falla;
}

/// No hizo nada: ya había un guardado en curso (doble toque), no hay cambios o no se puede guardar.
final class EdicionIgnorada extends ResultadoGuardadoEdicion {
  const EdicionIgnorada();
}

/// El estado y las reglas de la vista 07: lo guardado, el borrador (tipo, ciudad, calle, número y
/// punto) y el pedido de guardado.
///
/// - El borrador parte de lo guardado y solo se escribe al guardar: cerrar no cambia nada.
/// - «Mover el punto» ajusta un pin aparte; «Guardar posición» lo pasa al borrador y «Cancelar»
///   deja el borrador como estaba al entrar.
/// - Al mover el punto no se pisa la dirección cargada: se sugiere la del mapa ([usarNumeroDelMapa]).
/// - Una respuesta vieja (de un punto que ya se dejó) se descarta.
final class ModificarUbicacionNotifier extends Notifier<ModificarUbicacionState> {
  ModificarUbicacionNotifier(this.parametros);

  final ParametrosModificar parametros;

  Timer? _espera;
  int _secuencia = 0;
  int _secuenciaCarga = 0;
  int _secuenciaGps = 0;
  final _log = AppLogger.instance;

  /// El borrador al entrar a «Mover el punto», para «Cancelar».
  ({Coordenadas? punto, String calle, String numero})? _alEntrar;

  @override
  ModificarUbicacionState build() {
    ref.onDispose(() => _espera?.cancel());
    unawaited(Future<void>(() => ref.mounted ? _cargar() : null));
    return const ModificarUbicacionState();
  }

  // ---------------------------------------------------------------- lectura

  /// «Reintentar» de «No pudimos abrir la ubicación»: vuelve a leerla.
  Future<void> reintentarCarga() async {
    if (state.carga != CargaEdicion.noSePudoLeer) return;
    state = state.copyWith(carga: CargaEdicion.cargando, borrarFallaCarga: true);
    await _cargar();
  }

  /// «Abrir de nuevo» del aviso «Esta ubicación cambió mientras la editabas»: descarta el borrador y
  /// vuelve a leer la ubicación como está ahora, y la pantalla arranca de cero. No se mezcla lo
  /// cargado con los datos nuevos: podría pisar el cambio de otro.
  Future<void> abrirDeNuevo() async {
    if (!state.desactualizada || state.guardando || state.carga != CargaEdicion.lista) return;
    _cerrarAjuste();
    state = ModificarUbicacionState(movimientosCamara: state.movimientosCamara);
    await _cargar();
  }

  Future<void> _cargar() async {
    final numero = ++_secuenciaCarga;
    final repo = ref.read(ubicacionRepositoryProvider);
    try {
      final leida = await repo.obtener(parametros.ubicacionId);
      if (!ref.mounted || numero != _secuenciaCarga) return;
      final falla = leida.fold<Failure?>((f) => f, (_) => null);
      if (falla != null) {
        state = state.copyWith(carga: CargaEdicion.noSePudoLeer, fallaCarga: falla);
        return;
      }
      final ubicacion = leida.getOrElse(() => null);
      if (ubicacion == null) {
        state = state.copyWith(carga: CargaEdicion.noExiste);
        return;
      }
      final cuenta = await repo.contarEspaciosActivos(ubicacion.id);
      if (!ref.mounted || numero != _secuenciaCarga) return;
      final nombre = await _nombreDeCiudad(ubicacion.ciudadId);
      if (!ref.mounted || numero != _secuenciaCarga) return;
      state = ModificarUbicacionState(
        carga: CargaEdicion.lista,
        original: ubicacion,
        espacios: cuenta.fold<int?>((_) => null, (n) => n),
        tipo: ubicacion.tipo,
        ciudadId: ubicacion.ciudadId,
        ciudadNombre: nombre,
        calle: ubicacion.calle ?? '',
        numero: ubicacion.numero ?? '',
        punto: ubicacion.coordenadas,
        movimientosCamara: state.movimientosCamara + 1,
      );
    } on Object catch (e, st) {
      _log.error(
        LogModulo.map,
        'EDICION_CARGA_FAIL',
        'no se pudo leer la ubicación',
        const {},
        e,
        st,
      );
      if (!ref.mounted || numero != _secuenciaCarga) return;
      state = state.copyWith(
        carga: CargaEdicion.noSePudoLeer,
        fallaCarga: FailureInesperado(causa: e),
      );
    }
  }

  /// El nombre de la ciudad [id] entre las de la campaña, o `null` si no se pudieron leer o ya no
  /// está: el campo dice «Ciudad» y el guardado sigue con el id.
  Future<String?> _nombreDeCiudad(String id) async {
    try {
      final r = await ref.read(ciudadesParaAltaProvider).deMiCampania(parametros.colportorId);
      return r.fold<String?>((_) => null, (ciudades) {
        for (final c in ciudades) {
          if (c.id == id) return c.nombre;
        }
        return null;
      });
    } on Object {
      return null;
    }
  }

  // ---------------------------------------------------------------- el formulario

  bool get _editable => state.carga == CargaEdicion.lista && !state.guardando;

  void elegirTipo(TipoUbicacion tipo) {
    if (!_editable) return;
    state = state.copyWith(tipo: tipo, borrarFalla: !state.desactualizada);
  }

  void editarCalle(String texto) {
    if (!_editable) return;
    state = state.copyWith(calle: texto, borrarFalla: !state.desactualizada);
  }

  void editarNumero(String texto) {
    if (!_editable) return;
    state = state.copyWith(numero: texto, borrarFalla: !state.desactualizada);
  }

  /// «Cambiar»: la ciudad la elige el colportor de la lista de su campaña.
  void elegirCiudad(CiudadCatalogo ciudad) {
    if (!_editable) return;
    state = state.copyWith(
      ciudadId: ciudad.id,
      ciudadNombre: ciudad.nombre,
      borrarFalla: !state.desactualizada,
    );
  }

  // ---------------------------------------------------------------- mover el punto

  /// «Mover el punto»: el mapa se puede arrastrar y el pin parte del punto del borrador.
  void entrarAMoverPunto() {
    final punto = state.punto;
    if (!_editable || state.modo == ModoEdicion.moverPunto || punto == null) return;
    _alEntrar = (punto: punto, calle: state.calle, numero: state.numero);
    state = state.copyWith(
      modo: ModoEdicion.moverPunto,
      puntoMover: punto,
      borrarPropuesta: true,
      borrarFalla: !state.desactualizada,
      movimientosCamara: state.movimientosCamara + 1,
    );
    _programarDireccion(inmediato: true);
  }

  /// El colportor movió el mapa: el pin (fijo en el centro) queda en [punto].
  void moverPunto(Coordenadas punto) {
    if (state.modo != ModoEdicion.moverPunto || state.guardando) return;
    if (state.puntoMover == punto) return;
    state = state.copyWith(puntoMover: punto);
    _programarDireccion();
  }

  /// El colportor tocó el mapa donde está el lugar: el mapa se centra ahí.
  void marcarPunto(Coordenadas punto) {
    if (state.modo != ModoEdicion.moverPunto || state.guardando) return;
    state = state.copyWith(puntoMover: punto, movimientosCamara: state.movimientosCamara + 1);
    _programarDireccion();
  }

  /// «Volver a mi ubicación»: el pin va a la lectura actual del GPS. Devuelve por qué no se pudo, o
  /// `null` si el pin se movió. Dos pedidos seguidos: gana el último.
  Future<Failure?> volverAMiUbicacion() async {
    if (state.modo != ModoEdicion.moverPunto || state.guardando) return null;
    final numero = ++_secuenciaGps;
    final resultado = await ref.read(capturarPosicionGpsUseCaseProvider)(const NoParams());
    if (!ref.mounted || numero != _secuenciaGps || state.modo != ModoEdicion.moverPunto) {
      return null;
    }
    return resultado.fold<Failure?>((falla) => falla, (lectura) {
      state = state.copyWith(
        puntoMover: lectura.coordenadas,
        lectura: lectura,
        movimientosCamara: state.movimientosCamara + 1,
      );
      _programarDireccion(inmediato: true);
      return null;
    });
  }

  /// «Usar 1250»: toma el número del mapa para el borrador.
  void usarNumeroDelMapa() {
    final numero = state.propuesta?.numero?.trim();
    if (!_editable || numero == null || numero.isEmpty) return;
    state = state.copyWith(numero: numero, borrarFalla: !state.desactualizada);
  }

  /// «Usar Av. Italia»: toma la calle del mapa para el borrador.
  void usarCalleDelMapa() {
    final calle = state.propuesta?.calle?.trim();
    if (!_editable || calle == null || calle.isEmpty) return;
    state = state.copyWith(calle: calle, borrarFalla: !state.desactualizada);
  }

  /// «Guardar posición»: el pin pasa al borrador (todavía no se escribe nada en el teléfono).
  ///
  /// Un pin a menos de un metro de lo guardado es el mismo punto: el borrador vuelve a la coordenada
  /// guardada y no cuenta como cambio de posición.
  void guardarPosicion() {
    if (state.modo != ModoEdicion.moverPunto || state.guardando) return;
    final original = state.original?.coordenadas;
    var pin = state.puntoMover;
    if (pin != null &&
        original != null &&
        pin.distanciaMetrosA(original) < ModificarUbicacionState.metrosParaMovido) {
      pin = original;
    }
    _cerrarAjuste();
    state = state.copyWith(
      modo: ModoEdicion.datos,
      punto: pin,
      borrarPropuesta: true,
      movimientosCamara: state.movimientosCamara + 1,
    );
  }

  /// «Cancelar» (o la ✕, o atrás) en «Mover el punto»: el borrador queda como estaba al entrar.
  void cancelarMoverPunto() {
    if (state.modo != ModoEdicion.moverPunto || state.guardando) return;
    final antes = _alEntrar;
    _cerrarAjuste();
    state = state.copyWith(
      modo: ModoEdicion.datos,
      punto: antes?.punto,
      calle: antes?.calle,
      numero: antes?.numero,
      borrarPropuesta: true,
      movimientosCamara: state.movimientosCamara + 1,
    );
  }

  void _cerrarAjuste() {
    _espera?.cancel();
    _secuencia++;
    _secuenciaGps++;
    _alEntrar = null;
  }

  void _programarDireccion({bool inmediato = false}) {
    _espera?.cancel();
    final secuencia = ++_secuencia;
    if (inmediato) {
      unawaited(_pedirDireccion(secuencia));
      return;
    }
    _espera = Timer(ref.read(esperaPuntoAltaProvider), () => unawaited(_pedirDireccion(secuencia)));
  }

  Future<void> _pedirDireccion(int secuencia) async {
    final punto = state.puntoMover;
    if (punto == null || !ref.mounted) return;
    DireccionDelPunto? direccion;
    try {
      direccion = await ref.read(geocodificadorInversoProvider).direccionDe(punto);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.map,
        'EDICION_DIRECCION_FAIL',
        'no se pudo leer la dirección',
        const {},
        e,
        st,
      );
    }
    if (!ref.mounted || secuencia != _secuencia || state.modo != ModoEdicion.moverPunto) return;
    state = state.copyWith(propuesta: direccion, borrarPropuesta: direccion == null);
  }

  // ---------------------------------------------------------------- guardar

  /// «Guardar cambios». Un solo guardado a la vez: un segundo toque mientras el primero sigue en
  /// curso no hace nada. [confirmadas] son las confirmaciones que el colportor ya dio y
  /// [justificacion] el «Crear igual» del aviso de duplicado.
  Future<ResultadoGuardadoEdicion> guardar({
    Set<ConfirmacionModificacion> confirmadas = const {},
    String? justificacion,
  }) async {
    final original = state.original;
    final punto = state.punto;
    final tipo = state.tipo;
    if (state.guardando ||
        original == null ||
        punto == null ||
        tipo == null ||
        state.modo != ModoEdicion.datos ||
        state.carga != CargaEdicion.lista ||
        state.desactualizada ||
        !state.hayCambios) {
      return const EdicionIgnorada();
    }

    state = state.copyWith(guardando: true, borrarFalla: true);
    try {
      final resultado = await ref.read(modificarUbicacionUseCaseProvider)(
        ModificarUbicacionParams(
          id: original.id,
          colportorId: parametros.colportorId,
          tipo: tipo,
          coordenadas: punto,
          baseUpdatedAt: original.auditoria.updatedAt,
          ciudadId: state.ciudadId,
          calle: state.calle,
          numero: state.numero,
          confirmadas: confirmadas,
          justificacionDuplicado: justificacion,
        ),
      );
      if (!ref.mounted) return const EdicionIgnorada();
      return resultado.fold<ResultadoGuardadoEdicion>(_alFallar, (r) {
        switch (r) {
          case UbicacionModificada(:final ubicacion, :final reactivada):
            // La pantalla se cierra con el resultado: «guardando» queda en alto hasta entonces
            // para que no se pueda tocar otra vez.
            return EdicionGuardada(ubicacion, reactivada: reactivada);
          case ModificacionSinCambios(:final ubicacion):
            state = state.copyWith(guardando: false);
            return EdicionSinCambios(ubicacion);
          case ModificacionRequiereConfirmacion(:final pendientes, :final desplazamientoMetros):
            state = state.copyWith(guardando: false);
            final orden = [...pendientes]..sort((a, b) => a.index.compareTo(b.index));
            return EdicionRequiereConfirmacion(orden, metros: desplazamientoMetros);
          case ModificacionConDuplicados(:final candidatas):
            state = state.copyWith(guardando: false);
            return EdicionConDuplicados(candidatas);
        }
      });
    } on Object catch (e, st) {
      _log.error(LogModulo.map, 'EDICION_UBICACION_FAIL', 'no se pudo guardar', const {}, e, st);
      if (!ref.mounted) return const EdicionIgnorada();
      return _alFallar(FailureInesperado(causa: e));
    }
  }

  /// Con [FailureUbicacionCambio] el borrador queda a la vista pero ya no se puede guardar
  /// ([ModificarUbicacionState.desactualizada]): el aviso dice «Abrila de nuevo y repetí el cambio».
  ResultadoGuardadoEdicion _alFallar(Failure falla) {
    state = state.copyWith(guardando: false, falla: falla);
    return EdicionFallida(falla);
  }
}

/// El estado de la edición de [ParametrosModificar]; se descarta al cerrar la pantalla.
final modificarUbicacionProvider = NotifierProvider.autoDispose
    .family<ModificarUbicacionNotifier, ModificarUbicacionState, ParametrosModificar>(
      ModificarUbicacionNotifier.new,
    );
