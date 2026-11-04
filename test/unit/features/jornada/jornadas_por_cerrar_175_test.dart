// HU-JOR-002, «Jornada que quedó abierta» + HU-SYNC-006 (#175, regla de #327): al terminar la
// recuperación de dispositivo puede haber más de una jornada abierta. Cada una que tiene otra después
// se cierra con la hora que elige la persona y con el inicio de la siguiente como tope; ninguna se
// cierra sola ni con la hora de ahora.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/jornada_repository_impl.dart';
import 'package:colportores_mobile/features/jornada/data/repositories/jornadas_abiertas_repository_impl.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/finalizar_jornada_anterior_use_case.dart';
import 'package:colportores_mobile/features/jornada/domain/usecases/jornadas_por_cerrar_use_case.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

final class _BackupContado implements DisparadorBackup {
  int pedidos = 0;
  Object? error;

  @override
  Future<void> solicitar(String colportorId) async {
    pedidos++;
    if (error case final e?) throw e;
  }
}

DateTime _hoy(int h, [int m = 0]) => DateTime(2026, 10, 22, h, m);

JornadaModel _jornada(
  String id,
  DateTime inicio, {
  String colportor = 'u-1',
  DateTime? fin,
  DateTime? borrada,
}) => JornadaModel.fromEntity(
  Jornada(
    id: id,
    colportorId: colportor,
    inicio: inicio,
    fin: fin,
    auditoria: Auditoria(
      createdAt: inicio,
      updatedAt: inicio,
      createdBy: colportor,
      deletedAt: borrada,
    ),
  ),
);

void main() {
  late JornadaLocalDataSourceEnMemoria local;
  late JornadaRepositoryImpl jornadas;
  late JornadasAbiertasRepositoryImpl abiertas;
  late _BackupContado backup;
  late DateTime ahora;
  late List<Object> fallasDeBackup;

  void armar(Iterable<JornadaModel> iniciales) {
    local = JornadaLocalDataSourceEnMemoria(iniciales: iniciales);
    jornadas = JornadaRepositoryImpl(local, logger: loggerMudo());
    abiertas = JornadasAbiertasRepositoryImpl(local, logger: loggerMudo());
    backup = _BackupContado();
    ahora = _hoy(18);
    fallasDeBackup = [];
  }

  JornadasPorCerrarUseCase porCerrar() => JornadasPorCerrarUseCase(abiertas, jornadas);

  FinalizarJornadaAnteriorUseCase finalizar() => FinalizarJornadaAnteriorUseCase(
    abiertas,
    jornadas,
    backup,
    ahora: () => ahora,
    alFallarBackup: (error, rastro) => fallasDeBackup.add(error),
  );

  Future<List<JornadaPorCerrar>> lista([String colportor = 'u-1']) async => (await porCerrar()(
    JornadasPorCerrarParams(colportorId: colportor),
  )).fold((f) => fail('no debería fallar: ${f.mensaje}'), (l) => l);

  Failure? falla(Either<Failure, Object?> resultado) => resultado.fold((f) => f, (_) => null);

  group('JornadasPorCerrarUseCase', () {
    test('dos abiertas el mismo día: la de las 08:00 va con el tope de las 09:00; la última es la '
        'jornada en curso y no se pregunta', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      final por = await lista();

      expect(por, hasLength(1));
      expect(por.single.jornada.id, 'a');
      expect(por.single.inicioSiguiente.toLocal(), _hoy(9));
    });

    test('tres abiertas: las dos primeras, la más vieja primero, cada una con su tope', () async {
      armar([_jornada('c', _hoy(10)), _jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      final por = await lista();

      expect(por.map((p) => p.jornada.id), ['a', 'b']);
      expect(por.map((p) => p.inicioSiguiente.toLocal()), [_hoy(9), _hoy(10)]);
    });

    test('una sola abierta: nada que preguntar (de eso se ocupa Hoy)', () async {
      armar([_jornada('a', _hoy(8))]);

      expect(await lista(), isEmpty);
    });

    test('sin jornadas: vacío', () async {
      armar(const []);

      expect(await lista(), isEmpty);
    });

    test('una abierta con otra después ya cerrada también se pregunta', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9), fin: _hoy(12))]);

      final por = await lista();

      expect(por.single.jornada.id, 'a');
      expect(por.single.inicioSiguiente.toLocal(), _hoy(9));
    });

    test('no cuenta lo de otro colportor ni lo dado de baja', () async {
      armar([
        _jornada('a', _hoy(8)),
        _jornada('otro', _hoy(9), colportor: 'u-2'),
        _jornada('borrada', _hoy(10), borrada: _hoy(11)),
      ]);

      expect(await lista(), isEmpty);
    });

    test('un colportor vacío es una validación, no una lectura', () async {
      armar(const []);

      final r = await porCerrar()(const JornadasPorCerrarParams(colportorId: '  '));

      expect(falla(r), isA<FailureValidacion>());
    });
  });

  group('FinalizarJornadaAnteriorUseCase', () {
    FinalizarJornadaAnteriorParams params(String id, DateTime hora) =>
        FinalizarJornadaAnteriorParams(colportorId: 'u-1', jornadaId: id, hora: hora);

    test('cierra la anterior con la hora elegida y no toca la jornada en curso', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      final r = await finalizar()(params('a', _hoy(8, 45)));

      final cerrada = r.fold((f) => fail(f.mensaje), (j) => j);
      expect(cerrada.fin!.toLocal(), _hoy(8, 45));
      final guardadas = {for (final j in local.jornadas) j.id: j};
      expect(guardadas['a']!.fin!.toLocal(), _hoy(8, 45));
      expect(guardadas['b']!.fin, isNull, reason: 'la jornada en curso sigue abierta');
      expect(backup.pedidos, 1);
      expect(await lista(), isEmpty, reason: 'ya no queda nada por cerrar');
    });

    test('nunca la cierra con la hora de ahora', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      await finalizar()(params('a', _hoy(8, 30)));

      final cerrada = local.jornadas.firstWhere((j) => j.id == 'a');
      expect(cerrada.fin!.toLocal(), isNot(ahora));
    });

    test('una hora después del inicio de la siguiente se rechaza con el rango real', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      final r = await finalizar()(params('a', _hoy(9, 30)));

      final f = falla(r);
      expect(f, isA<FailureHoraFueraDeRango>());
      expect((f! as FailureHoraFueraDeRango).hasta.toLocal(), _hoy(9));
      expect(local.jornadas.firstWhere((j) => j.id == 'a').fin, isNull);
      expect(backup.pedidos, 0);
    });

    test('una hora antes (o igual) al inicio se rechaza', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      expect(falla(await finalizar()(params('a', _hoy(8)))), isA<FailureHoraFueraDeRango>());
      expect(falla(await finalizar()(params('a', _hoy(7)))), isA<FailureHoraFueraDeRango>());
    });

    test('el fin puede ser justo el inicio de la siguiente', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      final r = await finalizar()(params('a', _hoy(9)));

      expect(r.isRight(), isTrue);
    });

    test('la siguiente empieza en el mismo minuto: no queda hora que elegir', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(8))]);
      // Con el mismo inicio, `siguienteA` no ve una posterior: no hay nada por cerrar.
      expect(await lista(), isEmpty);

      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(8).add(const Duration(seconds: 30)))]);
      final r = await finalizar()(params('a', _hoy(8, 30)));

      expect(falla(r), isA<FailureJornadaDeDiaAnterior>());
    });

    test(
      'doble envío: el segundo ya no encuentra la jornada abierta y no escribe ni pide backup',
      () async {
        armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);
        final caso = finalizar();

        final primero = await caso(params('a', _hoy(8, 30)));
        final segundo = await caso(params('a', _hoy(8, 40)));

        expect(primero.isRight(), isTrue);
        expect(falla(segundo), isA<FailureSinJornadaActiva>());
        expect(local.jornadas.firstWhere((j) => j.id == 'a').fin!.toLocal(), _hoy(8, 30));
        expect(backup.pedidos, 1);
      },
    );

    test('dos jornadas por cerrar, una detrás de la otra, sin pisarse', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9)), _jornada('c', _hoy(10))]);
      final caso = finalizar();

      await caso(params('a', _hoy(8, 50)));
      expect((await lista()).map((p) => p.jornada.id), ['b']);
      await caso(params('b', _hoy(9, 50)));

      expect(await lista(), isEmpty);
      final guardadas = {for (final j in local.jornadas) j.id: j};
      expect(guardadas['a']!.fin!.toLocal(), _hoy(8, 50));
      expect(guardadas['b']!.fin!.toLocal(), _hoy(9, 50));
      expect(guardadas['c']!.fin, isNull);
    });

    test('la jornada en curso (sin otra después) no se cierra por acá', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      final r = await finalizar()(params('b', _hoy(9, 30)));

      expect(falla(r), isA<FailureSinJornadaActiva>());
      expect(local.jornadas.firstWhere((j) => j.id == 'b').fin, isNull);
    });

    test('una jornada que no existe no se inventa', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);

      expect(falla(await finalizar()(params('nada', _hoy(8, 30)))), isA<FailureSinJornadaActiva>());
    });

    test('con el reloj del teléfono antes del inicio no se cierra', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);
      ahora = _hoy(7);

      final r = await finalizar()(params('a', _hoy(8, 30)));

      expect(falla(r), isNotNull);
      expect(local.jornadas.firstWhere((j) => j.id == 'a').fin, isNull);
    });

    test('si pedir el backup falla, el cierre ya está hecho y el error va al registro', () async {
      armar([_jornada('a', _hoy(8)), _jornada('b', _hoy(9))]);
      backup.error = StateError('sin Drive');

      final r = await finalizar()(params('a', _hoy(8, 30)));
      await Future<void>.delayed(Duration.zero);

      expect(r.isRight(), isTrue);
      expect(fallasDeBackup, hasLength(1));
    });

    test('un colportor vacío es una validación', () async {
      armar(const []);

      final r = await finalizar()(
        FinalizarJornadaAnteriorParams(colportorId: ' ', jornadaId: 'a', hora: _hoy(8, 30)),
      );

      expect(falla(r), isA<FailureValidacion>());
    });
  });
}
