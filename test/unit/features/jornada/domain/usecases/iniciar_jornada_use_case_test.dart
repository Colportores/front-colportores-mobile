// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/repositories/jornada_repository.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/iniciar_jornada_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

/// Repositorio a mano: registra las llamadas y devuelve lo que el test le indique.
final class _RepositorioFalso implements JornadaRepository {
  Either<Failure, Jornada?> respuestaActiva = const Right(null);
  Either<Failure, Jornada>? respuestaCrear;

  final List<String> consultas = [];
  final List<Jornada> creadas = [];

  @override
  Future<Either<Failure, Jornada?>> obtenerActiva(String colportorId) async {
    consultas.add(colportorId);
    return respuestaActiva;
  }

  @override
  Future<Either<Failure, Jornada>> crear(Jornada jornada) async {
    creadas.add(jornada);
    return respuestaCrear ?? Right(jornada);
  }

  @override
  Future<Either<Failure, Jornada>> finalizar(Jornada jornada) =>
      throw UnimplementedError('no se usa en este caso de uso');
}

void main() {
  // 09:15 en Montevideo (UTC-3) = 12:15 UTC.
  final ahoraLocal = DateTime.parse('2026-09-22T09:15:00-03:00').toLocal();
  final ahoraUtc = DateTime.utc(2026, 9, 22, 12, 15);

  late _RepositorioFalso repositorio;
  late IniciarJornadaUseCase iniciarJornada;

  setUp(() {
    repositorio = _RepositorioFalso();
    iniciarJornada = IniciarJornadaUseCase(
      repositorio,
      generarId: () => 'jor-nueva',
      ahora: () => ahoraLocal,
    );
  });

  Jornada jornadaAbierta() => Jornada(
    id: 'jor-previa',
    colportorId: 'u-1',
    inicio: DateTime.utc(2026, 9, 22, 11),
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 9, 22, 11),
      updatedAt: DateTime.utc(2026, 9, 22, 11),
      createdBy: 'u-1',
    ),
  );

  group('IniciarJornadaUseCase', () {
    test('dado que no tengo jornada activa, cuando inicio jornada, se crea con inicio = now() en '
        'UTC y abierta', () async {
      final resultado = await iniciarJornada(const IniciarJornadaParams(colportorId: 'u-1'));

      final jornada = resultado.getOrElse(() => fail('se esperaba Right, llegó $resultado'));
      expect(jornada.id, 'jor-nueva');
      expect(jornada.colportorId, 'u-1');
      expect(jornada.inicio, ahoraUtc);
      expect(jornada.inicio.isUtc, isTrue);
      expect(jornada.fin, isNull);
      expect(jornada.estaAbierta, isTrue);
      expect(jornada.totalVisitas, 0);
      expect(jornada.totalVentas, 0);
      expect(jornada.acompananteId, isNull);
      expect(jornada.tipoAcompanamiento, isNull);
      expect(repositorio.consultas, ['u-1']);
      expect(repositorio.creadas, [jornada]);
    });

    test('dado que no tengo jornada activa, cuando inicio jornada, la auditoría queda con el '
        'colportor como creador, las fechas del inicio y sync_version 0', () async {
      final resultado = await iniciarJornada(const IniciarJornadaParams(colportorId: 'u-1'));

      final auditoria = resultado.getOrElse(() => fail('se esperaba Right')).auditoria;
      expect(auditoria.createdBy, 'u-1');
      expect(auditoria.createdAt, ahoraUtc);
      expect(auditoria.updatedAt, ahoraUtc);
      expect(auditoria.deletedAt, isNull);
      expect(auditoria.syncVersion, 0);
    });

    test('dado que tengo una jornada activa, cuando intento iniciar otra, devuelve '
        'FailureJornadaActiva y no crea nada', () async {
      repositorio.respuestaActiva = Right(jornadaAbierta());

      final resultado = await iniciarJornada(const IniciarJornadaParams(colportorId: 'u-1'));

      expect(resultado, const Left<Failure, Jornada>(FailureJornadaActiva()));
      expect(repositorio.creadas, isEmpty);
    });

    test('dado el FailureJornadaActiva, cuando la UI lo muestra, el texto es el del criterio de '
        'aceptación de HU-JOR-001', () {
      const failure = FailureJornadaActiva();

      expect(failure.mensaje, 'Tenés una jornada en curso. Cerrala antes de iniciar otra.');
      expect(failure.codigo, 'JOR_JORNADA_ACTIVA');
    });

    test('dado que leer la jornada activa falla, cuando inicio jornada, devuelve ese Failure y '
        'no crea nada', () async {
      repositorio.respuestaActiva = const Left(FailureInesperado(causa: 'db'));

      final resultado = await iniciarJornada(const IniciarJornadaParams(colportorId: 'u-1'));

      expect(resultado, const Left<Failure, Jornada>(FailureInesperado(causa: 'db')));
      expect(repositorio.creadas, isEmpty);
    });

    test('dado que el repositorio rechaza la escritura porque otra jornada se abrió en el medio, '
        'cuando inicio jornada, devuelve FailureJornadaActiva', () async {
      repositorio.respuestaCrear = const Left(FailureJornadaActiva());

      final resultado = await iniciarJornada(const IniciarJornadaParams(colportorId: 'u-1'));

      expect(resultado, const Left<Failure, Jornada>(FailureJornadaActiva()));
      expect(repositorio.creadas, hasLength(1));
    });

    test('dado un colportorId con espacios, cuando inicio jornada, se usa recortado', () async {
      final resultado = await iniciarJornada(const IniciarJornadaParams(colportorId: '  u-1  '));

      expect(resultado.isRight(), isTrue);
      expect(repositorio.consultas, ['u-1']);
      expect(repositorio.creadas.single.colportorId, 'u-1');
      expect(repositorio.creadas.single.auditoria.createdBy, 'u-1');
    });

    test('dado un colportorId vacío, cuando inicio jornada, devuelve FailureValidacion sin tocar '
        'el repositorio', () async {
      final resultado = await iniciarJornada(const IniciarJornadaParams(colportorId: '   '));

      final failure = resultado.fold<Failure>((f) => f, (_) => fail('se esperaba Left'));
      expect(failure, isA<FailureValidacion>());
      expect((failure as FailureValidacion).campos.keys, ['colportorId']);
      expect(repositorio.consultas, isEmpty);
      expect(repositorio.creadas, isEmpty);
    });

    test('dado un reloj con microsegundos, cuando inicio jornada, las fechas quedan truncadas al '
        'milisegundo y en UTC', () async {
      // 09:15:00.123999 en Montevideo (UTC-3): lo que está por debajo del milisegundo no llega a
      // la DB local (epoch ms), así que tampoco puede quedar en la entidad.
      final conMicrosegundos = IniciarJornadaUseCase(
        repositorio,
        generarId: () => 'jor-nueva',
        ahora: () => DateTime.parse('2026-09-22T09:15:00.123999-03:00').toLocal(),
      );
      final esperado = DateTime.utc(2026, 9, 22, 12, 15, 0, 123);

      final resultado = await conMicrosegundos(const IniciarJornadaParams(colportorId: 'u-1'));

      final creada = resultado.getOrElse(() => fail('se esperaba Right'));
      for (final fecha in [creada.inicio, creada.auditoria.createdAt, creada.auditoria.updatedAt]) {
        expect(fecha, esperado);
        expect(fecha.isUtc, isTrue);
        expect(fecha.microsecond, 0);
      }
    });

    test('dado que no se inyecta reloj, cuando inicio jornada, usa la hora actual', () async {
      final sinReloj = IniciarJornadaUseCase(repositorio, generarId: () => 'jor-x');
      // Al milisegundo, como el `inicio` que devuelve el caso de uso: con microsegundos, un
      // `inicio` del mismo milisegundo que `antes` quedaría "antes" de `antes`.
      final antes = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      );

      final resultado = await sinReloj(const IniciarJornadaParams(colportorId: 'u-1'));

      final inicio = resultado.getOrElse(() => fail('se esperaba Right')).inicio;
      expect(inicio.isUtc, isTrue);
      expect(inicio.isBefore(antes), isFalse);
      expect(inicio.isAfter(DateTime.now().toUtc()), isFalse);
    });

    test('dado dos IniciarJornadaParams con el mismo colportor, cuando se comparan, son '
        'iguales', () {
      expect(
        const IniciarJornadaParams(colportorId: 'u-1'),
        const IniciarJornadaParams(colportorId: 'u-1'),
      );
      expect(
        const IniciarJornadaParams(colportorId: 'u-1'),
        isNot(const IniciarJornadaParams(colportorId: 'u-2')),
      );
    });
  });

  group('IniciarJornadaUseCase — hora elegida a mano (hasta 30 min hacia atrás)', () {
    // 12:15:20 UTC: con segundos, para ver que el borde de abajo se compara al minuto.
    final ahora = DateTime.utc(2026, 9, 22, 12, 15, 20);
    late IniciarJornadaUseCase conSegundos;

    setUp(() {
      conSegundos = IniciarJornadaUseCase(
        repositorio,
        generarId: () => 'jor-nueva',
        ahora: () => ahora,
      );
    });

    Future<Either<Failure, Jornada>> iniciarA(DateTime hora) =>
        conSegundos(IniciarJornadaParams(colportorId: 'u-1', hora: hora));

    test('dado que no tengo jornada activa, cuando inicio con una hora de hace 10 minutos, la '
        'jornada empieza a esa hora', () async {
      final hora = DateTime.utc(2026, 9, 22, 12, 5);

      final resultado = await iniciarA(hora.toLocal());

      final jornada = resultado.getOrElse(() => fail('se esperaba Right, llegó $resultado'));
      expect(jornada.inicio, hora);
      expect(jornada.inicio.isUtc, isTrue);
      expect(repositorio.creadas.single.inicio, hora);
    });

    test(
      'dado now = 12:15:20, cuando elijo 11:45:00 (el minuto de now − 30 min), se acepta',
      () async {
        final resultado = await iniciarA(DateTime.utc(2026, 9, 22, 11, 45));

        expect(resultado.isRight(), isTrue);
      },
    );

    test('dado now, cuando elijo exactamente now, se acepta', () async {
      final resultado = await iniciarA(ahora);

      expect(resultado.getOrElse(() => fail('se esperaba Right')).inicio, ahora);
    });

    test('dado now = 12:15:20, cuando elijo 11:44:59 (más de 30 min atrás), se rechaza con el '
        'rango explícito y no se crea nada', () async {
      final resultado = await iniciarA(DateTime.utc(2026, 9, 22, 11, 44, 59));

      final failure = resultado.fold((f) => f, (_) => fail('se esperaba Left'));
      expect(
        failure,
        FailureHoraFueraDeRango(desde: DateTime.utc(2026, 9, 22, 11, 45), hasta: ahora),
      );
      expect(failure.codigo, 'JOR_HORA_FUERA_DE_RANGO');
      expect(repositorio.consultas, isEmpty);
      expect(repositorio.creadas, isEmpty);
    });

    test('dado now, cuando elijo una hora futura, se rechaza: sin horas futuras', () async {
      final resultado = await iniciarA(ahora.add(const Duration(seconds: 1)));

      expect(resultado.fold((f) => f, (_) => null), isA<FailureHoraFueraDeRango>());
      expect(repositorio.creadas, isEmpty);
    });

    test(
      'dado que ya tengo jornada activa, cuando inicio con una hora válida, se bloquea igual',
      () async {
        repositorio.respuestaActiva = Right(jornadaAbierta());

        final resultado = await iniciarA(DateTime.utc(2026, 9, 22, 12, 10));

        expect(resultado, const Left<Failure, Jornada>(FailureJornadaActiva()));
      },
    );

    test('dado un rango de 14:05 a 14:35, el mensaje es "La hora tiene que estar entre las 14:05 '
        'y las 14:35."', () {
      final failure = FailureHoraFueraDeRango(
        desde: DateTime(2026, 9, 23, 14, 5),
        hasta: DateTime(2026, 9, 23, 14, 35, 40),
      );

      expect(failure.mensaje, 'La hora tiene que estar entre las 14:05 y las 14:35.');
    });

    test('dado dos IniciarJornadaParams con distinta hora, cuando se comparan, son distintos', () {
      expect(
        IniciarJornadaParams(colportorId: 'u-1', hora: DateTime.utc(2026)),
        isNot(const IniciarJornadaParams(colportorId: 'u-1')),
      );
    });
  });
}
