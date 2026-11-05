import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/usecases/use_case.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../../domain/value_objects/punto_capturado.dart';
import 'alta_ubicacion_providers.dart';
import 'lista_ubicaciones_state.dart' show EstadoGpsLista;

/// Lo que se sabe del GPS del colportor: la última lectura, el permiso y el servicio.
final class UbicacionColportorState extends Equatable {
  const UbicacionColportorState({
    this.gps = EstadoGpsLista.sinPedir,
    this.lectura,
    this.motivoSinGps,
  });

  /// [EstadoGpsLista.sinPedir] hasta que se entra a la pestaña Mapa por primera vez.
  final EstadoGpsLista gps;

  /// La última lectura buena. Una lectura que falla después no la tira: la posición recordada
  /// sirve de centro inicial del mapa y de punto para ordenar por cercanía.
  final LecturaGps? lectura;

  /// Por qué no hay GPS; solo con [EstadoGpsLista.sinGps].
  final MotivoSinGps? motivoSinGps;

  /// La posición con la que se ordena y se mide, si hay.
  Coordenadas? get posicion => lectura?.coordenadas;

  UbicacionColportorState copyWith({
    EstadoGpsLista? gps,
    LecturaGps? lectura,
    MotivoSinGps? motivoSinGps,
    bool borrarMotivo = false,
  }) => UbicacionColportorState(
    gps: gps ?? this.gps,
    lectura: lectura ?? this.lectura,
    motivoSinGps: borrarMotivo ? null : (motivoSinGps ?? this.motivoSinGps),
  );

  @override
  List<Object?> get props => [gps, lectura, motivoSinGps];
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

  final _log = AppLogger.instance;

  @override
  UbicacionColportorState build() => const UbicacionColportorState();

  /// Se entró a la pestaña Mapa: se pide el GPS (y con él el permiso) la primera vez y se refresca
  /// las siguientes. Si la última vez falló por el permiso o por la ubicación apagada, **no** se
  /// vuelve a pedir sola (cada apertura mostraría el diálogo): se reintenta al volver de los ajustes.
  Future<void> alAbrirPestana() async {
    final sinPermisoOApagado =
        state.gps == EstadoGpsLista.sinGps && state.motivoSinGps != MotivoSinGps.sinSenal;
    if (sinPermisoOApagado || state.gps == EstadoGpsLista.buscando) return;
    await _leer();
  }

  /// Al volver a la app después de los ajustes (o del diálogo del permiso): si seguía sin GPS, se
  /// vuelve a intentar. Solo si el colportor había tocado «Activar GPS»; el regreso de cualquier
  /// otra app no hace nada.
  Future<void> reintentarGpsSiHaceFalta() async {
    if (!_enAjustes || state.gps != EstadoGpsLista.sinGps) return;
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
