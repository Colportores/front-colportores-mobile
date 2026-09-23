// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/repositories/jornada_repository.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/finalizar_jornada_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

/// Repositorio a mano: registra las llamadas y devuelve lo que el test le indique.
final class _RepositorioFalso implements JornadaRepository {
  Either<Failure, Jornada?> respuestaActiva = const Right(null);
  Either<Failure, Jornada>? respuestaFinalizar;

  final List<Jornada> finalizadas = [];

  @override
  Future<Either<Failure, Jornada?>> obtenerActiva(String colportorId) async => respuestaActiva;

  @override
  Future<Either<Failure, Jornada>> crear(Jornada jornada) =>
      throw UnimplementedError('no se usa en este caso de uso');

  @override
  Future<Either<Failure, Jornada>> finalizar(Jornada jornada) async {
    finalizadas.add(jornada);
    return respuestaFinalizar ?? Right(jornada);
  }
}

final class _BackupFalso implements DisparadorBackup {
  final List<String> pedidos = [];
  Object? error;

  @override
  Future<void> solicitar(String colportorId) async {
    pedidos.add(colportorId);
    if (error case final e?) throw e;
  }
}

void main() {
  // 14:35:20 UTC; la jornada empezó a las 13:15 UTC.
  final ahora = DateTime.utc(2026, 9, 23, 14, 35, 20);
  final inicio = DateTime.utc(2026, 9, 23, 13, 15);

  late _RepositorioFalso repositorio;
  late _BackupFalso backup;
  late FinalizarJornadaUseCase finalizarJornada;

  Jornada abierta({DateTime? desde}) => Jornada(
    id: 'jor-1',
    colportorId: 'u-1',
    inicio: desde ?? inicio,
    totalVisitas: 3,
    auditoria: Auditoria(createdAt: inicio, updatedAt: inicio, createdBy: 'u-1'),
  );

  setUp(() {
    repositorio = _RepositorioFalso()..respuestaActiva = Right(abierta());
    backup = _BackupFalso();
    finalizarJornada = FinalizarJornadaUseCase(repositorio, backup, ahora: () => ahora);
  });

  group('FinalizarJornadaUseCase — HU-JOR-002', () {
    test('Escenario: Fin de jornada con backup — Dado que tengo jornada activa con Wi-Fi '
        'disponible, Cuando finalizo, Entonces `hora_fin = now()` Y se dispara backup nocturno Y '
        'se muestra resumen', () async {
      final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

      final cerrada = resultado.getOrElse(() => fail('se esperaba Right'));
      expect(cerrada.fin, ahora);
      expect(cerrada.duracion, const Duration(hours: 1, minutes: 20, seconds: 20));
      expect(backup.pedidos, ['u-1']);
      // El cierre solo toca fin y updated_at.
      final guardada = repositorio.finalizadas.single;
      expect(guardada.id, 'jor-1');
      expect(guardada.inicio, inicio);
      expect(guardada.totalVisitas, 3);
      expect(guardada.auditoria.createdAt, inicio);
      expect(guardada.auditoria.updatedAt, ahora);
    });

    test('la hora del toque se trunca al milisegundo y queda en UTC', () async {
      final conMicros = DateTime.utc(2026, 9, 23, 14, 35, 20, 123, 999);
      final caso = FinalizarJornadaUseCase(repositorio, backup, ahora: () => conMicros.toLocal());

      final cerrada = (await caso(
        const FinalizarJornadaParams(colportorId: 'u-1'),
      )).getOrElse(() => fail('se esperaba Right'));

      expect(cerrada.fin, DateTime.utc(2026, 9, 23, 14, 35, 20, 123));
      expect(cerrada.fin!.isUtc, isTrue);
    });

    test('con una hora elegida dentro de [max(now − 30 min, inicio), now], la jornada termina a '
        'esa hora (el borde de abajo se compara al minuto)', () async {
      for (final hora in [DateTime.utc(2026, 9, 23, 14, 5), DateTime.utc(2026, 9, 23, 14, 30)]) {
        final resultado = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: hora),
        );
        expect(resultado.getOrElse(() => fail('se esperaba Right')).fin, hora);
      }
    });

    test('con una hora de más de 30 minutos atrás, en el futuro o anterior al inicio, rechaza con '
        'el rango explícito y no guarda nada', () async {
      repositorio.respuestaActiva = Right(abierta(desde: DateTime.utc(2026, 9, 23, 14, 20)));

      for (final hora in [
        DateTime.utc(2026, 9, 23, 14, 4, 59),
        DateTime.utc(2026, 9, 23, 14, 36),
        DateTime.utc(2026, 9, 23, 14, 19),
      ]) {
        final resultado = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: hora),
        );
        expect(
          resultado,
          Left<Failure, Jornada>(
            FailureHoraFueraDeRango(desde: DateTime.utc(2026, 9, 23, 14, 20), hasta: ahora),
          ),
        );
      }
      expect(repositorio.finalizadas, isEmpty);
      expect(backup.pedidos, isEmpty);
    });

    test('sin jornada activa devuelve FailureSinJornadaActiva y no pide backup', () async {
      repositorio.respuestaActiva = const Right(null);

      final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

      expect(resultado, const Left<Failure, Jornada>(FailureSinJornadaActiva()));
      expect(repositorio.finalizadas, isEmpty);
      expect(backup.pedidos, isEmpty);
    });

    test(
      'si el reloj del teléfono quedó antes del inicio, rechaza con qué pasó y qué hacer',
      () async {
        repositorio.respuestaActiva = Right(abierta(desde: ahora.add(const Duration(hours: 1))));

        final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

        final failure = resultado.fold((f) => f, (_) => fail('se esperaba Left'));
        expect(failure, isA<FailureValidacion>());
        expect(failure.mensaje, contains('Revisá la fecha y hora del teléfono'));
        expect(repositorio.finalizadas, isEmpty);
      },
    );

    test('sin colportor devuelve FailureValidacion sin tocar el repositorio', () async {
      final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: '  '));

      expect(resultado.fold((f) => f, (_) => null), isA<FailureValidacion>());
      expect(repositorio.finalizadas, isEmpty);
    });

    test('si leer o guardar falla, devuelve ese Failure y no pide backup', () async {
      repositorio.respuestaFinalizar = const Left(FailureInesperado());
      expect(
        await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1')),
        const Left<Failure, Jornada>(FailureInesperado()),
      );

      repositorio.respuestaActiva = const Left(FailureInesperado());
      expect(
        await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1')),
        const Left<Failure, Jornada>(FailureInesperado()),
      );
      expect(backup.pedidos, isEmpty);
    });

    test('si pedir el backup falla, la jornada igual queda cerrada', () async {
      backup.error = StateError('sin motor de backup');

      final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

      expect(resultado.isRight(), isTrue);
      expect(repositorio.finalizadas, hasLength(1));
    });
  });
}
