// Los casos de uso de la ubicación alternativa de cobranza (HU-UBI-013), con un repositorio de
// mentira. Los escenarios llevan el título de la HU.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_alternativa_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/ubicacion_alternativa_use_cases.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _Repo implements UbicacionAlternativaRepository {
  final llamadas = <String>[];
  DateTime? ultimoAhora;
  Either<Failure, EspacioPersona>? respuesta;

  @override
  Stream<EstadoUbicacionAlternativa> observar({
    required String personaId,
    required String espacioId,
  }) {
    llamadas.add('observar $personaId $espacioId');
    return Stream.value(const UbicacionAlternativaDeBaja('ub-2'));
  }

  @override
  Stream<List<Ubicacion>> observarCandidatas({
    required String colportorId,
    required String espacioId,
  }) {
    llamadas.add('candidatas $colportorId $espacioId');
    return Stream.value(const []);
  }

  @override
  Future<Either<Failure, EspacioPersona>> establecer({
    required String personaId,
    required String espacioId,
    required String ubicacionId,
    required String colportorId,
    required DateTime ahora,
  }) async {
    llamadas.add('establecer $personaId $espacioId $ubicacionId $colportorId');
    ultimoAhora = ahora;
    return respuesta ?? Right(_vinculo(ubicacionId));
  }

  @override
  Future<Either<Failure, EspacioPersona>> quitar({
    required String personaId,
    required String espacioId,
    required DateTime ahora,
  }) async {
    llamadas.add('quitar $personaId $espacioId');
    ultimoAhora = ahora;
    return respuesta ?? Right(_vinculo(null));
  }
}

EspacioPersona _vinculo(String? alternativa) => EspacioPersona(
  id: 'ep-1',
  espacioId: 'esp-1',
  personaId: 'per-1',
  ubicacionCobranzaAltId: alternativa,
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 22),
    updatedAt: DateTime.utc(2026, 10, 22),
  ),
);

void main() {
  final reloj = DateTime.utc(2026, 10, 26, 9, 30);
  late _Repo repo;
  late EstablecerUbicacionAlternativaUseCase establecer;
  late QuitarUbicacionAlternativaUseCase quitar;

  setUp(() {
    repo = _Repo();
    establecer = EstablecerUbicacionAlternativaUseCase(repo, ahora: () => reloj);
    quitar = QuitarUbicacionAlternativaUseCase(repo, ahora: () => reloj);
  });

  group('Escenario: Asignar ubicación alternativa existente', () {
    test('dados los ids, cuando se establece, llega al repositorio con el reloj y devuelve el '
        'vínculo con la alternativa', () async {
      final r = await establecer(
        const EstablecerUbicacionAlternativaParams(
          personaId: ' per-1 ',
          espacioId: 'esp-1',
          ubicacionId: 'ub-2',
          colportorId: 'col-1',
        ),
      );

      expect(r.getOrElse(() => throw StateError('falló')).ubicacionCobranzaAltId, 'ub-2');
      expect(repo.llamadas, ['establecer per-1 esp-1 ub-2 col-1']);
      expect(repo.ultimoAhora, reloj);
    });

    test(
      'dado un id vacío o en blanco, cuando se establece, devuelve una validación por campo y no '
      'llama al repositorio',
      () async {
        final r = await establecer(
          const EstablecerUbicacionAlternativaParams(
            personaId: '',
            espacioId: ' ',
            ubicacionId: '',
            colportorId: '\t',
          ),
        );

        expect(
          r,
          const Left<Failure, EspacioPersona>(
            FailureValidacion(
              campos: {
                'persona': 'Falta la persona',
                'espacio': 'Falta el espacio',
                'ubicacionAlternativa': 'Elegí la ubicación alternativa',
                'colportor': 'Falta quién cobra',
              },
            ),
          ),
        );
        expect(repo.llamadas, isEmpty);
      },
    );

    test('dado un rechazo del repositorio, cuando se establece, la falla sale tal cual', () async {
      repo.respuesta = const Left(FailureValidacion(campos: {'ubicacionAlternativa': 'x'}));

      final r = await establecer(
        const EstablecerUbicacionAlternativaParams(
          personaId: 'per-1',
          espacioId: 'esp-1',
          ubicacionId: 'ub-2',
          colportorId: 'col-1',
        ),
      );

      expect(
        r,
        const Left<Failure, EspacioPersona>(
          FailureValidacion(campos: {'ubicacionAlternativa': 'x'}),
        ),
      );
    });
  });

  group('Escenario: Quitar ubicación alternativa', () {
    test('dada una persona, cuando se quita, llega al repositorio con el reloj', () async {
      final r = await quitar(
        const QuitarUbicacionAlternativaParams(personaId: 'per-1', espacioId: 'esp-1'),
      );

      expect(r.getOrElse(() => throw StateError('falló')).ubicacionCobranzaAltId, isNull);
      expect(repo.llamadas, ['quitar per-1 esp-1']);
      expect(repo.ultimoAhora, reloj);
    });

    test(
      'dado un id vacío, cuando se quita, devuelve una validación y no llama al repositorio',
      () async {
        final r = await quitar(
          const QuitarUbicacionAlternativaParams(personaId: ' ', espacioId: ''),
        );

        expect(
          r,
          const Left<Failure, EspacioPersona>(
            FailureValidacion(
              campos: {'persona': 'Falta la persona', 'espacio': 'Falta el espacio'},
            ),
          ),
        );
        expect(repo.llamadas, isEmpty);
      },
    );
  });

  group('lecturas', () {
    test(
      'dado el repositorio, cuando se observa la alternativa, pasa el estado tal cual (de baja: no '
      'se sugiere)',
      () async {
        final estado = await ObservarUbicacionAlternativaUseCase(repo)(
          personaId: 'per-1',
          espacioId: 'esp-1',
        ).first;

        expect(estado, const UbicacionAlternativaDeBaja('ub-2'));
        expect(estado.sugerida, isNull);
        expect(repo.llamadas, ['observar per-1 esp-1']);
      },
    );

    test(
      'dado el repositorio, cuando se observan las candidatas, pasa quién cobra y el espacio',
      () async {
        final candidatas = await ObservarCandidatasAlternativaUseCase(repo)(
          colportorId: 'col-1',
          espacioId: 'esp-1',
        ).first;

        expect(candidatas, isEmpty);
        expect(repo.llamadas, ['candidatas col-1 esp-1']);
      },
    );
  });
}
