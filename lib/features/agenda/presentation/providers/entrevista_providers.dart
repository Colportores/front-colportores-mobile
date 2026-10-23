import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../data/datasources/ultima_visita_del_colportor_drift.dart';
import '../../data/repositories/entrevista_en_curso_repository_almacen.dart';
import '../../domain/entities/entrevista_en_curso.dart';
import '../../domain/repositories/entrevista_en_curso_repository.dart';
import '../../domain/services/ultima_visita_del_colportor.dart';
import '../../domain/usecases/empezar_entrevista_use_case.dart';
import '../../domain/usecases/finalizar_entrevista_use_case.dart';
import '../../domain/usecases/registrar_resultado_visita_use_case.dart';
import 'agenda_providers.dart';

// Cableado de la entrevista en curso (vista 39, R·05 a R·07; #450).

/// Dónde vive la entrevista en curso: el almacén seguro del teléfono. Un test lo reemplaza.
final entrevistaEnCursoRepositoryProvider = Provider<EntrevistaEnCursoRepository>(
  (ref) => EntrevistaEnCursoRepositoryAlmacen(ref.watch(almacenSeguroProvider)),
);

/// Reloj de la entrevista (inicio, salida y validación); un test lo reemplaza.
final relojEntrevistaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// UUID v7 de los ids de la visita y la nota; un test lo reemplaza para fijarlos.
final generadorIdEntrevistaProvider = Provider<String Function()>((ref) => const Uuid().v7);

final empezarEntrevistaUseCaseProvider = Provider<EmpezarEntrevistaUseCase>(
  (ref) => EmpezarEntrevistaUseCase(
    ref.watch(entrevistaEnCursoRepositoryProvider),
    generarId: ref.watch(generadorIdEntrevistaProvider),
    ahora: ref.watch(relojEntrevistaProvider),
  ),
);

final finalizarEntrevistaUseCaseProvider = Provider<FinalizarEntrevistaUseCase>(
  (ref) => FinalizarEntrevistaUseCase(
    ref.watch(registrarResultadoVisitaUseCaseProvider),
    ref.watch(entrevistaEnCursoRepositoryProvider),
    ahora: ref.watch(relojEntrevistaProvider),
  ),
);

/// La hora de la visita anterior de la colportora (R·07). Sin DB abierta no hay de dónde leerla:
/// lanza, y quien la lee la trata como «no hay».
final ultimaVisitaDelColportorProvider = Provider<UltimaVisitaDelColportor>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return UltimaVisitaDelColportorDrift(db);
});

/// Lo que la pantalla sabe de la entrevista en curso de una colportora.
final class EstadoEntrevista extends Equatable {
  const EstadoEntrevista({
    this.cargando = true,
    this.entrevista,
    this.recuperada = false,
    this.notaBorrador = '',
  });

  /// Leyendo el almacén por primera vez.
  final bool cargando;

  /// La entrevista en curso, o `null` si no hay.
  final EntrevistaEnCurso? entrevista;

  /// `true` si ya estaba guardada cuando la app arrancó: se cerró la app (o se la mataron) desde que
  /// empezó. La hora de salida **no se supone**: se le pide (decisión de Cristian, 23/10, #450).
  final bool recuperada;

  /// La nota de la visita que va escribiendo. Solo en memoria: dónde guardarla si se cierra la app
  /// espera una decisión (ver el archivo de pendientes del #450).
  final String notaBorrador;

  bool get hayEntrevista => entrevista != null;

  EstadoEntrevista copiar({
    bool? cargando,
    EntrevistaEnCurso? Function()? entrevista,
    bool? recuperada,
    String? notaBorrador,
  }) => EstadoEntrevista(
    cargando: cargando ?? this.cargando,
    entrevista: entrevista != null ? entrevista() : this.entrevista,
    recuperada: recuperada ?? this.recuperada,
    notaBorrador: notaBorrador ?? this.notaBorrador,
  );

  /// Lleva la nota (dato personal): nunca debe salir en un log ni en un `toString`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [cargando, entrevista, recuperada, notaBorrador];
}

/// La entrevista en curso de la colportora [colportorId]: la lee al arrancar, la empieza y la
/// termina. Sin lógica de negocio (vive en los casos de uso): traduce resultados a estado.
///
/// Si el almacén no se puede leer, la colportora no tiene entrevista en curso para la pantalla (no
/// se rompe el mapa por esto) y el error queda en el log.
final class EntrevistaEnCursoNotifier extends Notifier<EstadoEntrevista> {
  EntrevistaEnCursoNotifier(this.colportorId);

  final String colportorId;

  /// El «Empezar» en vuelo, si lo hay, y un solo «Guardar» a la vez: un segundo toque no repite el
  /// primero.
  Future<Either<Failure, EntrevistaEnCurso>>? _empezando;
  bool _finalizando = false;

  /// Se completa cuando terminó la primera lectura del almacén (o el provider se descartó).
  Completer<void> _lectura = Completer<void>();

  @override
  EstadoEntrevista build() {
    final lectura = _lectura = Completer<void>();
    ref.onDispose(() {
      if (!lectura.isCompleted) lectura.complete();
    });
    unawaited(
      Future<void>.microtask(_cargar).whenComplete(() {
        if (!lectura.isCompleted) lectura.complete();
      }),
    );
    return const EstadoEntrevista();
  }

  /// El estado ya leído del almacén: espera la primera lectura si todavía no terminó. Para quien
  /// decide algo según haya o no una entrevista en curso (por ejemplo, al finalizar la jornada).
  Future<EstadoEntrevista> esperarLectura() async {
    await _lectura.future;
    return state;
  }

  Future<void> _cargar() async {
    EntrevistaEnCurso? guardada;
    try {
      guardada = await ref.read(entrevistaEnCursoRepositoryProvider).leer(colportorId);
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ENTREVISTA_LEER',
        'no se pudo leer la entrevista en curso',
        {'tipo': e.runtimeType.toString()},
      );
    }
    if (!ref.mounted) return;
    // Si en esta sesión ya empezó una mientras se leía, manda lo que está en el estado.
    if (state.hayEntrevista) {
      state = state.copiar(cargando: false);
      return;
    }
    state = state.copiar(cargando: false, entrevista: () => guardada, recuperada: guardada != null);
  }

  /// «Empezar entrevista». Devuelve la entrevista (la que ya estaba en curso, si la había) o la
  /// falla. Un segundo toque mientras guarda **espera al primero y devuelve lo mismo**: así dos toques
  /// seguidos no escriben dos horas de inicio distintas.
  Future<Either<Failure, EntrevistaEnCurso>> empezar({
    required String espacioId,
    required String espacioPersonaId,
    String? agendaId,
    String? jornadaId,
  }) {
    final enVuelo = _empezando;
    if (enVuelo != null) return enVuelo;
    final nueva = _empezar(
      espacioId: espacioId,
      espacioPersonaId: espacioPersonaId,
      agendaId: agendaId,
      jornadaId: jornadaId,
    );
    _empezando = nueva;
    unawaited(
      nueva.whenComplete(() {
        if (identical(_empezando, nueva)) _empezando = null;
      }),
    );
    return nueva;
  }

  Future<Either<Failure, EntrevistaEnCurso>> _empezar({
    required String espacioId,
    required String espacioPersonaId,
    String? agendaId,
    String? jornadaId,
  }) async {
    try {
      final resultado = await ref.read(empezarEntrevistaUseCaseProvider)(
        EmpezarEntrevistaParams(
          colportorId: colportorId,
          espacioId: espacioId,
          espacioPersonaId: espacioPersonaId,
          agendaId: agendaId,
          jornadaId: jornadaId,
        ),
      );
      if (ref.mounted) {
        resultado.fold<void>(
          (_) {},
          (entrevista) => state = state.copiar(
            cargando: false,
            entrevista: () => entrevista,
            recuperada: false,
          ),
        );
      }
      return resultado;
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }

  /// Guarda la nota que escribe (en memoria).
  void escribirNota(String texto) {
    if (state.notaBorrador == texto) return;
    state = state.copiar(notaBorrador: texto);
  }

  /// «No, guardar y volver al mapa». Un segundo toque mientras guarda no guarda otra vez: devuelve
  /// `null`. Al guardar bien, ya no hay entrevista en curso.
  Future<Either<Failure, ResultadoVisitaRegistrado>?> finalizar({
    required DateTime entrada,
    required DateTime salida,
  }) async {
    final entrevista = state.entrevista;
    if (entrevista == null) return const Left(sinEntrevistaEnCurso);
    if (_finalizando) return null;
    _finalizando = true;
    try {
      final resultado = await ref.read(finalizarEntrevistaUseCaseProvider)(
        FinalizarEntrevistaParams.de(
          entrevista,
          entrada: entrada,
          salida: salida,
          nota: state.notaBorrador,
        ),
      );
      if (ref.mounted) {
        resultado.fold<void>(
          (_) {},
          (_) => state = state.copiar(entrevista: () => null, recuperada: false, notaBorrador: ''),
        );
      }
      return resultado;
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    } finally {
      _finalizando = false;
    }
  }

  /// R·07: termina una entrevista **sin inicio registrado** (no hay entrevista en curso): guarda la
  /// visita con los [params] que arma la pantalla (con sus ids fijos para el reintento).
  Future<Either<Failure, ResultadoVisitaRegistrado>> finalizarSinInicio(
    FinalizarEntrevistaParams params,
  ) async {
    try {
      return await ref.read(finalizarEntrevistaUseCaseProvider)(params);
    } on Object catch (e) {
      return Left(FailureInesperado(causa: e.runtimeType.toString()));
    }
  }

  /// La hora de la visita anterior, para la entrada cuando no se registró el inicio (R·07), o
  /// `null` si no hay: nunca se inventa.
  Future<DateTime?> horaDeLaVisitaAnterior() async {
    try {
      return await ref
          .read(ultimaVisitaDelColportorProvider)
          .fechaAntesDe(colportorId, ref.read(relojEntrevistaProvider)());
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.agenda,
        'ENTREVISTA_VISITA_ANTERIOR',
        'no se pudo leer la visita anterior',
        {'tipo': e.runtimeType.toString()},
      );
      return null;
    }
  }
}

/// No hay una entrevista en curso para terminar (ya la terminó otro toque, o nunca empezó).
const sinEntrevistaEnCurso = FailureValidacion(
  campos: {'entrevista': 'No hay una entrevista en curso.'},
  mensaje: 'No hay una entrevista en curso. Volvé al mapa y empezá una desde la casa.',
);

final entrevistaEnCursoProvider =
    NotifierProvider.family<EntrevistaEnCursoNotifier, EstadoEntrevista, String>(
      EntrevistaEnCursoNotifier.new,
    );
