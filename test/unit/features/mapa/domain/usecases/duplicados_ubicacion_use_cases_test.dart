// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests). El scan y
// la resolución contra la DB real están en duplicados_drift_test.dart.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/marcador_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_union_duplicados.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/pares_duplicados_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/ubicacion_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
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
  final pedidos = <({String colportorId, bool incluirBajas})>[];

  /// La lista con resumen que sigue el caso de uso reactivo.
  StreamController<List<UbicacionConResumen>> lista = StreamController<List<UbicacionConResumen>>();
  var listaCancelada = false;

  final uniones = <({String conservadaId, String duplicadaId, DateTime ahora})>[];
  Either<Failure, ResultadoUnionDuplicados> respuestaUnion = const Right(
    ResultadoUnionDuplicados(escribio: true, espaciosPasados: 1),
  );

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
  Stream<List<UbicacionConResumen>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  }) {
    pedidos.add((colportorId: colportorId, incluirBajas: incluirBajas));
    lista = StreamController<List<UbicacionConResumen>>(onCancel: () => listaCancelada = true);
    return lista.stream;
  }

  @override
  Future<Either<Failure, ResultadoUnionDuplicados>> unirDuplicada(
    String conservadaId,
    String duplicadaId, {
    required DateTime ahora,
  }) async {
    uniones.add((conservadaId: conservadaId, duplicadaId: duplicadaId, ahora: ahora));
    return respuestaUnion;
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
  Map<String, ParDecidido> guardados = {};
  Failure? fallaAlLeer;
  final decisiones = <({String clave, DecisionParDuplicado decision, DateTime ahora})>[];

  StreamController<Map<String, ParDecidido>> cambios = StreamController<Map<String, ParDecidido>>();
  var cambiosCancelados = false;

  @override
  Future<Either<Failure, Map<String, ParDecidido>>> decididos() async =>
      fallaAlLeer != null ? Left(fallaAlLeer!) : Right(guardados);

  @override
  Stream<Map<String, ParDecidido>> observarDecididos() {
    cambios = StreamController<Map<String, ParDecidido>>(onCancel: () => cambiosCancelados = true);
    return cambios.stream;
  }

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
        'ub-a|ub-b': ParDecidido(
          decision: DecisionParDuplicado.ignorar,
          decididoEn: ahora.subtract(const Duration(days: 30)).add(const Duration(milliseconds: 1)),
        ),
      };

      expect(_ok(await consultar(params)), isEmpty);

      pares.guardados = {
        'ub-a|ub-b': ParDecidido(
          decision: DecisionParDuplicado.ignorar,
          decididoEn: ahora.subtract(ParDecidido.ventanaIgnorar),
        ),
      };
      expect(_ok(await consultar(params)), hasLength(1));
    });

    test(
      'dado un par que el colportor marcó como "Son distintos", cuando escanea, no vuelve nunca, '
      'ni pasados mil días',
      () async {
        ubicaciones.propias = [_ubicacion('ub-a'), _ubicacion('ub-b', metrosAlNorte: 300)];
        pares.guardados = {
          'ub-a|ub-b': ParDecidido(
            decision: DecisionParDuplicado.conservarAmbos,
            decididoEn: ahora.subtract(const Duration(days: 1000)),
          ),
        };

        expect(_ok(await consultar(params)), isEmpty);
      },
    );

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

    test('dado un par con la misma dirección que no lo admite (D1: a menos de 100 m), cuando elige '
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

  group('UnirDuplicadosUseCase', () {
    final ahora = DateTime.utc(2026, 10, 1, 12);
    late UnirDuplicadosUseCase unir;

    setUp(() => unir = UnirDuplicadosUseCase(ubicaciones, ahora: () => ahora));

    test('dado el par A-B, cuando une conservando A, le pide a la base la unión con la hora de '
        'ahora y devuelve lo que hizo', () async {
      final r = _ok(
        await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b')),
      );

      expect(r, const ResultadoUnionDuplicados(escribio: true, espaciosPasados: 1));
      expect(ubicaciones.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b', ahora: ahora)]);
    });

    test('dado el par A-B, cuando elige conservar B, la que se conserva es B (se puede elegir '
        'cuál)', () async {
      await unir(const UnirDuplicadosParams(conservarId: 'ub-b', duplicadaId: 'ub-a'));

      expect(ubicaciones.uniones.single.conservadaId, 'ub-b');
      expect(ubicaciones.uniones.single.duplicadaId, 'ub-a');
    });

    test('dado ids con espacios alrededor, cuando une, los usa sin ellos', () async {
      await unir(const UnirDuplicadosParams(conservarId: ' ub-a ', duplicadaId: ' ub-b '));

      expect(ubicaciones.uniones.single.conservadaId, 'ub-a');
      expect(ubicaciones.uniones.single.duplicadaId, 'ub-b');
    });

    test('dado un id en blanco o el mismo en los dos, cuando une, devuelve FailureValidacion y no '
        'escribe', () async {
      const enBlanco = UnirDuplicadosParams(conservarId: ' ', duplicadaId: 'ub-b');
      const otraEnBlanco = UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: '');
      const lasMismas = UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: ' ub-a');

      expect(_falla(await unir(enBlanco)), isA<FailureValidacion>());
      expect(_falla(await unir(otraEnBlanco)), isA<FailureValidacion>());
      expect(_falla(await unir(lasMismas)), isA<FailureValidacion>());
      expect(ubicaciones.uniones, isEmpty);
    });

    test('dado que la que se conserva está de baja, cuando une, devuelve esa falla tal cual (la '
        'base no escribe nada)', () async {
      ubicaciones.respuestaUnion = const Left(FailureConservadaDeBaja());

      final f = _falla(
        await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b')),
      );

      expect(f, const FailureConservadaDeBaja());
    });

    test('dado que la duplicada ya estaba unida, cuando une, devuelve yaUnida', () async {
      ubicaciones.respuestaUnion = const Right(ResultadoUnionDuplicados.yaUnida);

      final r = _ok(
        await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b')),
      );

      expect(r.escribio, isFalse);
    });
  });

  group('ObservarParesDuplicadosUseCase', () {
    final ahora = DateTime.utc(2026, 10, 1, 12);
    late ObservarParesDuplicadosUseCase observar;
    late List<List<ParaRevisar>> emisiones;
    late List<Object> errores;
    late StreamSubscription<List<ParaRevisar>> suscripcion;

    UbicacionConResumen resumen(Ubicacion u, {int espacios = 1, EstadoCasa? estado}) =>
        UbicacionConResumen(ubicacion: u, cantidadEspacios: espacios, estado: estado);

    Future<void> asentar() => Future<void>.delayed(Duration.zero);

    setUp(() {
      observar = ObservarParesDuplicadosUseCase(ubicaciones, pares, ahora: () => ahora);
      emisiones = [];
      errores = [];
      suscripcion = observar('col-1').listen(emisiones.add, onError: errores.add);
    });

    tearDown(() async => suscripcion.cancel());

    final a = _ubicacion('ub-a');
    final b = _ubicacion('ub-b', metrosAlNorte: 300);

    test('dado que solo llegó la lista, cuando espera las decisiones, no emite todavía (un par '
        'decidido no puede aparecer un instante)', () async {
      ubicaciones.lista.add([resumen(a), resumen(b)]);
      await asentar();

      expect(emisiones, isEmpty);
    });

    test(
      'dado la lista y las decisiones, cuando llegan las dos, emite el par con los espacios y el '
      'estado de cada ubicación',
      () async {
        ubicaciones.lista.add([
          resumen(a, espacios: 2, estado: EstadoCasa.entrevistaHecha),
          resumen(b),
        ]);
        pares.cambios.add({});
        await asentar();

        expect(emisiones, hasLength(1));
        final item = emisiones.single.single;
        expect(item.par.clave, 'ub-a|ub-b');
        expect(item.espaciosA, 2);
        expect(item.espaciosB, 1);
        expect(item.estadoA, EstadoCasa.entrevistaHecha);
        expect(item.estadoB, isNull);
        expect(ubicaciones.pedidos, [(colportorId: 'col-1', incluirBajas: false)]);
      },
    );

    test('dado un par en la lista, cuando el colportor dice "Son distintos", sale solo y no '
        'vuelve', () async {
      ubicaciones.lista.add([resumen(a), resumen(b)]);
      pares.cambios.add({});
      await asentar();
      expect(emisiones.last, hasLength(1));

      pares.cambios.add({
        'ub-a|ub-b': ParDecidido(decision: DecisionParDuplicado.conservarAmbos, decididoEn: ahora),
      });
      await asentar();

      expect(emisiones.last, isEmpty);
    });

    test('dado un par ignorado hace 30 días justos, cuando se leen las decisiones, vuelve a la '
        'lista', () async {
      ubicaciones.lista.add([resumen(a), resumen(b)]);
      pares.cambios.add({
        'ub-a|ub-b': ParDecidido(
          decision: DecisionParDuplicado.ignorar,
          decididoEn: ahora.subtract(ParDecidido.ventanaIgnorar),
        ),
      });
      await asentar();

      expect(emisiones.single, hasLength(1));
    });

    test('dado un par en la lista, cuando una de las dos queda de baja (la lista sin ella), el par '
        'sale', () async {
      ubicaciones.lista.add([resumen(a), resumen(b)]);
      pares.cambios.add({});
      await asentar();

      ubicaciones.lista.add([resumen(a)]);
      await asentar();

      expect(emisiones.last, isEmpty);
    });

    test('dado que la lista falla, cuando emite el error, el stream sigue y vuelve a emitir con la '
        'lectura siguiente', () async {
      ubicaciones.lista.add([resumen(a), resumen(b)]);
      pares.cambios.add({});
      await asentar();

      ubicaciones.lista.addError(StateError('disco'));
      await asentar();
      pares.cambios.add({});
      await asentar();

      expect(errores, hasLength(1));
      expect(emisiones, hasLength(2));
    });

    test('dado que las decisiones fallan, cuando emite el error, lo pasa', () async {
      pares.cambios.addError(StateError('disco'));
      await asentar();

      expect(errores, hasLength(1));
    });

    test('dado el colportor en blanco, cuando observa, el stream sale con error sin leer nada', () {
      final stream = observar('  ');

      expect(stream, emitsError(isA<StateError>()));
    });

    test(
      'dado que se cancela la suscripción, cuando se corta, cancela la lista y las decisiones',
      () async {
        await suscripcion.cancel();

        expect(ubicaciones.listaCancelada, isTrue);
        expect(pares.cambiosCancelados, isTrue);
      },
    );
  });

  group('ParDecidido.ocultaEn', () {
    final ahora = DateTime.utc(2026, 10, 1, 12);

    test('dado "Son distintos", cuando pasa el tiempo que pase, sigue escondido', () {
      final decidido = ParDecidido(
        decision: DecisionParDuplicado.conservarAmbos,
        decididoEn: ahora.subtract(const Duration(days: 4000)),
      );

      expect(decidido.ocultaEn(ahora), isTrue);
    });

    test('dado "Ignorar", cuando faltan 1 ms para los 30 días sigue escondido y a los 30 días '
        'justos vuelve', () {
      final casi = ParDecidido(
        decision: DecisionParDuplicado.ignorar,
        decididoEn: ahora.subtract(ParDecidido.ventanaIgnorar).add(const Duration(milliseconds: 1)),
      );
      final justo = ParDecidido(
        decision: DecisionParDuplicado.ignorar,
        decididoEn: ahora.subtract(ParDecidido.ventanaIgnorar),
      );

      expect(casi.ocultaEn(ahora), isTrue);
      expect(justo.ocultaEn(ahora), isFalse);
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
      UnirDuplicadosParams unir(String duplicada) =>
          UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: duplicada);

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
      expect(unir('ub-b'), unir('ub-b'));
      expect(unir('ub-b'), isNot(unir('ub-c')));
      expect(
        ParDecidido(decision: DecisionParDuplicado.ignorar, decididoEn: _t0),
        ParDecidido(decision: DecisionParDuplicado.ignorar, decididoEn: _t0),
      );
      expect(
        ParDecidido(decision: DecisionParDuplicado.ignorar, decididoEn: _t0),
        isNot(ParDecidido(decision: DecisionParDuplicado.conservarAmbos, decididoEn: _t0)),
      );
      expect(
        ParaRevisar(par: par(MotivoDuplicado.cercania), espaciosA: 1, espaciosB: 2),
        ParaRevisar(par: par(MotivoDuplicado.cercania), espaciosA: 1, espaciosB: 2),
      );
      expect(
        ParaRevisar(par: par(MotivoDuplicado.cercania), espaciosA: 1, espaciosB: 2),
        isNot(
          ParaRevisar(
            par: par(MotivoDuplicado.cercania),
            espaciosA: 1,
            espaciosB: 2,
            estadoA: EstadoCasa.rechazo,
          ),
        ),
      );
      expect(
        const ResultadoUnionDuplicados(escribio: true, espaciosPasados: 1),
        isNot(const ResultadoUnionDuplicados(escribio: true, espaciosFundidos: 1)),
      );
    });
  });
}
