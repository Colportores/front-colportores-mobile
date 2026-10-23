// Traducción de errores del repositorio de agendas y visitas (BACK-HU-VIS-001): una validación con el
// mensaje del motivo, o un error inesperado sin ningún dato de la persona.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/motivo_rechazo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

final class _Local implements AgendaLocalDataSource {
  Object? lanza;

  @override
  Future<AgendaAgendada> agendar(Agenda agenda, {NotaDeCampo? nota}) async {
    _lanzarSiCorresponde();
    return (agenda: agenda, yaEstaba: false);
  }

  @override
  Future<AgendaCancelada> cancelar(String agendaId, {required DateTime ahora}) async {
    _lanzarSiCorresponde();
    return (agenda: agendaDe(agendaId, estado: EstadoAgenda.cancelada), escribio: true);
  }

  @override
  Future<VisitaRegistrada> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) async {
    _lanzarSiCorresponde();
    return (visita: visita, yaEstaba: false);
  }

  @override
  Future<Agenda?> obtenerAgenda(String id) async => null;

  @override
  Future<Visita?> obtenerVisita(String id) async => null;

  void _lanzarSiCorresponde() {
    final error = lanza;
    if (error != null) throw error;
  }
}

void main() {
  late _Local local;
  late AgendaRepositoryImpl repositorio;

  setUp(() {
    local = _Local();
    repositorio = AgendaRepositoryImpl(local, logger: loggerMudo());
  });

  group('cuando sale bien', () {
    test('agendar devuelve la agenda', () async {
      final r = await repositorio.agendar(agendaDe('age-1'));

      expect(r.getOrElse(() => throw StateError('falló')), agendaDe('age-1'));
    });

    test('cancelar devuelve la agenda cancelada', () async {
      final r = await repositorio.cancelar('age-1', ahora: t0);

      expect(r.getOrElse(() => throw StateError('falló')).estado, EstadoAgenda.cancelada);
    });

    test('registrar la visita devuelve la visita', () async {
      final r = await repositorio.registrarVisita(visitaDe('vis-1'), agendaId: 'age-1');

      expect(r.getOrElse(() => throw StateError('falló')).id, 'vis-1');
    });
  });

  group('cuando la persistencia la rechaza', () {
    test('devuelve una validación con el mensaje del motivo en su campo', () async {
      for (final motivo in MotivoRechazoAgenda.values) {
        local.lanza = AgendaRechazadaException(motivo);

        final a = await repositorio.agendar(agendaDe('age-1'));
        final c = await repositorio.cancelar('age-1', ahora: t0);
        final v = await repositorio.registrarVisita(visitaDe('vis-1'));

        for (final r in [a.swap(), c.swap(), v.swap()]) {
          final f = r.getOrElse(() => throw StateError('debía fallar'));
          expect(f, isA<FailureValidacion>(), reason: motivo.name);
          expect((f as FailureValidacion).campos, {motivo.campo: motivo.mensaje});
        }
      }
    });
  });

  group('cuando falla algo que nadie previó', () {
    test(
      'devuelve un error inesperado que no lleva la sentencia ni los datos de la persona',
      () async {
        local.lanza = StateError(
          'INSERT INTO nota (texto) VALUES (la hija de Ana Martínez 099 123 456)',
        );

        final a = await repositorio.agendar(agendaDe('age-1'), nota: notaDe('nota-1'));
        final c = await repositorio.cancelar('age-1', ahora: t0);
        final v = await repositorio.registrarVisita(visitaDe('vis-1'));

        for (final r in [a.swap(), c.swap(), v.swap()]) {
          final f = r.getOrElse(() => throw StateError('debía fallar'));
          expect(f, isA<FailureInesperado>());
          expect('${f.props}', isNot(contains('Martínez')));
          expect('${f.props}', isNot(contains('099')));
          expect('${f.props}', contains('StateError'));
        }
      },
    );
  });
}
