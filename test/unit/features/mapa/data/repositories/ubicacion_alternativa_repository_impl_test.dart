// Traducción de errores del repositorio de la ubicación alternativa de cobranza (HU-UBI-013).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_alternativa_local_data_source.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_alternativa_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _Local implements UbicacionAlternativaLocalDataSource {
  Object? lanza;
  var llamadas = 0;

  final estados = Stream.value(const SinUbicacionAlternativa());

  @override
  Stream<EstadoUbicacionAlternativa> observar({
    required String personaId,
    required String espacioId,
  }) => estados;

  @override
  Stream<List<Ubicacion>> observarCandidatas({
    required String colportorId,
    required String espacioId,
  }) => Stream.value(const []);

  Future<EspacioPersona> _responder(String? alternativa) async {
    llamadas++;
    final error = lanza;
    if (error != null) throw error;
    return EspacioPersona(
      id: 'ep-1',
      espacioId: 'esp-1',
      personaId: 'per-1',
      ubicacionCobranzaAltId: alternativa,
      auditoria: Auditoria(
        createdAt: DateTime.utc(2026, 10, 22),
        updatedAt: DateTime.utc(2026, 10, 22),
      ),
    );
  }

  @override
  Future<EspacioPersona> establecer({
    required String personaId,
    required String espacioId,
    required String ubicacionId,
    required String colportorId,
    required DateTime ahora,
  }) => _responder(ubicacionId);

  @override
  Future<EspacioPersona> quitar({
    required String personaId,
    required String espacioId,
    required DateTime ahora,
  }) => _responder(null);
}

void main() {
  final ahora = DateTime.utc(2026, 10, 26, 9);
  late _Local local;
  late UbicacionAlternativaRepositoryImpl repositorio;

  setUp(() {
    local = _Local();
    repositorio = UbicacionAlternativaRepositoryImpl(local, logger: loggerMudo());
  });

  Future<Either<Failure, EspacioPersona>> establecer() => repositorio.establecer(
    personaId: 'per-1',
    espacioId: 'esp-1',
    ubicacionId: 'ub-2',
    colportorId: 'col-1',
    ahora: ahora,
  );

  test(
    'dado un cambio que sale bien, cuando se establece o se quita, devuelve el vínculo',
    () async {
      final fijado = await repositorio.establecer(
        personaId: 'per-1',
        espacioId: 'esp-1',
        ubicacionId: 'ub-2',
        colportorId: 'col-1',
        ahora: ahora,
      );
      final quitado = await repositorio.quitar(
        personaId: 'per-1',
        espacioId: 'esp-1',
        ahora: ahora,
      );

      expect(fijado.getOrElse(() => throw StateError('falló')).ubicacionCobranzaAltId, 'ub-2');
      expect(quitado.getOrElse(() => throw StateError('falló')).ubicacionCobranzaAltId, isNull);
    },
  );

  test('dado un rechazo de la persistencia, cuando se establece, devuelve un FailureValidacion con '
      'el campo y el mensaje del motivo', () async {
    for (final motivo in MotivoRechazoUbicacionAlternativa.values) {
      local.lanza = UbicacionAlternativaRechazadaException(motivo);

      final r = await establecer();

      expect(
        r,
        Left<Failure, EspacioPersona>(FailureValidacion(campos: {motivo.campo: motivo.mensaje})),
        reason: motivo.name,
      );
    }
  });

  test('dado un rechazo, cuando se quita, también es un FailureValidacion', () async {
    local.lanza = const UbicacionAlternativaRechazadaException(
      MotivoRechazoUbicacionAlternativa.personaDeBaja,
    );

    final r = await repositorio.quitar(personaId: 'per-1', espacioId: 'esp-1', ahora: ahora);

    expect(r.isLeft(), isTrue);
    expect(r.fold((f) => f, (_) => null), isA<FailureValidacion>());
  });

  test('dada cualquier otra excepción, cuando se establece, devuelve FailureInesperado con solo el '
      'tipo: la sentencia de Drift trae datos de la persona', () async {
    local.lanza = StateError('INSERT ... Ana Martínez 099 123 456');

    final r = await establecer();

    expect(r.isLeft(), isTrue);
    final falla = r.fold((f) => f, (_) => null);
    expect(falla, const FailureInesperado(causa: 'StateError'));
    expect(falla.toString(), isNot(contains('Ana')));
  });

  test(
    'dada una falla, cuando se reintenta y sale bien, el repositorio no quedó trabado',
    () async {
      local.lanza = StateError('disco');
      expect((await establecer()).isLeft(), isTrue);

      local.lanza = null;

      expect((await establecer()).isRight(), isTrue);
      expect(local.llamadas, 2);
    },
  );

  test('dadas las lecturas, cuando se observan, salen tal cual las da la persistencia', () async {
    expect(
      await repositorio.observar(personaId: 'per-1', espacioId: 'esp-1').first,
      const SinUbicacionAlternativa(),
    );
    expect(
      await repositorio.observarCandidatas(colportorId: 'col-1', espacioId: 'esp-1').first,
      isEmpty,
    );
  });
}
