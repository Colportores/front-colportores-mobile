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
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

final class _Local implements AgendaLocalDataSource {
  Object? lanza;
  MotivoAgendaIgnorada? ignorada;
  bool noCumplida = false;
  VisitaDeshecha? deshecha;

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
    return (
      visita: visita,
      yaEstaba: false,
      agendaIgnorada: ignorada,
      agendaNoCumplida: noCumplida,
      agendaCreadaId: 'age-nueva',
      agendaAfectadaId: null,
    );
  }

  @override
  Future<VisitaDeshecha> deshacerVisita(
    String visitaId, {
    String? agendaCreadaId,
    String? agendaAfectadaId,
    required DateTime ahora,
  }) async {
    _lanzarSiCorresponde();
    return deshecha ?? (visita: visitaDe(visitaId), escribio: true);
  }

  Agenda? programada;

  @override
  Future<Agenda?> agendaProgramadaDe(String espacioId) async {
    _lanzarSiCorresponde();
    return programada;
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

      expect(r.getOrElse(() => throw StateError('falló')).visita.id, 'vis-1');
    });

    test('registrar la visita con una agenda que no sirve devuelve la visita y el aviso', () async {
      local.ignorada = MotivoAgendaIgnorada.cerrada;

      final r = await repositorio.registrarVisita(visitaDe('vis-1'), agendaId: 'age-1');

      final guardada = r.getOrElse(() => throw StateError('falló'));
      expect(guardada.visita.id, 'vis-1');
      expect(guardada.agendaIgnorada, MotivoAgendaIgnorada.cerrada);
      expect(
        guardada.aviso,
        'Esa agenda ya estaba cerrada: guardamos la visita igual, como visita espontánea.',
      );
    });

    test(
      'registrar la visita que deja la agenda no cumplida lo dice, sin aviso de error',
      () async {
        local.noCumplida = true;

        final r = await repositorio.registrarVisita(visitaDe('vis-1'), agendaId: 'age-1');

        final guardada = r.getOrElse(() => throw StateError('falló'));
        expect(guardada.agendaNoCumplida, isTrue);
        expect(guardada.agendaIgnorada, isNull);
        expect(guardada.aviso, isNull);
        expect(guardada.agendaCreadaId, 'age-nueva');
      },
    );

    test('deshacer una visita devuelve la visita dada de baja', () async {
      final r = await repositorio.deshacerVisita('vis-1', ahora: DateTime.utc(2026, 10, 25));

      expect(r.getOrElse(() => throw StateError('falló')).id, 'vis-1');
    });

    test(
      'deshacer una visita que el teléfono no tiene es una validación en el campo visita',
      () async {
        local.lanza = const AgendaRechazadaException(MotivoRechazoAgenda.visitaInexistente);

        final r = await repositorio.deshacerVisita('vis-x', ahora: DateTime.utc(2026, 10, 25));

        final falla = r.fold<Failure?>((f) => f, (_) => null);
        expect(falla, isA<FailureValidacion>());
        expect((falla! as FailureValidacion).campos.keys, ['visita']);
      },
    );

    test('la agenda programada de la casa sale tal cual, o null si no hay', () async {
      expect(
        (await repositorio.agendaProgramadaDe('esp-1')).getOrElse(() => throw StateError('x')),
        isNull,
      );

      local.programada = agendaDe('age-1');
      final r = await repositorio.agendaProgramadaDe('esp-1');

      expect(r.getOrElse(() => throw StateError('falló'))!.id, 'age-1');
    });

    test('leer la agenda de la casa que falla es un error inesperado, sin excepción', () async {
      local.lanza = StateError('no se pudo leer');

      final r = await repositorio.agendaProgramadaDe('esp-1');

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), isA<FailureInesperado>());
    });

    test('registrar la visita sin problema no trae aviso', () async {
      final r = await repositorio.registrarVisita(visitaDe('vis-1'));

      expect(r.getOrElse(() => throw StateError('falló')).aviso, isNull);
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
