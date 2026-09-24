// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'dart:async';

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

  /// Si no es `null`, el pedido no vuelve hasta que el test lo complete.
  Completer<void>? demora;

  @override
  Future<void> solicitar(String colportorId) async {
    pedidos.add(colportorId);
    await demora?.future;
    if (error case final e?) throw e;
  }
}

/// Una hora del miércoles 23/09/2026 **en la zona del dispositivo**, como instante UTC (como la
/// devuelve el caso de uso). Así los tests no dependen del huso horario de quien los corre: la
/// guarda de "día anterior" mira el día local.
DateTime _hoy(int hora, int minuto, [int segundo = 0, int ms = 0, int us = 0]) =>
    DateTime(2026, 9, 23, hora, minuto, segundo, ms, us).toUtc();

void main() {
  // 14:35:20 hora local; la jornada empezó a las 13:15.
  final ahora = _hoy(14, 35, 20);
  final inicio = _hoy(13, 15);

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
      final conMicros = _hoy(14, 35, 20, 123, 999);
      final caso = FinalizarJornadaUseCase(repositorio, backup, ahora: () => conMicros.toLocal());

      final cerrada = (await caso(
        const FinalizarJornadaParams(colportorId: 'u-1'),
      )).getOrElse(() => fail('se esperaba Right'));

      expect(cerrada.fin, _hoy(14, 35, 20, 123));
      expect(cerrada.fin!.isUtc, isTrue);
    });

    test('con una hora elegida dentro de [max(now − 30 min, inicio), now], la jornada termina a '
        'esa hora (el borde de abajo se compara al minuto)', () async {
      for (final hora in [_hoy(14, 5), _hoy(14, 30)]) {
        final resultado = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: hora),
        );
        expect(resultado.getOrElse(() => fail('se esperaba Right')).fin, hora);
      }
    });

    test('con una hora de más de 30 minutos atrás, en el futuro o anterior al inicio, rechaza con '
        'el rango explícito y no guarda nada', () async {
      repositorio.respuestaActiva = Right(abierta(desde: _hoy(14, 20)));

      for (final hora in [_hoy(14, 4, 59), _hoy(14, 36), _hoy(14, 19)]) {
        final resultado = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: hora),
        );
        expect(
          resultado,
          Left<Failure, Jornada>(FailureHoraFueraDeRango(desde: _hoy(14, 20), hasta: ahora)),
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

    test('si pedir el backup falla, la jornada igual queda cerrada y la falla se informa para el '
        'log (#102)', () async {
      final fallas = <Object>[];
      final caso = FinalizarJornadaUseCase(
        repositorio,
        backup..error = StateError('sin motor de backup'),
        ahora: () => ahora,
        alFallarBackup: (error, _) => fallas.add(error),
      );

      final resultado = await caso(const FinalizarJornadaParams(colportorId: 'u-1'));
      await Future<void>.delayed(Duration.zero);

      expect(resultado.isRight(), isTrue);
      expect(repositorio.finalizadas, hasLength(1));
      expect(fallas.single, isA<StateError>());
    });

    test(
      'no espera al backup para devolver el cierre: la pantalla no queda colgada (#102)',
      () async {
        backup.demora = Completer<void>();

        final resultado = await finalizarJornada(
          const FinalizarJornadaParams(colportorId: 'u-1'),
        ).timeout(const Duration(seconds: 1));

        expect(resultado.isRight(), isTrue);
        expect(backup.pedidos, ['u-1'], reason: 'el backup se pidió igual');
        backup.demora!.complete();
      },
    );

    test('dada una jornada que empezó hace más de 30 minutos, una hora anterior a now − 30 se '
        'rechaza por el borde de 30 min, no por el del inicio (#102)', () async {
      // Inicio 13:15: el piso del rango es now − 30 = 14:05 (al minuto), no el inicio.
      final resultado = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: _hoy(14, 4, 59)),
      );

      expect(
        resultado,
        Left<Failure, Jornada>(FailureHoraFueraDeRango(desde: _hoy(14, 5), hasta: ahora)),
      );
      expect(repositorio.finalizadas, isEmpty);
    });
  });

  group('Jornada que quedó abierta de un día anterior (HU-JOR-002, #102)', () {
    // En la zona del dispositivo: el día del colportor, no el de UTC.
    final ahoraLocal = DateTime(2026, 9, 23, 8);

    setUp(() {
      finalizarJornada = FinalizarJornadaUseCase(repositorio, backup, ahora: () => ahoraLocal);
    });

    test('dado que empezó ayer, no la cierra con la hora de hoy (nunca se inventa un fin) y dice '
        'de qué día es', () async {
      final ayer = DateTime(2026, 9, 22, 18);
      repositorio.respuestaActiva = Right(abierta(desde: ayer));

      final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

      final failure = resultado.fold((f) => f, (_) => fail('se esperaba Left'));
      expect(failure, FailureJornadaDeDiaAnterior(inicio: ayer.toUtc()));
      expect(failure.mensaje, startsWith('Tenés una jornada del martes 22 sin cerrar.'));
      expect(failure.mensaje, contains('hay que indicar a qué hora terminaste ese día'));
      expect(repositorio.finalizadas, isEmpty);
      expect(backup.pedidos, isEmpty);
    });

    test('tampoco con una hora elegida a mano', () async {
      repositorio.respuestaActiva = Right(abierta(desde: DateTime(2026, 9, 22, 23, 50)));

      final resultado = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 7, 50)),
      );

      expect(resultado.fold((f) => f, (_) => null), isA<FailureJornadaDeDiaAnterior>());
      expect(repositorio.finalizadas, isEmpty);
    });

    test('a las 00:10, elegir las 23:50 de ayer vale: está dentro de los 30 minutos y del día del '
        'inicio (revisión de #107)', () async {
      final medianoche = FinalizarJornadaUseCase(
        repositorio,
        backup,
        ahora: () => DateTime(2026, 9, 23, 0, 10),
      );
      repositorio.respuestaActiva = Right(abierta(desde: DateTime(2026, 9, 22, 20)));

      final resultado = await medianoche(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 22, 23, 50)),
      );

      expect(
        resultado.getOrElse(() => fail('se esperaba Right')).fin,
        DateTime(2026, 9, 22, 23, 50).toUtc(),
      );
    });

    test(
      'a las 00:10, elegir las 00:05 de hoy no vale: la jornada cruzaría la medianoche',
      () async {
        final medianoche = FinalizarJornadaUseCase(
          repositorio,
          backup,
          ahora: () => DateTime(2026, 9, 23, 0, 10),
        );
        repositorio.respuestaActiva = Right(abierta(desde: DateTime(2026, 9, 22, 20)));

        final sinElegir = await medianoche(const FinalizarJornadaParams(colportorId: 'u-1'));
        final hoy = await medianoche(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 0, 5)),
        );

        expect(sinElegir.fold((f) => f, (_) => null), isA<FailureJornadaDeDiaAnterior>());
        expect(hoy.fold((f) => f, (_) => null), isA<FailureJornadaDeDiaAnterior>());
        expect(repositorio.finalizadas, isEmpty);
      },
    );

    test('dado que empezó hoy temprano, la cierra normalmente', () async {
      repositorio.respuestaActiva = Right(abierta(desde: DateTime(2026, 9, 23, 0, 5)));

      final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

      expect(resultado.isRight(), isTrue);
      expect(repositorio.finalizadas, hasLength(1));
    });
  });
}
