// Cancelar una agenda (HU-VIS-004, #150): validación, orden (primero la base, después el aviso), qué
// pasa si falla cada parte y el reintento. La cancelación real, contra la DB, está en
// `cancelar_agenda_datos_test.dart`. Los escenarios llevan el título de la HU.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/cancelar_agenda_use_case.dart';
import 'package:test/test.dart';

import '../../../../../helpers/agenda_repositorio_falso.dart';

/// Un [Recordatorios] cuyo plugin se cae: lanza al cancelar.
final class _RecordatoriosQueLanzan implements Recordatorios {
  final llamadas = <String>[];

  @override
  Future<bool> cancelar(String agendaId) async {
    llamadas.add('cancelar:$agendaId');
    throw StateError('el plugin se cayó');
  }

  @override
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita) async =>
      ResultadoRecordatorio.programado;

  @override
  Future<bool> puedeAvisar() async => true;
}

void main() {
  final ahora = DateTime.utc(2026, 10, 26, 18, 30, 5, 123);
  late AgendaRepositorioFalso repositorio;
  late RecordatoriosEnMemoria recordatorios;
  late CancelarAgendaUseCase casoDeUso;

  RecordatorioDeVisita aviso(String id) => RecordatorioDeVisita(
    agendaId: id,
    tipo: TipoAgenda.entrevista,
    direccion: 'Av. Italia 1234',
    fechaProgramada: DateTime.utc(2026, 10, 27, 17),
  );

  CancelarAgendaUseCase armar([Recordatorios? r]) =>
      CancelarAgendaUseCase(repositorio, r ?? recordatorios, ahora: () => ahora);

  setUp(() {
    repositorio = AgendaRepositorioFalso();
    recordatorios = RecordatoriosEnMemoria();
    casoDeUso = armar();
  });

  group('Escenario: Cancelar', () {
    test('dado que tengo una agenda PROGRAMADA, cuando cancelo, pasa a CANCELADA con la hora de '
        'ahora y el recordatorio se elimina', () async {
      await recordatorios.programar(aviso('age-1'));

      final r = await casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));

      final hecho = r.getOrElse(() => throw StateError('falló: $r'));
      expect(hecho.agenda.estado, EstadoAgenda.cancelada);
      expect(hecho.recordatorioCancelado, isTrue);
      expect(repositorio.canceladas, [(agendaId: 'age-1', ahora: ahora)]);
      expect(recordatorios.programados, isEmpty);
      expect(recordatorios.llamadas, ['programar:age-1', 'cancelar:age-1']);
    });

    test('dado un id con espacios alrededor, cuando cancelo, se usa el id limpio', () async {
      await casoDeUso(const CancelarAgendaParams(agendaId: '  age-1 '));

      expect(repositorio.canceladas.single.agendaId, 'age-1');
      expect(recordatorios.llamadas, ['cancelar:age-1']);
    });
  });

  group('Validación', () {
    for (final id in ['', '   ']) {
      test('dado un id en blanco ("$id"), cuando cancelo, falla por el campo agenda y no toca la '
          'base ni el recordatorio', () async {
        final r = await casoDeUso(CancelarAgendaParams(agendaId: id));

        final falla = r.fold((f) => f, (_) => null);
        expect(falla, isA<FailureValidacion>());
        expect((falla! as FailureValidacion).campos.keys, ['agenda']);
        expect(repositorio.canceladas, isEmpty);
        expect(recordatorios.llamadas, isEmpty);
      });
    }

    test('dado que la agenda ya se cumplió o no está, cuando cancelo, devuelve la falla del '
        'repositorio y el recordatorio no se toca', () async {
      const motivo = FailureValidacion(
        campos: {'agenda': 'Esa agenda ya se cumplió o se canceló.'},
      );
      repositorio.resultadosCancelar.add(motivo);

      final r = await casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));

      expect(r.fold((f) => f, (_) => null), motivo);
      expect(recordatorios.llamadas, isEmpty);
    });

    test('dado que la base falla, cuando cancelo, la falla sale tal cual y el aviso sigue '
        'programado (la agenda sigue PROGRAMADA)', () async {
      await recordatorios.programar(aviso('age-1'));
      repositorio.resultadosCancelar.add(const FailureInesperado(causa: 'StateError'));

      final r = await casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));

      expect(r.fold((f) => f, (_) => null), isA<FailureInesperado>());
      expect(recordatorios.programados.keys, ['age-1']);
    });
  });

  group('El recordatorio', () {
    test('dado que el teléfono no puede cancelar el aviso, cuando cancelo, la agenda queda '
        'cancelada y el resultado lo dice', () async {
      await recordatorios.programar(aviso('age-1'));
      recordatorios.puedeCancelar = false;

      final r = await casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));

      final hecho = r.getOrElse(() => throw StateError('falló: $r'));
      expect(hecho.agenda.estado, EstadoAgenda.cancelada);
      expect(hecho.recordatorioCancelado, isFalse);
    });

    test('dado que el plugin lanza al cancelar, cuando cancelo, la agenda queda cancelada igual '
        'y no escapa ninguna excepción', () async {
      final r = await armar(_RecordatoriosQueLanzan())(
        const CancelarAgendaParams(agendaId: 'age-1'),
      );

      final hecho = r.getOrElse(() => throw StateError('falló: $r'));
      expect(hecho.agenda.estado, EstadoAgenda.cancelada);
      expect(hecho.recordatorioCancelado, isFalse);
    });

    test('dado que la base todavía escribe, cuando espero, el aviso no se toca hasta que la '
        'agenda quedó cancelada', () async {
      repositorio.compuertaCancelar = Completer<void>();
      await recordatorios.programar(aviso('age-1'));
      recordatorios.llamadas.clear();

      final enCurso = casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));
      await Future<void>.delayed(Duration.zero);
      expect(recordatorios.llamadas, isEmpty);
      expect(recordatorios.programados.keys, ['age-1']);

      repositorio.compuertaCancelar!.complete();
      await enCurso;
      expect(recordatorios.llamadas, ['cancelar:age-1']);
    });
  });

  group('Dos veces seguidas', () {
    test('dado que ya cancelé, cuando cancelo otra vez, no es un error y vuelve a pedir sacar el '
        'aviso (el reintento arregla un aviso que no se pudo cancelar)', () async {
      await recordatorios.programar(aviso('age-1'));
      recordatorios.puedeCancelar = false;
      final primera = await casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));
      expect(primera.getOrElse(() => throw StateError('falló')).recordatorioCancelado, isFalse);

      recordatorios.puedeCancelar = true;
      final segunda = await casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));

      expect(segunda.getOrElse(() => throw StateError('falló')).recordatorioCancelado, isTrue);
      expect(recordatorios.programados, isEmpty);
      expect(recordatorios.llamadas, ['programar:age-1', 'cancelar:age-1', 'cancelar:age-1']);
    });

    test('dado que dos toques llegan antes de que termine el primero, cuando se resuelven, cada '
        'uno devuelve la agenda cancelada y no se pierde ninguno', () async {
      repositorio.compuertaCancelar = Completer<void>();

      final a = casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));
      final b = casoDeUso(const CancelarAgendaParams(agendaId: 'age-1'));
      repositorio.compuertaCancelar!.complete();
      final resultados = await Future.wait([a, b]);

      for (final r in resultados) {
        expect(r.getOrElse(() => throw StateError('falló')).agenda.estado, EstadoAgenda.cancelada);
      }
      expect(repositorio.canceladas, hasLength(2));
    });
  });
}
