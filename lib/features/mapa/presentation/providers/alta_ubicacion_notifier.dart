import 'dart:async';

import 'package:dartz/dartz.dart' show Either, Left;
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
import '../../domain/entities/resultado_alta_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/ciudades_para_alta.dart';
import '../../domain/services/geocodificador_inverso.dart';
import '../../domain/usecases/registrar_ubicacion_use_case.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';
import 'alta_ubicacion_providers.dart';

/// Con qué se abre el alta (vista 03).
final class ParametrosAlta extends Equatable {
  const ParametrosAlta({required this.colportorId, this.puntoInicial, this.apertura = 0});

  /// UUID del colportor con la sesión iniciada (`created_by`).
  final String colportorId;

  /// Si el alta llega por tap largo en el mapa (HU-UBI-003), el pin arranca en ese punto y la
  /// precisión se muestra como «Marcado a mano».
  final Coordenadas? puntoInicial;

  /// Qué apertura del alta es: cada vez que se abre la pantalla es una distinta, así que un alta
  /// nueva arranca de cero aunque el estado de la anterior todavía no se haya descartado.
  final int apertura;

  @override
  List<Object?> get props => [colportorId, puntoInicial, apertura];
}

/// Qué pasa con el GPS (el chip de arriba de la vista 03).
enum EstadoGps {
  /// Esperando la lectura.
  buscando,

  /// Hay una lectura utilizable ([AltaUbicacionState.lectura]).
  conLectura,

  /// Permiso denegado, ubicación apagada o sin señal ([AltaUbicacionState.motivoSinGps]).
  sinGps,
}

/// De dónde sale el texto de un campo de dirección (vista 03: «Del mapa», «Editado»).
enum FuenteCampo { vacio, delMapa, editado }

/// Calle o número: el texto y de dónde salió.
final class CampoDireccion extends Equatable {
  const CampoDireccion([this.texto = '', this.fuente = FuenteCampo.vacio]);

  final String texto;
  final FuenteCampo fuente;

  @override
  List<Object?> get props => [texto, fuente];
}

/// Cómo se llegó a la ciudad del alta (vista 03: «detectada», «de tu zona», «de tu campaña»).
///
/// La ciudad nunca limita el alta (decisión de Cristian, 02/10, en #267): siempre se propone una de
/// la campaña del colportor. Solo hay aviso si la campaña no tiene ciudades ([sinCiudades]) o si no
/// se pudieron leer ([noSePudoLeer]).
enum OrigenCiudad {
  /// Todavía no hay ciudad (esperando la propuesta).
  buscando,

  /// La ciudad de la zona de sus campañas que contiene el punto.
  detectada,

  /// La ciudad de la zona que tiene asignada.
  deZona,

  /// La única ciudad de su campaña o la que tiene el centro más cerca del punto.
  deCampania,

  /// La eligió el colportor: no se vuelve a pisar al mover el punto.
  elegida,

  /// La campaña tiene varias ciudades y todavía no hay punto con el que elegir entre ellas: se
  /// propone cuando lo haya, o la elige el colportor.
  porElegir,

  /// La campaña del colportor no tiene ciudades cargadas: aviso que guía, y «Registrar» espera.
  sinCiudades,

  /// No se pudieron leer las ciudades de la campaña: aviso con «Reintentar».
  noSePudoLeer,
}

/// Todo lo que muestra el alta de ubicación (vista 03).
final class AltaUbicacionState extends Equatable {
  const AltaUbicacionState({
    this.gps = EstadoGps.buscando,
    this.motivoSinGps,
    this.lectura,
    this.punto,
    this.origen = OrigenCoordenadas.gps,
    this.precisionDecidida = false,
    this.tipo,
    this.ciudad,
    this.origenCiudad = OrigenCiudad.buscando,
    this.calle = const CampoDireccion(),
    this.numero = const CampoDireccion(),
    this.propuesta,
    this.avisosCalle = 0,
    this.movimientosCamara = 0,
    this.guardando = false,
    this.falla,
  });

  final EstadoGps gps;
  final MotivoSinGps? motivoSinGps;

  /// La última lectura del GPS: es lo que usa «Volver a mi ubicación».
  final LecturaGps? lectura;

  /// El punto del pin, o `null` hasta que haya GPS o el colportor lo marque.
  final Coordenadas? punto;
  final OrigenCoordenadas origen;

  /// El colportor ya vio el aviso de baja precisión y eligió «Ajustar manualmente» o «Continuar».
  final bool precisionDecidida;

  final TipoUbicacion? tipo;

  final CiudadCatalogo? ciudad;
  final OrigenCiudad origenCiudad;

  final CampoDireccion calle;
  final CampoDireccion numero;

  /// La dirección que el mapa conoce del punto actual (para «El punto está en … Usar …»).
  final DireccionDelPunto? propuesta;

  /// Cuántas veces se actualizó sola la calle al mover el punto (dispara «Calle actualizada»).
  final int avisosCalle;

  /// Cuántas veces la pantalla tiene que centrar el mapa en [punto] (GPS, «Volver a mi
  /// ubicación», toque en el mapa).
  final int movimientosCamara;

  final bool guardando;

  /// Por qué falló el último intento de registrar.
  final Failure? falla;

  /// La precisión que muestra la vista: la del GPS, o `null` si el punto se marcó a mano.
  double? get precisionMetros => origen == OrigenCoordenadas.gps ? lectura?.precisionMetros : null;

  /// El punto es una lectura del GPS con peor precisión que 50 m (HU-UBI-001).
  bool get esImpreciso {
    final l = lectura;
    return origen == OrigenCoordenadas.gps && punto != null && l != null && _gps(l).esImpreciso;
  }

  /// «Registrar» espera a que el colportor elija «Ajustar manualmente» o «Continuar».
  bool get necesitaDecisionPrecision => esImpreciso && !precisionDecidida;

  /// Los datos mínimos del alta: punto, tipo y ciudad.
  bool get estaCompleto => punto != null && tipo != null && ciudad != null;

  bool get puedeRegistrar => !guardando && estaCompleto && !necesitaDecisionPrecision;

  static PuntoCapturado _gps(LecturaGps l) => PuntoCapturado.gps(l);

  AltaUbicacionState copyWith({
    EstadoGps? gps,
    MotivoSinGps? motivoSinGps,
    bool borrarMotivo = false,
    LecturaGps? lectura,
    Coordenadas? punto,
    OrigenCoordenadas? origen,
    bool? precisionDecidida,
    TipoUbicacion? tipo,
    CiudadCatalogo? ciudad,
    bool borrarCiudad = false,
    OrigenCiudad? origenCiudad,
    CampoDireccion? calle,
    CampoDireccion? numero,
    DireccionDelPunto? propuesta,
    bool borrarPropuesta = false,
    int? avisosCalle,
    int? movimientosCamara,
    bool? guardando,
    Failure? falla,
    bool borrarFalla = false,
  }) => AltaUbicacionState(
    gps: gps ?? this.gps,
    motivoSinGps: borrarMotivo ? null : (motivoSinGps ?? this.motivoSinGps),
    lectura: lectura ?? this.lectura,
    punto: punto ?? this.punto,
    origen: origen ?? this.origen,
    precisionDecidida: precisionDecidida ?? this.precisionDecidida,
    tipo: tipo ?? this.tipo,
    ciudad: borrarCiudad ? null : (ciudad ?? this.ciudad),
    origenCiudad: origenCiudad ?? this.origenCiudad,
    calle: calle ?? this.calle,
    numero: numero ?? this.numero,
    propuesta: borrarPropuesta ? null : (propuesta ?? this.propuesta),
    avisosCalle: avisosCalle ?? this.avisosCalle,
    movimientosCamara: movimientosCamara ?? this.movimientosCamara,
    guardando: guardando ?? this.guardando,
    falla: borrarFalla ? null : (falla ?? this.falla),
  );

  @override
  List<Object?> get props => [
    gps,
    motivoSinGps,
    lectura,
    punto,
    origen,
    precisionDecidida,
    tipo,
    ciudad,
    origenCiudad,
    calle,
    numero,
    propuesta,
    avisosCalle,
    movimientosCamara,
    guardando,
    falla,
  ];
}

/// Qué pasó al tocar «Registrar» (o «Crear igual»).
sealed class ResultadoRegistroAlta {
  const ResultadoRegistroAlta();
}

/// La ubicación quedó guardada: la pantalla vuelve al mapa con ella seleccionada.
final class AltaCreada extends ResultadoRegistroAlta {
  const AltaCreada(this.ubicacion);

  final Ubicacion ubicacion;
}

/// Hay ubicaciones que parecen la misma (vista 04): no se creó nada.
final class AltaConCandidatas extends ResultadoRegistroAlta {
  const AltaConCandidatas(this.candidatas);

  /// De la más cercana a la más lejana; nunca vacía.
  final List<CandidataDuplicado> candidatas;
}

/// No se pudo registrar: el botón vuelve a quedar habilitado y [falla] es lo que se muestra.
final class AltaFallida extends ResultadoRegistroAlta {
  const AltaFallida(this.falla);

  final Failure falla;
}

/// No hizo nada: ya había un registro en curso (doble toque) o falta tipo, punto o ciudad.
final class AltaIgnorada extends ResultadoRegistroAlta {
  const AltaIgnorada();
}

/// El estado y las reglas de la vista 03: GPS, punto, tipo, ciudad y dirección (con «Del mapa» y
/// «Editado»), y el pedido de registro.
///
/// - Calle y número se completan con la dirección del punto y se actualizan al mover el mapa,
///   salvo el campo que el colportor escribió: ese queda «Editado» y no se pisa.
/// - La dirección y la ciudad se piden recién cuando el punto se asienta (`esperaPuntoAltaProvider`),
///   no en cada fotograma del gesto.
/// - Una respuesta vieja (de un punto que ya se dejó) se descarta.
final class AltaUbicacionNotifier extends Notifier<AltaUbicacionState> {
  AltaUbicacionNotifier(this.parametros);

  final ParametrosAlta parametros;

  Timer? _espera;
  int _secuencia = 0;

  /// Cuál es la última lectura del GPS que se pidió: una lectura que llega cuando ya se pidió otra
  /// se ignora, para que el pin y la lectura que se guarda sean siempre la misma.
  int _secuenciaGps = 0;
  String? _idAlta;
  final _log = AppLogger.instance;

  @override
  AltaUbicacionState build() {
    ref.onDispose(() => _espera?.cancel());
    final inicial = parametros.puntoInicial;
    unawaited(Future<void>(() => ref.mounted ? _arrancar() : null));
    if (inicial == null) return const AltaUbicacionState();
    return AltaUbicacionState(
      punto: inicial,
      origen: OrigenCoordenadas.manual,
      movimientosCamara: 1,
    );
  }

  Future<void> _arrancar() async {
    if (parametros.puntoInicial != null) _programarEnriquecimiento(inmediato: true);
    await _leerGps();
  }

  // ---------------------------------------------------------------- GPS

  /// Pide una lectura al GPS. Pueden quedar dos en vuelo (por ejemplo «Activar GPS» y, al volver de
  /// los ajustes, el reintento automático): **gana la última que se pidió**, aunque la anterior
  /// llegue después. Así el pin, el chip de precisión y el aviso de baja precisión salen de la misma
  /// lectura, y es la que `registrar` guarda.
  Future<void> _leerGps() async {
    if (!ref.mounted) return;
    final numero = ++_secuenciaGps;
    state = state.copyWith(gps: EstadoGps.buscando, borrarMotivo: true);
    final resultado = await ref.read(capturarPosicionGpsUseCaseProvider)(const NoParams());
    if (!ref.mounted || numero != _secuenciaGps) return;
    resultado.fold<void>(
      (falla) {
        final motivo = falla is FailureGpsNoDisponible ? falla.motivo : MotivoSinGps.sinSenal;
        state = state.copyWith(gps: EstadoGps.sinGps, motivoSinGps: motivo);
        // Sin GPS y sin punto la ciudad sale de la zona asignada o de la campaña (vista 03). Con un
        // punto ya puesto (tap largo, toque en el mapa) la propone el enriquecimiento del punto.
        if (state.punto == null && state.origenCiudad == OrigenCiudad.buscando) {
          unawaited(_proponerCiudad(null, _secuencia));
        }
      },
      (lectura) {
        // Si el colportor ya puso el pin (tap largo, toque en el mapa) la lectura no lo mueve.
        final sinPunto = state.punto == null;
        state = state.copyWith(
          gps: EstadoGps.conLectura,
          lectura: lectura,
          borrarMotivo: true,
          punto: sinPunto ? lectura.coordenadas : null,
          origen: sinPunto ? OrigenCoordenadas.gps : null,
          movimientosCamara: sinPunto ? state.movimientosCamara + 1 : null,
        );
        if (sinPunto) _programarEnriquecimiento(inmediato: true);
      },
    );
  }

  /// «Activar GPS»: pide el permiso o abre el ajuste que corresponda y vuelve a leer.
  Future<void> activarGps() async {
    final motivo = state.motivoSinGps;
    if (motivo != null) await ref.read(activadorGpsProvider).activar(motivo);
    await _leerGps();
  }

  /// Al volver a la app después de los ajustes: si seguía sin GPS, se vuelve a intentar.
  Future<void> reintentarGpsSiHaceFalta() async {
    if (state.gps == EstadoGps.sinGps) await _leerGps();
  }

  /// «Volver a mi ubicación»: el pin vuelve a la última lectura del GPS.
  void volverAMiUbicacion() {
    final lectura = state.lectura;
    if (lectura == null) {
      unawaited(_leerGps());
      return;
    }
    state = state.copyWith(
      punto: lectura.coordenadas,
      origen: OrigenCoordenadas.gps,
      precisionDecidida: false,
      movimientosCamara: state.movimientosCamara + 1,
    );
    _programarEnriquecimiento();
  }

  /// «Ajustar manualmente» y «Continuar» del aviso de baja precisión: los dos dejan registrar; el
  /// primero además invita a mover el mapa (el texto «Mové el mapa para ajustar el punto»).
  void decidirPrecision() => state = state.copyWith(precisionDecidida: true);

  // ---------------------------------------------------------------- el punto

  /// El colportor movió el mapa: el pin (fijo en el centro) queda en [punto], marcado a mano.
  void moverPunto(Coordenadas punto) {
    if (state.guardando) return;
    if (state.punto == punto && state.origen == OrigenCoordenadas.manual) return;
    state = state.copyWith(punto: punto, origen: OrigenCoordenadas.manual);
    _programarEnriquecimiento();
  }

  /// El colportor tocó el mapa donde está el lugar: el mapa se centra ahí.
  void marcarPunto(Coordenadas punto) {
    if (state.guardando) return;
    state = state.copyWith(
      punto: punto,
      origen: OrigenCoordenadas.manual,
      movimientosCamara: state.movimientosCamara + 1,
    );
    _programarEnriquecimiento();
  }

  // ---------------------------------------------------------------- el formulario

  void elegirTipo(TipoUbicacion tipo) => state = state.copyWith(tipo: tipo, borrarFalla: true);

  void editarCalle(String texto) => state = state.copyWith(
    calle: CampoDireccion(texto, texto.trim().isEmpty ? FuenteCampo.vacio : FuenteCampo.editado),
    borrarFalla: true,
  );

  void editarNumero(String texto) => state = state.copyWith(
    numero: CampoDireccion(texto, texto.trim().isEmpty ? FuenteCampo.vacio : FuenteCampo.editado),
    borrarFalla: true,
  );

  /// «Usar 1250»: toma el valor del mapa para la calle.
  void usarCalleDelMapa() {
    final calle = state.propuesta?.calle?.trim();
    if (calle == null || calle.isEmpty) return;
    state = state.copyWith(calle: CampoDireccion(calle, FuenteCampo.delMapa));
  }

  /// «Usar 1250»: toma el valor del mapa para el número.
  void usarNumeroDelMapa() {
    final numero = state.propuesta?.numero?.trim();
    if (numero == null || numero.isEmpty) return;
    state = state.copyWith(numero: CampoDireccion(numero, FuenteCampo.delMapa));
  }

  /// «Cambiar»: la ciudad la elige el colportor de la lista de su campaña. Desde ahí no se pisa al
  /// mover el punto ni con una propuesta que todavía venga en camino (se descarta al llegar).
  void elegirCiudad(CiudadCatalogo ciudad) =>
      state = state.copyWith(ciudad: ciudad, origenCiudad: OrigenCiudad.elegida, borrarFalla: true);

  /// «Reintentar» del aviso de ciudad: vuelve a pedir la propuesta.
  Future<void> reintentarCiudad() async {
    final origen = state.origenCiudad;
    if (origen != OrigenCiudad.noSePudoLeer && origen != OrigenCiudad.sinCiudades) return;
    state = state.copyWith(origenCiudad: OrigenCiudad.buscando);
    await _proponerCiudad(state.punto, _secuencia);
  }

  // ---------------------------------------------------------------- dirección y ciudad del punto

  void _programarEnriquecimiento({bool inmediato = false}) {
    _espera?.cancel();
    final secuencia = ++_secuencia;
    if (inmediato) {
      unawaited(_enriquecer(secuencia));
      return;
    }
    _espera = Timer(ref.read(esperaPuntoAltaProvider), () => unawaited(_enriquecer(secuencia)));
  }

  /// Pide la dirección (red) y la ciudad (dato local) del punto **a la vez y sin que una espere a la
  /// otra**: la ciudad ya se conoce sin red, y «Registrar» no tiene que quedar esperando a que
  /// Nominatim conteste o venza (hasta ~15 s con mala señal). Cada respuesta se descarta por su
  /// cuenta si el punto ya cambió.
  Future<void> _enriquecer(int secuencia) async {
    final punto = state.punto;
    if (punto == null || !ref.mounted) return;
    final direccion = ref.read(geocodificadorInversoProvider).direccionDe(punto);
    if (state.origenCiudad != OrigenCiudad.elegida) unawaited(_proponerCiudad(punto, secuencia));
    final dir = await direccion;
    if (!ref.mounted || secuencia != _secuencia) return;
    _aplicarDireccion(dir);
  }

  Future<void> _proponerCiudad(Coordenadas? punto, int secuencia) async =>
      _aplicarPropuesta(await _pedirPropuesta(punto), secuencia);

  /// Le pide la ciudad al puerto. Si el puerto lanza en vez de devolver una falla, se traduce a una:
  /// el campo no se queda en «Buscando la ciudad…» para siempre.
  Future<Either<Failure, PropuestaCiudad>> _pedirPropuesta(Coordenadas? punto) async {
    try {
      return await ref
          .read(ciudadesParaAltaProvider)
          .proponer(colportorId: parametros.colportorId, punto: punto);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.map,
        'CIUDAD_PROPONER_FAIL',
        'no se pudo proponer la ciudad',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  /// Aplica la propuesta si sigue valiendo: si el colportor ya eligió una ciudad (aunque haya sido
  /// mientras la propuesta venía en camino) o el punto ya cambió, se descarta.
  void _aplicarPropuesta(Either<Failure, PropuestaCiudad> resultado, int secuencia) {
    if (!ref.mounted || secuencia != _secuencia || state.origenCiudad == OrigenCiudad.elegida) {
      return;
    }
    final propuesta = resultado.fold<PropuestaCiudad?>((falla) {
      _log.warn(LogModulo.map, 'CIUDAD_PROPONER_FAIL', 'no se pudo leer la ciudad', {
        'codigo': falla.codigo,
      });
      return null;
    }, (p) => p);
    switch (propuesta) {
      case null:
        // Si ya había una ciudad propuesta (el punto se movió), se conserva: nada se pierde.
        if (state.ciudad == null) state = state.copyWith(origenCiudad: OrigenCiudad.noSePudoLeer);
      case CiudadPropuesta(:final ciudad, :final origen):
        state = state.copyWith(
          ciudad: ciudad,
          origenCiudad: switch (origen) {
            OrigenPropuesta.detectada => OrigenCiudad.detectada,
            OrigenPropuesta.deZona => OrigenCiudad.deZona,
            OrigenPropuesta.deCampania => OrigenCiudad.deCampania,
          },
        );
      case CampaniaSinCiudades():
        state = state.copyWith(borrarCiudad: true, origenCiudad: OrigenCiudad.sinCiudades);
      case FaltaElPunto():
        if (state.ciudad == null) state = state.copyWith(origenCiudad: OrigenCiudad.porElegir);
    }
  }

  void _aplicarDireccion(DireccionDelPunto? dir) {
    final nuevaCalle = dir?.calle?.trim() ?? '';
    final nuevoNumero = dir?.numero?.trim() ?? '';
    final calleAnterior = state.calle;
    final numeroAnterior = state.numero;
    CampoDireccion aplicar(CampoDireccion actual, String delMapa) {
      if (actual.fuente == FuenteCampo.editado) return actual;
      return CampoDireccion(delMapa, delMapa.isEmpty ? FuenteCampo.vacio : FuenteCampo.delMapa);
    }

    final calle = aplicar(calleAnterior, nuevaCalle);
    final cambioLaCalle =
        calleAnterior.fuente == FuenteCampo.delMapa &&
        calle.fuente == FuenteCampo.delMapa &&
        calle.texto != calleAnterior.texto;
    state = state.copyWith(
      calle: calle,
      numero: aplicar(numeroAnterior, nuevoNumero),
      propuesta: dir,
      borrarPropuesta: dir == null,
      avisosCalle: cambioLaCalle ? state.avisosCalle + 1 : null,
    );
  }

  // ---------------------------------------------------------------- registrar

  /// «Registrar» (o «Crear igual» con [justificacion]). Un solo registro a la vez: un segundo toque
  /// mientras el primero sigue en curso no hace nada; y como el `id` del alta es el mismo en cada
  /// intento, aun un reintento no puede crear dos.
  Future<ResultadoRegistroAlta> registrar({String? justificacion}) async {
    final punto = state.punto;
    final tipo = state.tipo;
    final ciudad = state.ciudad;
    if (state.guardando || punto == null || tipo == null || ciudad == null) {
      return const AltaIgnorada();
    }
    if (justificacion == null && state.necesitaDecisionPrecision) return const AltaIgnorada();

    state = state.copyWith(guardando: true, borrarFalla: true);
    final lectura = state.lectura;
    final capturado = state.origen == OrigenCoordenadas.gps && lectura != null
        ? PuntoCapturado.gps(lectura)
        : PuntoCapturado.manual(punto);
    try {
      final casoDeUso = ref.read(registrarUbicacionUseCaseProvider);
      _idAlta ??= casoDeUso.nuevoId();
      final resultado = await casoDeUso(
        RegistrarUbicacionParams(
          id: _idAlta!,
          colportorId: parametros.colportorId,
          tipo: tipo,
          punto: capturado,
          ciudadId: ciudad.id,
          calle: state.calle.texto,
          numero: state.numero.texto,
          confirmaBajaPrecision: state.precisionDecidida,
          justificacionDuplicado: justificacion,
        ),
      );
      if (!ref.mounted) return const AltaIgnorada();
      return resultado.fold<ResultadoRegistroAlta>(
        (falla) {
          state = state.copyWith(guardando: false, falla: falla);
          return AltaFallida(falla);
        },
        (r) {
          switch (r) {
            case AltaRegistrada(:final ubicacion):
              // La pantalla se cierra con el resultado: «guardando» queda en alto hasta entonces
              // para que no se pueda tocar otra vez.
              return AltaCreada(ubicacion);
            case AltaConBajaPrecision():
              state = state.copyWith(guardando: false, precisionDecidida: false);
              return const AltaIgnorada();
            case AltaConDuplicados(:final candidatas):
              state = state.copyWith(guardando: false);
              return AltaConCandidatas(candidatas);
          }
        },
      );
    } on Object catch (e, st) {
      _log.error(LogModulo.map, 'ALTA_UBICACION_FAIL', 'no se pudo registrar', const {}, e, st);
      if (!ref.mounted) return const AltaIgnorada();
      final falla = FailureInesperado(causa: e);
      state = state.copyWith(guardando: false, falla: falla);
      return AltaFallida(falla);
    }
  }
}

/// El estado del alta de [parametros]; se descarta al cerrar la pantalla.
final altaUbicacionProvider = NotifierProvider.autoDispose
    .family<AltaUbicacionNotifier, AltaUbicacionState, ParametrosAlta>(AltaUbicacionNotifier.new);
