import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/duplicado_ubicacion.dart';
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

  /// «Av. Italia 1234»: lo que dice el aviso («Las dos Av. Italia 1234 quedaron unidas en una.»). La
  /// de la ubicación que se conserva o, si no tiene calle ni número, la de la otra; vacía si ninguna
  /// de las dos tiene (los avisos tienen su frase para ese caso).
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
  const UnionesPendientesState({
    this.pendiente,
    this.ocultas = const {},
    this.duplicadasEnCurso = const {},
    this.fallas = const [],
  });

  /// La unión que espera sus 8 s: el aviso «Las dos … quedaron unidas en una.» con «Deshacer».
  final UnionPendiente? pendiente;

  /// Los pares (`clavePar`) que la lista no muestra: el que espera sus 8 s, los que se están uniendo
  /// y los que ya se unieron (la base los saca sola; mientras llega esa lectura no reaparecen).
  final Set<String> ocultas;

  /// Las ubicaciones («B») que van a quedar de baja por una unión que espera, se está haciendo o ya
  /// se hizo mientras la pantalla seguía abierta. Cualquier otro par que las contenga tampoco se
  /// muestra: unirlo correría sobre una «B» que ya no existe, no escribiría nada y el aviso diría
  /// «quedaron unidas» sin que pasara (revisión r1 de #338, M3).
  final Set<String> duplicadasEnCurso;

  /// Las uniones que fallaron, de la más vieja a la más nueva, una por par: la pantalla dice por qué
  /// y, si sirve, ofrece «Reintentar». Ninguna pisa a otra: cada una se queda hasta que se reintenta,
  /// se descarta o una unión nueva toca la misma ubicación.
  final List<FallaUnion> fallas;

  /// La última que falló, si hay alguna.
  FallaUnion? get falla => fallas.lastOrNull;

  /// Si la lista de pares no tiene que mostrar [par]: es uno de [ocultas] o contiene a una de
  /// [duplicadasEnCurso].
  bool oculta(ParDuplicado par) =>
      ocultas.contains(par.clave) ||
      duplicadasEnCurso.contains(par.a.id) ||
      duplicadasEnCurso.contains(par.b.id);

  @override
  List<Object?> get props => [pendiente, ocultas, duplicadasEnCurso, fallas];
}

/// Las uniones que fallaron cuando la pantalla de «Posibles duplicados» ya no estaba (la colportora
/// salió dentro de los 8 s, o con otras uniones en la cola, y la escritura falló después: disco
/// lleno, por ejemplo). Ella ya vio «quedaron unidas en una»: la Lista le dice que no pasó
/// (QA r1 de #338, F3). Vive mientras corre la app, a diferencia de [unionesPendientesProvider].
///
/// Solo guarda la última falla de cada par. Se vacía cuando la colportora toca «Revisar» en la Lista:
/// ahí ya ve los pares y no hace falta repetirle el aviso.
final class UnionesFallidasFueraDePantallaNotifier extends Notifier<List<FallaUnion>> {
  @override
  List<FallaUnion> build() => const [];

  void registrar(FallaUnion falla) {
    if (!ref.mounted) return;
    state = [
      for (final f in state)
        if (f.union.clavePar != falla.union.clavePar) f,
      falla,
    ];
  }

  void olvidar() {
    if (!ref.mounted || state.isEmpty) return;
    state = const [];
  }
}

final unionesFallidasFueraDePantallaProvider =
    NotifierProvider<UnionesFallidasFueraDePantallaNotifier, List<FallaUnion>>(
      UnionesFallidasFueraDePantallaNotifier.new,
    );

/// El aviso de la Lista «No pudimos unir `dirección` · Revisar» (o «No pudimos unir 2 pares · Revisar»
/// con más de una): las uniones que fallaron fuera de la pantalla y cuyo par **sigue** para revisar,
/// de la más vieja a la más nueva. Si el par ya no está (se unió por otro lado, se corrigió una
/// dirección, una pasó a baja), no hay nada que revisar y esa falla no se cuenta.
/// Vacío mientras se leen los pares: un aviso que no se puede confirmar no se muestra.
final avisoUnionFallidaProvider = Provider.autoDispose.family<List<FallaUnion>, String>((
  ref,
  colportorId,
) {
  final fallidas = ref.watch(unionesFallidasFueraDePantallaProvider);
  if (fallidas.isEmpty) return const [];
  final pares = ref.watch(paresParaRevisarProvider(colportorId)).value;
  if (pares == null) return const [];
  final claves = {for (final p in pares) p.par.clave};
  return [
    for (final f in fallidas)
      if (claves.contains(f.union.clavePar)) f,
  ];
});

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
/// - Si una falla, no cambia nada, el par vuelve a la lista y [UnionesPendientesState.fallas] dice
///   por qué; [reintentar] las vuelve a correr ya, sin otra espera. Una falla no pisa a otra: se
///   queda hasta que se reintenta, se descarta o se une otro par que toca la misma ubicación; unir
///   otro par distinto no la borra.
/// - Mientras una unión espera o corre, los demás pares que contienen a la duplicada tampoco se
///   muestran ([UnionesPendientesState.duplicadasEnCurso]).
/// - Si la unión falla cuando la pantalla ya no está, la falla va a
///   [unionesFallidasFueraDePantallaProvider] y la Lista la avisa.
final class UnionesPendientesNotifier extends Notifier<UnionesPendientesState> {
  late UnirDuplicadosUseCase _unir;
  late Duration _plazo;
  late UnionesFallidasFueraDePantallaNotifier _fueraDePantalla;
  Timer? _reloj;

  /// Espejo de [UnionesPendientesState.pendiente] para el cierre: no se lee `state` al descartarse.
  UnionPendiente? _pendiente;

  /// Cada unión definitiva espera a la anterior: dos a la vez sobre la misma base no se pisan.
  Future<void> _cola = Future<void>.value();

  @override
  UnionesPendientesState build() {
    _unir = ref.watch(unirDuplicadosUseCaseProvider);
    _plazo = ref.watch(plazoDeshacerUnionProvider);
    // Se toma ahora: pasada la pantalla ya no se puede leer con `ref`, y la falla de una unión que
    // termina después de salir tiene que llegar igual a la Lista.
    _fueraDePantalla = ref.read(unionesFallidasFueraDePantallaProvider.notifier);
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
    state = UnionesPendientesState(
      pendiente: union,
      ocultas: {...state.ocultas, union.clavePar},
      duplicadasEnCurso: {...state.duplicadasEnCurso, union.duplicadaId},
      fallas: _fallasQueSiguenCon(union),
    );
    _reloj = Timer(_plazo, _alCumplirse);
  }

  /// Las fallas que se quedan cuando se pide [nueva]: las que ya estaban, menos las que [nueva]
  /// reemplaza. Reemplaza a la del mismo par (otro intento) y a las que tocan la misma ubicación:
  /// reintentar la vieja después correría sobre una ubicación que la nueva ya movió o va a mover (que
  /// la nueva dé de baja a la que la vieja iba a conservar, o conserve a la que iba a quedar de baja,
  /// o duplique la misma).
  List<FallaUnion> _fallasQueSiguenCon(UnionPendiente nueva) => [
    for (final falla in state.fallas)
      if (!_seCruzaCon(falla.union, nueva)) falla,
  ];

  static bool _seCruzaCon(UnionPendiente vieja, UnionPendiente nueva) =>
      vieja.clavePar == nueva.clavePar ||
      vieja.duplicadaId == nueva.duplicadaId ||
      vieja.duplicadaId == nueva.conservarId ||
      vieja.conservarId == nueva.duplicadaId;

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
      duplicadasEnCurso: {...state.duplicadasEnCurso}..remove(union.duplicadaId),
      fallas: state.fallas,
    );
  }

  /// «Reintentar» tras una falla: corre ya todas las que se pueden reintentar, una detrás de otra y
  /// en el orden en que fallaron. Las que vuelven a fallar quedan de nuevo en
  /// [UnionesPendientesState.fallas]; las que no se pueden reintentar (la que se iba a conservar ya
  /// es baja) se quedan hasta que se descartan.
  void reintentar() {
    final aReintentar = [
      for (final falla in state.fallas)
        if (falla.sePuedeReintentar) falla.union,
    ];
    if (aReintentar.isEmpty) return;
    state = UnionesPendientesState(
      pendiente: state.pendiente,
      ocultas: {...state.ocultas, for (final u in aReintentar) u.clavePar},
      duplicadasEnCurso: {...state.duplicadasEnCurso, for (final u in aReintentar) u.duplicadaId},
      fallas: [
        for (final falla in state.fallas)
          if (!falla.sePuedeReintentar) falla,
      ],
    );
    aReintentar.forEach(_confirmar);
  }

  /// Cierra el aviso de las fallas sin reintentar.
  void descartarFalla() {
    if (state.fallas.isEmpty) return;
    state = UnionesPendientesState(
      pendiente: state.pendiente,
      ocultas: state.ocultas,
      duplicadasEnCurso: state.duplicadasEnCurso,
    );
  }

  void _alCumplirse() {
    final union = _pendiente;
    if (union == null) return;
    _reloj = null;
    _pendiente = null;
    state = UnionesPendientesState(
      ocultas: state.ocultas,
      duplicadasEnCurso: state.duplicadasEnCurso,
      fallas: state.fallas,
    );
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

  /// No lanza: lo que salga mal se traduce a [UnionesPendientesState.fallas].
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
    if (falla == null) return;
    final fallaDeLaUnion = FallaUnion(union: union, falla: falla);
    if (!ref.mounted) {
      // La pantalla ya se fue, pero la colportora vio «quedaron unidas en una»: la Lista le dice que
      // no pasó (el repositorio dejó el log).
      _fueraDePantalla.registrar(fallaDeLaUnion);
      return;
    }
    state = UnionesPendientesState(
      pendiente: state.pendiente,
      ocultas: {...state.ocultas}..remove(union.clavePar),
      duplicadasEnCurso: {...state.duplicadasEnCurso}..remove(union.duplicadaId),
      fallas: [
        for (final f in state.fallas)
          if (f.union.clavePar != union.clavePar) f,
        fallaDeLaUnion,
      ],
    );
  }
}

/// Las uniones en marcha de «Posibles duplicados». Se descarta con la pantalla, y al descartarse
/// hace definitiva la que esperaba sus 8 s.
final unionesPendientesProvider =
    NotifierProvider.autoDispose<UnionesPendientesNotifier, UnionesPendientesState>(
      UnionesPendientesNotifier.new,
    );
