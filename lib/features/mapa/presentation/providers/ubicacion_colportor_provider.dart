import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/modo_seguimiento.dart';
import '../../domain/value_objects/punto_capturado.dart';
import 'alta_ubicacion_providers.dart';
import 'lista_ubicaciones_state.dart' show EstadoGpsLista;

/// Lo que se sabe del GPS del colportor: la última lectura, el permiso y el servicio, y cómo lo sigue
/// el mapa.
final class UbicacionColportorState extends Equatable {
  const UbicacionColportorState({
    this.gps = EstadoGpsLista.sinPedir,
    this.lectura,
    this.motivoSinGps,
    this.modo = ModoSeguimiento.libre,
    this.enVivo = false,
    this.llegoDelStream = false,
    this.cortes = 0,
  });

  /// [EstadoGpsLista.sinPedir] hasta que se entra a la pestaña Mapa por primera vez.
  final EstadoGpsLista gps;

  /// La última lectura buena. Una lectura que falla después no la tira: la posición recordada
  /// sirve de centro inicial del mapa y de punto para ordenar por cercanía.
  final LecturaGps? lectura;

  /// Por qué no hay GPS; solo con [EstadoGpsLista.sinGps].
  final MotivoSinGps? motivoSinGps;

  /// Cómo sigue el mapa a la colportora (#670). Se recuerda mientras la app está abierta.
  final ModoSeguimiento modo;

  /// Hay un stream del GPS abierto: [lectura] es la posición de ahora, no la de la última vez que
  /// se leyó. Pasa solo con un [modo] que sigue y el mapa a la vista.
  final bool enVivo;

  /// El stream abierto ya trajo una lectura: hasta ese primer evento, [lectura] sigue siendo la de
  /// antes de abrirlo (puede ser vieja).
  final bool llegoDelStream;

  /// Cuántas veces se cortó el seguimiento solo (el GPS se apagó o dejó de responder): quien
  /// escucha avisa a la colportora una vez por cada corte.
  final int cortes;

  /// La posición con la que se ordena y se mide, si hay.
  Coordenadas? get posicion => lectura?.coordenadas;

  /// La posición de ahora, si el seguimiento la mantiene viva y ya trajo una lectura; si no, `null`:
  /// la última lectura puede ser vieja.
  LecturaGps? get lecturaViva => enVivo && llegoDelStream ? lectura : null;

  UbicacionColportorState copyWith({
    EstadoGpsLista? gps,
    LecturaGps? lectura,
    MotivoSinGps? motivoSinGps,
    bool borrarMotivo = false,
    ModoSeguimiento? modo,
    bool? enVivo,
    bool? llegoDelStream,
    int? cortes,
  }) => UbicacionColportorState(
    gps: gps ?? this.gps,
    lectura: lectura ?? this.lectura,
    motivoSinGps: borrarMotivo ? null : (motivoSinGps ?? this.motivoSinGps),
    modo: modo ?? this.modo,
    enVivo: enVivo ?? this.enVivo,
    llegoDelStream: llegoDelStream ?? this.llegoDelStream,
    cortes: cortes ?? this.cortes,
  );

  @override
  List<Object?> get props => [gps, lectura, motivoSinGps, modo, enVivo, llegoDelStream, cortes];
}

/// El único GPS del colportor (decisión de Cristian, 04/11, #651).
///
/// Es el **único** que llama a `ProveedorGps.posicionActual()` (por `CapturarPosicionGpsUseCase`) y
/// el único que dispara el diálogo del permiso: lo hace al entrar a la pestaña Mapa
/// ([alAbrirPestana]). El Mapa, la Lista, el alta, Modificar y Precios **leen** de acá y no vuelven
/// a pedir el permiso; «Mi ubicación» y «Activar GPS» son acciones de este mismo provider.
///
/// Vive mientras la app (keepAlive): la última lectura queda en memoria entre pestañas, sin tabla
/// nueva ni disco. Sin permiso o con la ubicación apagada **no** se vuelve a pedir solo: se
/// reintenta al volver de los ajustes del sistema ([reintentarGpsSiHaceFalta]).
///
/// **Seguimiento (#670, decisión de Cristian del 05/11).** Con un [ModoSeguimiento] que sigue
/// ([cambiarModo]), y mientras el mapa está a la vista ([mapaALaVista]: pestaña Mapa activa y app en
/// primer plano), mantiene la posición viva con un stream en vez de una lectura suelta. Fuera de la
/// pestaña, o con la app en segundo plano, el stream se cierra (batería); el modo se recuerda y el
/// stream vuelve con el mapa. No pide el permiso: si el GPS se apaga o el permiso se retira, corta el
/// seguimiento y lo avisa en [UbicacionColportorState.cortes].
class UbicacionColportorNotifier extends Notifier<UbicacionColportorState> {
  /// Cuál es la última lectura que se pidió: una que llega cuando ya se pidió otra se ignora, así
  /// la posición es siempre la última.
  int _secuencia = 0;

  /// El colportor tocó «Activar GPS» y se lo mandó al permiso o a los ajustes del sistema: solo
  /// entonces tiene sentido volver a leer cuando regrese a la app. Cualquier otro regreso (volver
  /// de WhatsApp) no puede volver a mostrarle el diálogo del permiso.
  bool _enAjustes = false;

  /// «Activar GPS» ya está en curso: un segundo toque no abre otro diálogo del sistema encima.
  bool _activando = false;

  /// El stream del GPS en vivo; `null` si no hay seguimiento abierto.
  StreamSubscription<Either<Failure, LecturaGps>>? _suscripcion;

  /// El mapa está a la vista: la pestaña Mapa activa y la app en primer plano.
  bool _mapaALaVista = false;

  final _log = AppLogger.instance;

  @override
  UbicacionColportorState build() {
    ref.onDispose(() {
      final suscripcion = _suscripcion;
      _suscripcion = null;
      if (suscripcion != null) unawaited(suscripcion.cancel());
    });
    return const UbicacionColportorState();
  }

  /// Se entró a la pestaña Mapa: se pide el GPS (y con él el permiso) la primera vez y se refresca
  /// las siguientes. Si la última vez falló por el permiso o por la ubicación apagada, **no** se
  /// vuelve a pedir sola (cada apertura mostraría el diálogo): se reintenta al volver de los ajustes.
  Future<void> alAbrirPestana() async {
    final sinPermisoOApagado =
        state.gps == EstadoGpsLista.sinGps && state.motivoSinGps != MotivoSinGps.sinSenal;
    if (sinPermisoOApagado || state.gps == EstadoGpsLista.buscando) return;
    // Con el seguimiento abierto la posición ya es la de ahora: no hace falta otra lectura.
    if (state.enVivo) return;
    await _leer();
  }

  /// Al volver a la app después de los ajustes (o del diálogo del permiso): si seguía sin GPS, se
  /// vuelve a intentar. Solo si el colportor había tocado «Activar GPS»; el regreso de cualquier
  /// otra app no hace nada.
  Future<void> reintentarGpsSiHaceFalta() async {
    // El diálogo del permiso también pausa y reanuda la app: si «Activar GPS» sigue en curso, ese
    // regreso no es el de los ajustes y leer ahora pediría el permiso otra vez, encimado (#679).
    if (_activando || !_enAjustes || state.gps != EstadoGpsLista.sinGps) return;
    _enAjustes = false;
    await _leer();
  }

  /// «Mi ubicación» y «Volver a mi ubicación»: vuelve a leer (el colportor se movió desde la última
  /// lectura). Una lectura que falla no tira la última buena. Devuelve lo que contestó el GPS.
  ///
  /// Es un toque explícito de Ana: igual que «Activar GPS», puede abrir el permiso (decisión del
  /// 05/11, #660). Nunca se llama sola al abrir una vista.
  Future<Either<Failure, LecturaGps>> refrescar() => _leer();

  /// «Activar GPS»: pide el permiso o abre el ajuste que corresponda y vuelve a leer. Sin un motivo
  /// conocido (todavía no se pidió) solo lee.
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
            'UBICACION_COLPORTOR_ACTIVAR_FAIL',
            'no se pudo activar el GPS',
            const {},
            error,
            pila,
          );
        }
      }
      await _leer();
    } finally {
      _activando = false;
    }
  }

  // ---------------------------------------------------------------- seguimiento (#670)

  /// Pasa el botón de ubicación al modo siguiente: libre, seguir, seguir y girar y de nuevo libre.
  void siguienteModo() => cambiarModo(state.modo.siguiente);

  /// Cambia el modo de seguimiento. Para seguir hace falta una posición: sin ninguna lectura no hay
  /// a quién seguir y el modo no cambia (el botón está apagado). Mover el mapa con el dedo llama acá
  /// con [ModoSeguimiento.libre].
  void cambiarModo(ModoSeguimiento nuevo) {
    if (!ref.mounted || nuevo == state.modo) return;
    if (nuevo.sigue && state.lectura == null) return;
    state = state.copyWith(modo: nuevo);
    _sincronizarSeguimiento();
  }

  /// La pestaña Mapa avisa si está a la vista (activa y con la app en primer plano). Fuera de ahí el
  /// stream se cierra y el modo queda como estaba.
  void mapaALaVista(bool aLaVista) {
    if (!ref.mounted || aLaVista == _mapaALaVista) return;
    _mapaALaVista = aLaVista;
    _sincronizarSeguimiento();
  }

  /// Abre o cierra el stream según lo que hace falta: modo que sigue, mapa a la vista y una posición
  /// de la que partir.
  void _sincronizarSeguimiento() {
    final hace = state.modo.sigue && _mapaALaVista && state.lectura != null;
    if (hace && _suscripcion == null) {
      _suscripcion = ref
          .read(seguidorGpsProvider)
          .seguir()
          .listen(
            _alLlegarLectura,
            onError: (Object _, StackTrace _) => _alTerminarElStream(),
            onDone: _alTerminarElStream,
          );
      state = state.copyWith(enVivo: true, llegoDelStream: false);
    } else if (!hace && _suscripcion != null) {
      _cerrarSeguimiento();
    }
  }

  void _cerrarSeguimiento() {
    final suscripcion = _suscripcion;
    _suscripcion = null;
    if (suscripcion != null) unawaited(suscripcion.cancel());
    if (state.enVivo) state = state.copyWith(enVivo: false, llegoDelStream: false);
  }

  void _alLlegarLectura(Either<Failure, LecturaGps> resultado) {
    if (!ref.mounted || _suscripcion == null) return;
    resultado.fold<void>(_cortarSeguimiento, (lectura) {
      // Esta lectura es más nueva que cualquier lectura suelta que siga en vuelo.
      _secuencia++;
      state = state.copyWith(
        gps: EstadoGpsLista.conLectura,
        lectura: lectura,
        llegoDelStream: true,
        borrarMotivo: true,
      );
    });
  }

  /// El sistema cerró el stream sin avisar: se trata como un corte (nadie queda siguiendo a nada).
  void _alTerminarElStream() {
    if (!ref.mounted || _suscripcion == null) return;
    _cortarSeguimiento(const FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal));
  }

  /// El GPS se apagó, el permiso se retiró o el plugin falló: el mapa vuelve a «libre» y se avisa
  /// una vez. Con el permiso o la ubicación apagados el GPS queda como «sin GPS» (con «Activar GPS»
  /// en todas las vistas); una falla sin motivo conocido deja la última posición como está.
  void _cortarSeguimiento(Failure falla) {
    final motivo = falla is FailureGpsNoDisponible ? falla.motivo : MotivoSinGps.sinSenal;
    _log.warn(LogModulo.map, 'UBICACION_COLPORTOR_SEGUIMIENTO_CORTADO', 'se cortó el seguimiento', {
      'motivo': motivo.name,
    });
    _cerrarSeguimiento();
    final sinPermisoOApagado = motivo != MotivoSinGps.sinSenal;
    state = state.copyWith(
      modo: ModoSeguimiento.libre,
      cortes: state.cortes + 1,
      gps: sinPermisoOApagado ? EstadoGpsLista.sinGps : null,
      motivoSinGps: sinPermisoOApagado ? motivo : null,
    );
  }

  // ---------------------------------------------------------------- lectura suelta

  Future<Either<Failure, LecturaGps>> _leer() async {
    const sinSenal = Left<Failure, LecturaGps>(
      FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal),
    );
    if (!ref.mounted) return sinSenal;
    final numero = ++_secuencia;
    if (state.gps != EstadoGpsLista.conLectura) {
      state = state.copyWith(gps: EstadoGpsLista.buscando, borrarMotivo: true);
    }
    final resultado = await ref.read(capturarPosicionGpsUseCaseProvider)(const NoParams());
    if (!ref.mounted || numero != _secuencia) return resultado;
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
      (lectura) => state = state.copyWith(
        gps: EstadoGpsLista.conLectura,
        lectura: lectura,
        borrarMotivo: true,
      ),
    );
    return resultado;
  }
}

/// El GPS del colportor, uno solo para toda la app. Ver [UbicacionColportorNotifier].
final ubicacionColportorProvider =
    NotifierProvider<UbicacionColportorNotifier, UbicacionColportorState>(
      UbicacionColportorNotifier.new,
    );
