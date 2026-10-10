import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/usecases/duplicados_ubicacion_use_cases.dart';
import 'duplicados_providers.dart';

/// Una unión que el colportor pidió con «Conservar A y unir» y todavía no se hizo: espera sus 8 s de
/// «Deshacer». **No cambia nada** en la base local ni en la cola de sync hasta que se cumplen.
final class UnionPendiente extends Equatable {
  const UnionPendiente({
    required this.clavePar,
    required this.conservarId,
    required this.duplicadaId,
    required this.direccion,
  });

  /// `ParDuplicado.clave`: identifica el par sin importar cuál se conserva.
  final String clavePar;

  /// La que queda («A») y la que pasa a ser baja con sus espacios en la otra («B»).
  final String conservarId;
  final String duplicadaId;

  /// «Av. Italia 1234»: lo que dice el aviso («Las dos Av. Italia 1234 quedaron unidas en una.»).
  final String direccion;

  @override
  List<Object?> get props => [clavePar, conservarId, duplicadaId, direccion];
}

/// Una unión que se intentó hacer y no se pudo, con el motivo.
final class FallaUnion extends Equatable {
  const FallaUnion({required this.union, required this.falla});

  final UnionPendiente union;
  final Failure falla;

  /// Reintentar sirve si la falla puede cambiar sola o con otro intento. Con la que se iba a
  /// conservar ya dada de baja, no: el par hay que revisarlo de nuevo.
  bool get sePuedeReintentar => falla is! FailureConservadaDeBaja;

  @override
  List<Object?> get props => [union, falla];
}

/// Lo que la pantalla de «Posibles duplicados» tiene que saber de las uniones en marcha.
final class UnionesPendientesState extends Equatable {
  const UnionesPendientesState({this.pendiente, this.ocultas = const {}, this.falla});

  /// La unión que espera sus 8 s: el aviso «Las dos … quedaron unidas en una.» con «Deshacer».
  final UnionPendiente? pendiente;

  /// Los pares (`clavePar`) que la lista no muestra: el que espera sus 8 s, los que se están uniendo
  /// y los que ya se unieron (la base los saca sola; mientras llega esa lectura no reaparecen).
  final Set<String> ocultas;

  /// La última unión que falló: la pantalla dice por qué y, si sirve, ofrece «Reintentar».
  final FallaUnion? falla;

  @override
  List<Object?> get props => [pendiente, ocultas, falla];
}

/// HU-UBI-006: las uniones de «Posibles duplicados» con su espera de 8 s.
///
/// - **«Conservar A y unir»** ([unir]) deja la unión pendiente 8 s. En ese tiempo no se escribe nada.
/// - **«Deshacer»** ([deshacer]) la cancela: el par sigue en la lista.
/// - **Un segundo toque sobre el mismo par** no hace nada y no reinicia el tiempo.
/// - **Unir otro par** hace definitiva la anterior en ese momento, y los 8 s corren para el nuevo.
/// - **Pasados los 8 s**, o al salir de la pantalla (se descarta el notificador), la unión es
///   definitiva: una sola transacción local (`UnirDuplicadosUseCase`).
/// - Si la app se cierra de golpe en los 8 s, no se hizo nada (todo está en memoria).
/// - Las uniones definitivas corren de a una y en el orden en que se pidieron.
/// - Si una falla, no cambia nada, el par vuelve a la lista y [UnionesPendientesState.falla] dice
///   por qué; [reintentar] la vuelve a correr ya, sin otra espera.
final class UnionesPendientesNotifier extends Notifier<UnionesPendientesState> {
  late UnirDuplicadosUseCase _unir;
  late Duration _plazo;
  Timer? _reloj;

  /// Espejo de [UnionesPendientesState.pendiente] para el cierre: no se lee `state` al descartarse.
  UnionPendiente? _pendiente;

  /// Cada unión definitiva espera a la anterior: dos a la vez sobre la misma base no se pisan.
  Future<void> _cola = Future<void>.value();

  @override
  UnionesPendientesState build() {
    _unir = ref.watch(unirDuplicadosUseCaseProvider);
    _plazo = ref.watch(plazoDeshacerUnionProvider);
    ref.onDispose(_alDescartar);
    return const UnionesPendientesState();
  }

  /// «Conservar A y unir»: arranca los 8 s de [union].
  void unir(UnionPendiente union) {
    final actual = _pendiente;
    if (actual?.clavePar == union.clavePar) return;
    if (state.ocultas.contains(union.clavePar)) return;
    if (actual != null) {
      _reloj?.cancel();
      _confirmar(actual);
    }
    _pendiente = union;
    state = UnionesPendientesState(pendiente: union, ocultas: {...state.ocultas, union.clavePar});
    _reloj = Timer(_plazo, _alCumplirse);
  }

  /// «Deshacer»: cancela la unión que espera. Si ya se hizo, no hay nada que deshacer (el aviso ya
  /// no está).
  void deshacer() {
    final union = _pendiente;
    if (union == null) return;
    _reloj?.cancel();
    _reloj = null;
    _pendiente = null;
    state = UnionesPendientesState(
      ocultas: {...state.ocultas}..remove(union.clavePar),
      falla: state.falla,
    );
  }

  /// «Reintentar» tras una falla: la corre ya.
  void reintentar() {
    final falla = state.falla;
    if (falla == null || !falla.sePuedeReintentar) return;
    state = UnionesPendientesState(
      pendiente: state.pendiente,
      ocultas: {...state.ocultas, falla.union.clavePar},
    );
    _confirmar(falla.union);
  }

  /// Cierra el aviso de una falla sin reintentar.
  void descartarFalla() {
    if (state.falla == null) return;
    state = UnionesPendientesState(pendiente: state.pendiente, ocultas: state.ocultas);
  }

  void _alCumplirse() {
    final union = _pendiente;
    if (union == null) return;
    _reloj = null;
    _pendiente = null;
    state = UnionesPendientesState(ocultas: state.ocultas, falla: state.falla);
    _confirmar(union);
  }

  /// Salir de la pantalla con una unión esperando la hace definitiva.
  void _alDescartar() {
    _reloj?.cancel();
    _reloj = null;
    final union = _pendiente;
    _pendiente = null;
    if (union != null) _confirmar(union);
  }

  void _confirmar(UnionPendiente union) {
    _cola = _cola.then((_) => _ejecutar(union));
  }

  /// No lanza: lo que salga mal se traduce a [UnionesPendientesState.falla].
  Future<void> _ejecutar(UnionPendiente union) async {
    Failure? falla;
    try {
      final resultado = await _unir(
        UnirDuplicadosParams(conservarId: union.conservarId, duplicadaId: union.duplicadaId),
      );
      falla = resultado.fold((f) => f, (_) => null);
    } on Object catch (e) {
      falla = FailureInesperado(causa: e);
    }
    // La pantalla ya se fue: no hay a quién avisarle (el repositorio dejó el log).
    if (falla == null || !ref.mounted) return;
    state = UnionesPendientesState(
      pendiente: state.pendiente,
      ocultas: {...state.ocultas}..remove(union.clavePar),
      falla: FallaUnion(union: union, falla: falla),
    );
  }
}

/// Las uniones en marcha de «Posibles duplicados». Se descarta con la pantalla, y al descartarse
/// hace definitiva la que esperaba sus 8 s.
final unionesPendientesProvider =
    NotifierProvider.autoDispose<UnionesPendientesNotifier, UnionesPendientesState>(
      UnionesPendientesNotifier.new,
    );
