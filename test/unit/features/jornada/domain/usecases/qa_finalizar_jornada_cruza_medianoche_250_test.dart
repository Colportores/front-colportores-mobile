// QA del PR #326 (#250): bordes de `FinalizarJornadaUseCase` en la jornada que cruza la medianoche
// que la prueba del implementador no recorre. Dart puro: no importa Flutter, Drift ni Supabase.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/repositories/jornada_repository.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/finalizar_jornada_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _Repositorio implements JornadaRepository {
  _Repositorio(this.activa);

  final Jornada activa;
  final List<Jornada> finalizadas = [];

  @override
  Future<Either<Failure, Jornada?>> obtenerActiva(String colportorId) async => Right(activa);

  @override
  Future<Either<Failure, Jornada>> crear(Jornada jornada) =>
      throw UnimplementedError('no se usa en este caso de uso');

  @override
  Future<Either<Failure, Jornada>> finalizar(Jornada jornada) async {
    finalizadas.add(jornada);
    return Right(jornada);
  }
}

final class _Backup implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

/// Una hora **local** (la zona del dispositivo) del 21/09/2026 (lunes) más [dia] días.
DateTime _local(int dia, int hora, int minuto, [int segundo = 0]) =>
    DateTime(2026, 9, 21 + dia, hora, minuto, segundo);

Jornada _abierta(DateTime inicio) => Jornada(
  id: 'jor-1',
  colportorId: 'u-1',
  inicio: inicio.toUtc(),
  auditoria: Auditoria(createdAt: inicio.toUtc(), updatedAt: inicio.toUtc(), createdBy: 'u-1'),
);

Future<Either<Failure, Jornada>> _finalizar({
  required DateTime inicio,
  required DateTime ahora,
  DateTime? hora,
}) => FinalizarJornadaUseCase(
  _Repositorio(_abierta(inicio)),
  _Backup(),
  ahora: () => ahora.toUtc(),
)(FinalizarJornadaParams(colportorId: 'u-1', hora: hora?.toUtc()));

void main() {
  // Una jornada que empezó el lunes a las 20:00.
  final inicio = _local(0, 20, 0);

  group('El borde entre «cierre normal» y «quedó abierta» (la regla de los 30 minutos)', () {
    test('a las 00:29 todavía cierra normal: con el margen de 30 min el piso es el lunes a las '
        '23:59', () async {
      final r = await _finalizar(inicio: inicio, ahora: _local(1, 0, 29));

      expect(r.fold((f) => f, (_) => null), isNull);
      expect(r.getOrElse(() => fail('se esperaba Right')).fin, _local(1, 0, 29).toUtc());
    });

    test(
      'a las 00:30 ya pide la corrección: ni hace 30 minutos cae en el día del inicio',
      () async {
        final r = await _finalizar(inicio: inicio, ahora: _local(1, 0, 30));

        expect(r.fold((f) => f, (_) => null), isA<FailureJornadaDeDiaAnterior>());
      },
    );

    test(
      'con el reloj en 00:30:45 también pide la corrección (el piso se mira al minuto)',
      () async {
        final r = await _finalizar(inicio: inicio, ahora: _local(1, 0, 30, 45));

        expect(r.fold((f) => f, (_) => null), isA<FailureJornadaDeDiaAnterior>());
      },
    );
  });

  group('Una hora elegida antes de que «quede abierta»', () {
    test('elegida a las 00:20 (cierre normal) y tocada a las 00:35: la rama de corrección la '
        'acepta tal cual, no la rechaza por estar a más de 30 minutos', () async {
      final r = await _finalizar(inicio: inicio, ahora: _local(1, 0, 35), hora: _local(1, 0, 20));

      expect(r.getOrElse(() => fail('se esperaba Right')).fin, _local(1, 0, 20).toUtc());
    });

    test(
      'la hora elegida de ayer a las 23:50 con el reloj en 00:35 también cierra a esa hora',
      () async {
        final r = await _finalizar(
          inicio: inicio,
          ahora: _local(1, 0, 35),
          hora: _local(0, 23, 50),
        );

        expect(r.getOrElse(() => fail('se esperaba Right')).fin, _local(0, 23, 50).toUtc());
      },
    );
  });

  group('Los extremos del rango de la corrección', () {
    final ahora = _local(1, 9, 0);

    test('el inicio exacto no vale (el fin tiene que ser posterior)', () async {
      final r = await _finalizar(inicio: inicio, ahora: ahora, hora: inicio);

      expect(r.fold((f) => f, (_) => null), isA<FailureHoraFueraDeRango>());
    });

    test('un minuto después del inicio vale', () async {
      final r = await _finalizar(inicio: inicio, ahora: ahora, hora: _local(0, 20, 1));

      expect(r.getOrElse(() => fail('se esperaba Right')).fin, _local(0, 20, 1).toUtc());
    });

    test(
      'las 08:00 (12 h exactas) valen y las 08:01 no, y el aviso nombra el rango real',
      () async {
        final justo = await _finalizar(inicio: inicio, ahora: ahora, hora: _local(1, 8, 0));
        expect(justo.fold((f) => f, (_) => null), isNull);

        final pasado = await _finalizar(inicio: inicio, ahora: ahora, hora: _local(1, 8, 1));
        final falla = pasado.fold((f) => f, (_) => null);
        expect(falla, isA<FailureHoraFueraDeRango>());
        expect(falla!.mensaje, 'La hora tiene que estar entre las 20:01 y las 08:00.');
      },
    );

    test('con un inicio con segundos (20:00:30) las 20:00 no valen y las 20:01 sí', () async {
      final conSegundos = _local(0, 20, 0, 30);

      final antes = await _finalizar(inicio: conSegundos, ahora: ahora, hora: _local(0, 20, 0));
      expect(antes.fold((f) => f, (_) => null), isA<FailureHoraFueraDeRango>());

      final despues = await _finalizar(inicio: conSegundos, ahora: ahora, hora: _local(0, 20, 1));
      expect(despues.fold((f) => f, (_) => null), isNull);
    });

    test(
      'nunca una hora futura: con el reloj a las 07:00 (menos de 12 h) la de las 07:01 se rechaza',
      () async {
        // Inicio del domingo a las 20:00; ahora es el lunes a las 07:00.
        final inicioAnterior = _local(-1, 20, 0);

        final r = await _finalizar(
          inicio: inicioAnterior,
          ahora: _local(0, 7, 0),
          hora: _local(0, 7, 1),
        );

        final falla = r.fold((f) => f, (_) => null);
        expect(falla, isA<FailureHoraFueraDeRango>());
        expect(falla!.mensaje, 'La hora tiene que estar entre las 20:01 y las 07:00.');
      },
    );
  });

  test(
    'privacidad: el mensaje de la jornada sin cerrar nombra el día, no a la persona ni su id',
    () {
      final f = FailureJornadaDeDiaAnterior(inicio: inicio);

      expect(f.mensaje, contains('Tenés una jornada del lunes 21 sin cerrar.'));
      expect(f.toString(), isNot(contains('u-1')));
      expect(f.mensaje, isNot(contains('u-1')));
    },
  );
}
