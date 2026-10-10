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

  /// La jornada siguiente a la abierta (HU-JOR-002): `null` = no hay ninguna.
  Either<Failure, Jornada?> respuestaSiguiente = const Right(null);

  final List<Jornada> finalizadas = [];
  final List<Jornada> consultasSiguiente = [];

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

  @override
  Future<Either<Failure, Jornada?>> siguienteA(Jornada jornada) async {
    consultasSiguiente.add(jornada);
    return respuestaSiguiente;
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

/// Una jornada ya cerrada que empezó en [inicio]: la que sigue a la que quedó abierta.
Jornada _cerrada(DateTime inicio) => Jornada(
  id: 'jor-2',
  colportorId: 'u-1',
  inicio: inicio.toUtc(),
  fin: inicio.toUtc().add(const Duration(hours: 2)),
  auditoria: Auditoria(createdAt: inicio.toUtc(), updatedAt: inicio.toUtc(), createdBy: 'u-1'),
);

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
      expect(
        failure.mensaje,
        'Tu jornada del martes 22 empezó a las 18:00 y quedó abierta. Cerrala para empezar la de '
        'hoy.',
      );
      expect(repositorio.finalizadas, isEmpty);
      expect(backup.pedidos, isEmpty);
    });

    test('el aviso lleva el día entero y la hora de inicio con ceros, y se compara con el '
        'inicio de la siguiente', () {
      // Domingo 6/9/2026 a las 05:05, en la zona del dispositivo.
      final inicio = DateTime(2026, 9, 6, 5, 5);
      final siguiente = DateTime(2026, 9, 6, 9);

      final failure = FailureJornadaDeDiaAnterior(
        inicio: inicio.toUtc(),
        inicioSiguiente: siguiente.toUtc(),
      );

      expect(
        failure.mensaje,
        'Tu jornada del domingo 6 empezó a las 05:05 y quedó abierta. Cerrala para empezar la de '
        'hoy.',
      );
      expect(failure.inicioSiguiente, siguiente.toUtc());
      expect(
        failure,
        FailureJornadaDeDiaAnterior(inicio: inicio.toUtc(), inicioSiguiente: siguiente.toUtc()),
      );
      expect(failure, isNot(FailureJornadaDeDiaAnterior(inicio: inicio.toUtc())));
    });

    test('dado que hay una jornada siguiente, el aviso la informa para que la pantalla ofrezca el '
        'mismo tope', () async {
      final inicioAyer = DateTime(2026, 9, 22, 22);
      final inicioSiguiente = DateTime(2026, 9, 23, 6);
      repositorio
        ..respuestaActiva = Right(abierta(desde: inicioAyer))
        ..respuestaSiguiente = Right(_cerrada(inicioSiguiente));

      final resultado = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

      final failure = resultado.fold((f) => f, (_) => fail('se esperaba Left'));
      expect(
        failure,
        FailureJornadaDeDiaAnterior(
          inicio: inicioAyer.toUtc(),
          inicioSiguiente: inicioSiguiente.toUtc(),
        ),
      );
      expect(repositorio.consultasSiguiente.single.id, 'jor-1');
      expect(repositorio.finalizadas, isEmpty);
    });

    test('con una hora elegida, el fin no pisa a la jornada siguiente: las 06:00 valen y las '
        '06:01 no, aunque las 12 h dejarían hasta las 08:00', () async {
      final inicioAyer = DateTime(2026, 9, 22, 20);
      repositorio
        ..respuestaActiva = Right(abierta(desde: inicioAyer))
        ..respuestaSiguiente = Right(_cerrada(DateTime(2026, 9, 23, 6)));

      final pasado = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 6, 1)),
      );

      final falla = pasado.fold((f) => f, (_) => fail('se esperaba Left'));
      expect(falla, isA<FailureHoraFueraDeRango>());
      expect(falla.mensaje, 'La hora tiene que estar entre las 20:01 y las 06:00.');
      expect(repositorio.finalizadas, isEmpty);
      expect(backup.pedidos, isEmpty);

      final justo = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 6)),
      );
      expect(
        justo.getOrElse(() => fail('se esperaba Right')).fin,
        DateTime(2026, 9, 23, 6).toUtc(),
      );
      expect(repositorio.finalizadas, hasLength(1));
    });

    test('la jornada siguiente topa el fin aunque esté abierta: es la misma regla', () async {
      final inicioAyer = DateTime(2026, 9, 22, 20);
      repositorio
        ..respuestaActiva = Right(abierta(desde: inicioAyer))
        ..respuestaSiguiente = Right(abierta(desde: DateTime(2026, 9, 23, 3)));

      final r = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 4)),
      );

      expect(r.fold((f) => f, (_) => null), isA<FailureHoraFueraDeRango>());
      expect(repositorio.finalizadas, isEmpty);
    });

    test('sin jornada siguiente, el tope sigue siendo el de las 12 h (o ahora)', () async {
      final inicioAyer = DateTime(2026, 9, 22, 20);
      repositorio.respuestaActiva = Right(abierta(desde: inicioAyer));

      final r = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 7)),
      );

      expect(r.getOrElse(() => fail('se esperaba Right')).fin, DateTime(2026, 9, 23, 7).toUtc());
    });

    test('si no se puede leer la jornada siguiente, devuelve esa falla y no guarda nada: no se '
        'ofrece ni se acepta una hora sin saber si pisa a la que sigue', () async {
      repositorio
        ..respuestaActiva = Right(abierta(desde: DateTime(2026, 9, 22, 20)))
        ..respuestaSiguiente = const Left(FailureInesperado(causa: 'disco'));

      final sinHora = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));
      final conHora = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 6)),
      );

      expect(sinHora.fold((f) => f, (_) => null), isA<FailureInesperado>());
      expect(conHora.fold((f) => f, (_) => null), isA<FailureInesperado>());
      expect(repositorio.finalizadas, isEmpty);
    });

    test('un cierre normal (la jornada de hoy) no consulta la siguiente', () async {
      finalizarJornada = FinalizarJornadaUseCase(repositorio, backup, ahora: () => ahora);

      await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));

      expect(repositorio.consultasSiguiente, isEmpty);
    });

    test(
      'una hora de la mañana siguiente es válida: la jornada cruza la medianoche y la corrección '
      'la acepta mientras no pase de 12 h después del inicio (#250)',
      () async {
        final inicioAyer = DateTime(2026, 9, 22, 23, 50);
        repositorio.respuestaActiva = Right(abierta(desde: inicioAyer));

        final resultado = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 7, 50)),
        );

        final cerrada = resultado.getOrElse(() => fail('se esperaba Right'));
        expect(cerrada.fin, DateTime(2026, 9, 23, 7, 50).toUtc());
        expect(cerrada.duracion, const Duration(hours: 8));
        expect(repositorio.finalizadas, hasLength(1));
      },
    );

    test('reproduce el bug #118: una hora de HOY que el selector normal de "Hora de fin" ofrecía '
        'para una jornada de ayer (antes del fix de `JornadaPage._maximoAtrasFin`) está más de 12 h '
        'después del inicio: rechaza con el rango real, sin cerrar', () async {
      final ahoraDeHoy = FinalizarJornadaUseCase(
        repositorio,
        backup,
        ahora: () => DateTime(2026, 9, 23, 10),
      );
      final inicioAyer = DateTime(2026, 9, 22, 18);
      repositorio.respuestaActiva = Right(abierta(desde: inicioAyer));

      // Repro exacta del revisor: inicio 22/09 18:00, ahora 23/09 10:00, "hace 15 min" (09:45 de
      // HOY, no de ayer). Con el tope de 12 h (#250) el último minuto válido son las 06:00.
      final resultado = await ahoraDeHoy(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 9, 45)),
      );

      final failure = resultado.fold((f) => f, (_) => fail('se esperaba Left'));
      expect(
        failure,
        FailureHoraFueraDeRango(
          desde: DateTime(2026, 9, 22, 18, 1).toUtc(),
          hasta: DateTime(2026, 9, 23, 6).toUtc(),
        ),
      );
      expect(failure.mensaje, 'La hora tiene que estar entre las 18:01 y las 06:00.');
      expect(repositorio.finalizadas, isEmpty);
    });

    test('la corrección de "jornada que quedó abierta" cierra con la hora elegida, entre el inicio '
        'y 12 h después, sin el margen de 30 min (#109)', () async {
      final inicioAyer = DateTime(2026, 9, 22, 13);
      repositorio.respuestaActiva = Right(abierta(desde: inicioAyer));

      final resultado = await finalizarJornada(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 22, 22, 30)),
      );

      final cerrada = resultado.getOrElse(() => fail('se esperaba Right'));
      expect(cerrada.fin, DateTime(2026, 9, 22, 22, 30).toUtc());
      expect(repositorio.finalizadas, hasLength(1));
      expect(backup.pedidos, ['u-1'], reason: 'el backup se pide igual que en el cierre normal');
    });

    test(
      'la corrección rechaza una hora que no es posterior al inicio (nunca se inventa un fin)',
      () async {
        final inicioAyer = DateTime(2026, 9, 22, 13);
        repositorio.respuestaActiva = Right(abierta(desde: inicioAyer));

        final igualAlInicio = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: inicioAyer),
        );
        final antesDelInicio = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 22, 12, 59)),
        );

        expect(igualAlInicio.fold((f) => f, (_) => null), isA<FailureHoraFueraDeRango>());
        expect(antesDelInicio.fold((f) => f, (_) => null), isA<FailureHoraFueraDeRango>());
        expect(repositorio.finalizadas, isEmpty);
      },
    );

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

    test('a las 00:10, con el margen de 30 min todavía en el día del inicio, cerrar con la hora '
        'del toque o con las 00:05 de hoy vale: el fin cruza la medianoche (#250)', () async {
      final medianoche = FinalizarJornadaUseCase(
        repositorio,
        backup,
        ahora: () => DateTime(2026, 9, 23, 0, 10),
      );
      repositorio.respuestaActiva = Right(abierta(desde: DateTime(2026, 9, 22, 20)));

      final sinElegir = await medianoche(const FinalizarJornadaParams(colportorId: 'u-1'));
      repositorio.finalizadas.clear();
      final hoy = await medianoche(
        FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 0, 5)),
      );

      expect(
        sinElegir.getOrElse(() => fail('se esperaba Right')).fin,
        DateTime(2026, 9, 23, 0, 10).toUtc(),
      );
      expect(
        hoy.getOrElse(() => fail('se esperaba Right')).fin,
        DateTime(2026, 9, 23, 0, 5).toUtc(),
      );
    });

    group('jornada iniciada a las 23:59 (la trampa de #250)', () {
      final inicioTarde = DateTime(2026, 9, 22, 23, 59);

      setUp(() => repositorio.respuestaActiva = Right(abierta(desde: inicioTarde)));

      test('a las 00:05, cierra con la hora del toque o con las 00:03: ya no hay que adivinar una '
          'hora que no existe', () async {
        final medianoche = FinalizarJornadaUseCase(
          repositorio,
          backup,
          ahora: () => DateTime(2026, 9, 23, 0, 5),
        );

        final sinElegir = await medianoche(const FinalizarJornadaParams(colportorId: 'u-1'));
        final elegida = await medianoche(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 0, 3)),
        );

        expect(
          sinElegir.getOrElse(() => fail('se esperaba Right')).fin,
          DateTime(2026, 9, 23, 0, 5).toUtc(),
        );
        expect(
          elegida.getOrElse(() => fail('se esperaba Right')).fin,
          DateTime(2026, 9, 23, 0, 3).toUtc(),
        );
      });

      test('a la mañana, sin hora pide la corrección y con una hora del día siguiente la cierra '
          'a esa hora (nunca se inventa un fin)', () async {
        final sinElegir = await finalizarJornada(const FinalizarJornadaParams(colportorId: 'u-1'));
        expect(sinElegir.fold((f) => f, (_) => null), isA<FailureJornadaDeDiaAnterior>());
        expect(repositorio.finalizadas, isEmpty);

        final elegida = await finalizarJornada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 0, 30)),
        );

        final cerrada = elegida.getOrElse(() => fail('se esperaba Right'));
        expect(cerrada.fin, DateTime(2026, 9, 23, 0, 30).toUtc());
        expect(cerrada.duracion, const Duration(minutes: 31));
        expect(backup.pedidos, ['u-1']);
      });

      test('el tope son 12 h exactas después del inicio: las 11:59 valen, las 12:00 no', () async {
        final tarde = FinalizarJornadaUseCase(
          repositorio,
          backup,
          ahora: () => DateTime(2026, 9, 23, 15),
        );

        final enElTope = await tarde(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 11, 59)),
        );
        expect(
          enElTope.getOrElse(() => fail('se esperaba Right')).fin,
          DateTime(2026, 9, 23, 11, 59).toUtc(),
        );

        repositorio.finalizadas.clear();
        final pasado = await tarde(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 12)),
        );
        expect(
          pasado.fold((f) => f, (_) => null),
          FailureHoraFueraDeRango(
            desde: DateTime(2026, 9, 23).toUtc(),
            hasta: DateTime(2026, 9, 23, 11, 59).toUtc(),
          ),
        );
        expect(repositorio.finalizadas, isEmpty);
      });
    });

    test(
      'sin horas futuras: si pasaron menos de 12 h desde el inicio, el tope es ahora (#250)',
      () async {
        final inicioAyer = DateTime(2026, 9, 22, 22);
        repositorio.respuestaActiva = Right(abierta(desde: inicioAyer));
        // 23/09 01:00: el margen de 30 min ya cae en otro día, así que es una corrección.
        final unaDeLaMadrugada = FinalizarJornadaUseCase(
          repositorio,
          backup,
          ahora: () => DateTime(2026, 9, 23, 1),
        );

        final futura = await unaDeLaMadrugada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 1, 30)),
        );
        final valida = await unaDeLaMadrugada(
          FinalizarJornadaParams(colportorId: 'u-1', hora: DateTime(2026, 9, 23, 0, 45)),
        );

        expect(
          futura.fold((f) => f, (_) => null),
          FailureHoraFueraDeRango(
            desde: DateTime(2026, 9, 22, 22, 1).toUtc(),
            hasta: DateTime(2026, 9, 23, 1).toUtc(),
          ),
        );
        expect(
          valida.getOrElse(() => fail('se esperaba Right')).fin,
          DateTime(2026, 9, 23, 0, 45).toUtc(),
        );
        expect(repositorio.finalizadas, hasLength(1));
      },
    );

    test(
      'si el reloj del teléfono quedó antes del inicio, no cierra: dice qué revisar (#250)',
      () async {
        final inicioAyer = DateTime(2026, 9, 22, 18);
        repositorio.respuestaActiva = Right(abierta(desde: inicioAyer));
        final atrasado = FinalizarJornadaUseCase(
          repositorio,
          backup,
          ahora: () => DateTime(2026, 9, 22, 17),
        );

        final resultado = await atrasado(const FinalizarJornadaParams(colportorId: 'u-1'));

        expect(resultado.fold((f) => f, (_) => null), isA<FailureValidacion>());
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
