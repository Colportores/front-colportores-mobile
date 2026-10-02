// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests). El scan y
// la resolución contra la DB real están en duplicados_drift_test.dart.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_baja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/pares_duplicados_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/consultor_pendientes_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/baja_ubicacion_use_cases.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/duplicados_ubicacion_use_cases.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/area_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/ubicacion_sin_modificar.dart';

final _t0 = DateTime.utc(2026, 9, 1, 10);

Ubicacion _ubicacion(String id, {double metrosAlNorte = 0, DateTime? deletedAt}) => Ubicacion(
  id: id,
  tipo: TipoUbicacion.casa,
  calle: 'Av. Italia',
  numero: '1234',
  lat: -34.891 + metrosAlNorte / 111195.08,
  lon: -56.125,
  ciudadId: 'mvd',
  auditoria: Auditoria(createdAt: _t0, updatedAt: _t0, createdBy: 'col-1', deletedAt: deletedAt),
);

final class _Ubicaciones with UbicacionRepositorySinModificar implements UbicacionRepository {
  List<Ubicacion> propias = [];
  Object? errorAlObservar;
  final porId = <String, Ubicacion>{};
  Failure? fallaAlObtener;
  final pedidos = <({String colportorId, bool incluirBajas})>[];
  final bajas = <({String id, DateTime baseUpdatedAt, bool conMotivo, String? conservadaId})>[];

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) {
    pedidos.add((colportorId: colportorId, incluirBajas: incluirBajas));
    final error = errorAlObservar;
    return error != null ? Stream.error(error) : Stream.value(propias);
  }

  @override
  Future<Either<Failure, Ubicacion?>> obtener(String id) async =>
      fallaAlObtener != null ? Left(fallaAlObtener!) : Right(porId[id]);

  @override
  Future<Either<Failure, CambioDeBaja>> cambiarBaja(
    String id, {
    required bool baja,
    required DateTime baseUpdatedAt,
    required DateTime ahora,
    bool conMotivo = false,
    String? conservadaId,
  }) async {
    bajas.add((
      id: id,
      baseUpdatedAt: baseUpdatedAt,
      conMotivo: conMotivo,
      conservadaId: conservadaId,
    ));
    final actual = porId[id]!;
    return Right((
      ubicacion: Ubicacion(
        id: actual.id,
        tipo: actual.tipo,
        calle: actual.calle,
        numero: actual.numero,
        lat: actual.lat,
        lon: actual.lon,
        ciudadId: actual.ciudadId,
        auditoria: Auditoria(createdAt: _t0, updatedAt: ahora, deletedAt: baja ? ahora : null),
      ),
      escribio: true,
    ));
  }

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) => throw UnimplementedError();

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => throw UnimplementedError();
}

final class _Pares implements ParesDuplicadosRepository {
  Map<String, DateTime> guardados = {};
  Failure? fallaAlLeer;
  final decisiones = <({String clave, DecisionParDuplicado decision, DateTime ahora})>[];

  @override
  Future<Either<Failure, Map<String, DateTime>>> decididos() async =>
      fallaAlLeer != null ? Left(fallaAlLeer!) : Right(guardados);

  @override
  Future<Either<Failure, Unit>> decidir(
    ParDuplicado par,
    DecisionParDuplicado decision, {
    required DateTime ahora,
  }) async {
    decisiones.add((clave: par.clave, decision: decision, ahora: ahora));
    return const Right(unit);
  }
}

final class _SinPendientes implements ConsultorPendientesUbicacion {
  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async =>
      const Right(PendientesUbicacion.ninguno);
}

Failure _falla<T>(Either<Failure, T> r) => r.swap().getOrElse(() => throw StateError('era Right'));

T _ok<T>(Either<Failure, T> r) => r.getOrElse(() => throw StateError('era Left'));

void main() {
  late _Ubicaciones ubicaciones;
  late _Pares pares;

  setUp(() {
    ubicaciones = _Ubicaciones();
    pares = _Pares();
  });

  group('ConsultarParesDuplicadosUseCase', () {
    final ahora = DateTime.utc(2026, 10, 1, 12);
    late ConsultarParesDuplicadosUseCase consultar;

    setUp(
      () => consultar = ConsultarParesDuplicadosUseCase(ubicaciones, pares, ahora: () => ahora),
    );

    const params = ConsultarParesDuplicadosParams(colportorId: ' col-1 ');

    test('dado dos ubicaciones propias con la misma dirección, cuando escanea, devuelve el par y '
        'lee solo las activas del colportor', () async {
      ubicaciones.propias = [_ubicacion('ub-a'), _ubicacion('ub-b', metrosAlNorte: 300)];

      final lista = _ok(await consultar(params));

      expect(lista.map((p) => p.clave), ['ub-a|ub-b']);
      expect(ubicaciones.pedidos, [(colportorId: 'col-1', incluirBajas: false)]);
    });

    test('dado un par decidido hace menos de 30 días, cuando escanea, no aparece; a los 30 días '
        'justos, vuelve', () async {
      ubicaciones.propias = [_ubicacion('ub-a'), _ubicacion('ub-b', metrosAlNorte: 300)];
      pares.guardados = {
        'ub-a|ub-b': ahora.subtract(const Duration(days: 30)).add(const Duration(milliseconds: 1)),
      };

      expect(_ok(await consultar(params)), isEmpty);

      pares.guardados = {'ub-a|ub-b': ahora.subtract(ConsultarParesDuplicadosUseCase.ventana)};
      expect(_ok(await consultar(params)), hasLength(1));
    });

    test(
      'dado el colportor en blanco, cuando escanea, devuelve FailureValidacion sin leer nada',
      () async {
        final f = _falla(await consultar(const ConsultarParesDuplicadosParams(colportorId: '  ')));

        expect(f, isA<FailureValidacion>());
        expect(ubicaciones.pedidos, isEmpty);
      },
    );

    test(
      'dado que la lectura de ubicaciones falla, cuando escanea, devuelve FailureInesperado',
      () async {
        ubicaciones.errorAlObservar = StateError('disco');

        expect(_falla(await consultar(params)), isA<FailureInesperado>());
      },
    );

    test('dado que la lectura de decisiones falla, cuando escanea, devuelve esa falla', () async {
      pares.fallaAlLeer = const FailureInesperado();

      expect(_falla(await consultar(params)), const FailureInesperado());
    });
  });

  group('DecidirParDuplicadoUseCase', () {
    final ahora = DateTime.utc(2026, 10, 1, 12);
    late DecidirParDuplicadoUseCase decidir;

    setUp(() => decidir = DecidirParDuplicadoUseCase(pares, ahora: () => ahora));

    ParDuplicado par({required bool admite}) => ParDuplicado(
      a: _ubicacion('ub-a'),
      b: _ubicacion('ub-b', metrosAlNorte: 300),
      motivo: MotivoDuplicado.mismaDireccion,
      distanciaMetros: 300,
      admiteConservarAmbos: admite,
    );

    test('dado un par que lo admite, cuando elige "Conservar ambos", guarda la decisión con la '
        'fecha de ahora', () async {
      final r = await decidir(
        DecidirParDuplicadoParams(
          par: par(admite: true),
          decision: DecisionParDuplicado.conservarAmbos,
        ),
      );

      expect(r, const Right<Failure, Unit>(unit));
      expect(pares.decisiones, [
        (clave: 'ub-a|ub-b', decision: DecisionParDuplicado.conservarAmbos, ahora: ahora),
      ]);
    });

    test('dado un par con la misma dirección que no lo admite (D1 opción (a)), cuando elige '
        '"Conservar ambos", devuelve FailureDuplicadoMismaDireccion y no guarda nada', () async {
      final r = await decidir(
        DecidirParDuplicadoParams(
          par: par(admite: false),
          decision: DecisionParDuplicado.conservarAmbos,
        ),
      );

      expect(_falla(r), const FailureDuplicadoMismaDireccion());
      expect(pares.decisiones, isEmpty);
    });

    test(
      'dado un par que no admite conservar ambos, cuando elige "Ignorar", lo guarda igual',
      () async {
        await decidir(
          DecidirParDuplicadoParams(
            par: par(admite: false),
            decision: DecisionParDuplicado.ignorar,
          ),
        );

        expect(pares.decisiones.single.decision, DecisionParDuplicado.ignorar);
      },
    );
  });

  group('MarcarDuplicadoUseCase', () {
    final ahora = DateTime.utc(2026, 10, 1, 12);
    late MarcarDuplicadoUseCase marcar;

    setUp(() {
      marcar = MarcarDuplicadoUseCase(
        ubicaciones,
        DarDeBajaUbicacionUseCase(ubicaciones, _SinPendientes(), ahora: () => ahora),
      );
      ubicaciones.porId
        ..['ub-a'] = _ubicacion('ub-a')
        ..['ub-b'] = _ubicacion('ub-b', metrosAlNorte: 300);
    });

    MarcarDuplicadoParams params({String conservar = 'ub-a', String duplicada = 'ub-b'}) =>
        MarcarDuplicadoParams(
          conservarId: conservar,
          duplicadaId: duplicada,
          baseUpdatedAtDuplicada: _t0,
        );

    test('dado el par A–B, cuando marca B como duplicado conservando A, da de baja B con motivo '
        'y no toca A', () async {
      final r = _ok(await marcar(params()));

      expect(r, isA<UbicacionDadaDeBaja>());
      expect((r as UbicacionDadaDeBaja).ubicacion.id, 'ub-b');
      expect(ubicaciones.bajas, [
        (id: 'ub-b', baseUpdatedAt: _t0, conMotivo: true, conservadaId: 'ub-a'),
      ]);
    });

    test('dado el par A–B, cuando elige conservar B, da de baja A (se puede elegir cuál '
        'conservar)', () async {
      await marcar(
        MarcarDuplicadoParams(
          conservarId: 'ub-b',
          duplicadaId: 'ub-a',
          baseUpdatedAtDuplicada: _t0,
        ),
      );

      expect(ubicaciones.bajas.single.id, 'ub-a');
    });

    test('dado un id en blanco o el mismo en los dos, cuando marca, devuelve FailureValidacion y '
        'no escribe', () async {
      expect(_falla(await marcar(params(conservar: ' '))), isA<FailureValidacion>());
      expect(_falla(await marcar(params(duplicada: 'ub-a'))), isA<FailureValidacion>());
      expect(ubicaciones.bajas, isEmpty);
    });

    test('dado que la que se conserva ya no está, cuando marca, devuelve '
        'FailureUbicacionInexistente y no da de baja la otra', () async {
      ubicaciones.porId.remove('ub-a');

      expect(_falla(await marcar(params())), const FailureUbicacionInexistente());
      expect(ubicaciones.bajas, isEmpty);
    });

    test('dado que la que se conserva quedó de baja desde el scan, cuando marca, devuelve '
        'FailureConservadaDeBaja y no deja a las dos de baja', () async {
      ubicaciones.porId['ub-a'] = _ubicacion('ub-a', deletedAt: _t0);

      expect(_falla(await marcar(params())), const FailureConservadaDeBaja());
      expect(ubicaciones.bajas, isEmpty);
    });

    test('dado que leer la que se conserva falla, cuando marca, devuelve esa falla', () async {
      ubicaciones.fallaAlObtener = const FailureInesperado();

      expect(_falla(await marcar(params())), const FailureInesperado());
    });

    test('el motivo de la baja es el reason de la HU', () {
      expect(MarcarDuplicadoUseCase.motivoBaja('ub-a'), 'duplicado_de_ub-a');
    });
  });

  group('Igualdad por valor (Equatable)', () {
    test('dado dos instancias con los mismos datos, son iguales; con otro dato, distintas', () {
      CandidataDuplicado candidata(double metros) => CandidataDuplicado(
        ubicacion: _ubicacion('ub-a'),
        motivo: MotivoDuplicado.cercania,
        distanciaMetros: metros,
        admiteConservarAmbos: true,
      );
      ParDuplicado par(MotivoDuplicado motivo) => ParDuplicado(
        a: _ubicacion('ub-a'),
        b: _ubicacion('ub-b'),
        motivo: motivo,
        distanciaMetros: 3,
        admiteConservarAmbos: true,
      );
      MarcarDuplicadoParams marcar(String duplicada) => MarcarDuplicadoParams(
        conservarId: 'ub-a',
        duplicadaId: duplicada,
        baseUpdatedAtDuplicada: _t0,
      );

      expect(candidata(3), candidata(3));
      expect(candidata(3), isNot(candidata(4)));
      expect(par(MotivoDuplicado.cercania), par(MotivoDuplicado.cercania));
      expect(par(MotivoDuplicado.cercania), isNot(par(MotivoDuplicado.mismaDireccion)));
      expect(
        const ConsultarParesDuplicadosParams(colportorId: 'col-1'),
        isNot(const ConsultarParesDuplicadosParams(colportorId: 'col-2')),
      );
      expect(
        DecidirParDuplicadoParams(
          par: par(MotivoDuplicado.cercania),
          decision: DecisionParDuplicado.ignorar,
        ),
        isNot(
          DecidirParDuplicadoParams(
            par: par(MotivoDuplicado.cercania),
            decision: DecisionParDuplicado.conservarAmbos,
          ),
        ),
      );
      expect(marcar('ub-b'), marcar('ub-b'));
      expect(marcar('ub-b'), isNot(marcar('ub-c')));
    });
  });
}
