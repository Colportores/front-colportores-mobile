// HU-VIS-001 (#408): agendar una visita y programar su recordatorio, sin pantalla.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/recordatorios.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/agendar_visita_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/agendar_visita_arnes.dart';

class _RecordatoriosQueLanzan implements Recordatorios {
  @override
  Future<ResultadoRecordatorio> programar(RecordatorioDeVisita visita) async {
    throw StateError('Mataojo 2044 no se debe filtrar');
  }

  @override
  Future<bool> cancelar(String agendaId) async => true;

  @override
  Future<bool> puedeAvisar() async => true;
}

void main() {
  late AgendaRepositorioQueAgenda repo;
  late RecordatoriosEnMemoria recordatorios;
  late DateTime ahora;
  late AgendarVisitaUseCase caso;
  var n = 0;

  setUp(() {
    n = 0;
    repo = AgendaRepositorioQueAgenda();
    recordatorios = RecordatoriosEnMemoria();
    ahora = DateTime(2026, 10, 23, 14, 35, 40);
    caso = AgendarVisitaUseCase(
      repo,
      recordatorios,
      generarId: () => 'id-${++n}',
      ahora: () => ahora,
    );
  });

  AgendarVisitaParams params({
    DateTime? cuando,
    TipoAgenda tipo = TipoAgenda.entrevista,
    String nota = '',
    String direccion = 'Mataojo 2044 · Depto 3B',
    bool confirmo = false,
    String espacioId = 'esp-1',
    String colportorId = 'col-1',
    String? persona = 'ep-p1',
    FranjaHoraria? franja = FranjaHoraria.primeraTarde,
    IdsAgendarVisita? ids,
  }) => AgendarVisitaParams(
    ids: ids ?? caso.nuevosIds(),
    espacioId: espacioId,
    espacioPersonaId: persona,
    colportorId: colportorId,
    tipo: tipo,
    fechaProgramada: cuando ?? DateTime(2026, 10, 24, 14, 30),
    franja: franja,
    nota: nota,
    direccion: direccion,
    confirmoHoraPasada: confirmo,
  );

  ResultadoAgendar resultado(Either<Failure, ResultadoAgendar> r) =>
      r.fold((f) => throw StateError('falló: $f'), (x) => x);

  group('AgendarVisitaUseCase', () {
    test(
      'dados los datos del canvas, cuando se agenda, entonces guarda PROGRAMADA y avisa',
      () async {
        final ok = resultado(await caso(params())) as VisitaAgendada;
        expect(ok.recordatorio, ResultadoRecordatorio.programado);
        expect(ok.agenda.estado, EstadoAgenda.programada);
        expect(ok.agenda.tipo, TipoAgenda.entrevista);
        expect(ok.agenda.slotCodigo, 'early_afternoon');
        expect(ok.agenda.espacioPersonaId, 'ep-p1');
        expect(ok.agenda.colportorId, 'col-1');
        expect(ok.agenda.auditoria.createdBy, 'col-1');
        expect(repo.cuantasQuedaron, 1);
        expect(recordatorios.programados.values.single.direccion, 'Mataojo 2044 · Depto 3B');
      },
    );

    test('dada una cobranza, cuando se agenda, entonces el tipo llega al recordatorio', () async {
      await caso(params(tipo: TipoAgenda.cobranza));
      expect(repo.recibidas.single.agenda.tipo, TipoAgenda.cobranza);
      expect(recordatorios.programados.values.single.tipo, TipoAgenda.cobranza);
    });

    test('dada una nota en blanco, cuando se agenda, entonces no crea nota', () async {
      await caso(params(nota: '   \n '));
      expect(repo.recibidas.single.nota, isNull);
    });

    test('dada una nota, cuando se agenda, entonces la guarda sin los bordes', () async {
      await caso(params(nota: '  Tocar el timbre dos veces  '));
      expect(repo.recibidas.single.nota?.texto, 'Tocar el timbre dos veces');
    });

    test(
      'dada una agenda sin persona ni franja, cuando se agenda, entonces cuelga del espacio',
      () async {
        await caso(params(persona: '  ', franja: null));
        final a = repo.recibidas.single.agenda;
        expect(a.espacioPersonaId, isNull);
        expect(a.slotCodigo, isNull);
      },
    );

    final invalidos = <String, AgendarVisitaParams Function()>{
      'espacio': () => params(espacioId: ' '),
      'colportorId': () => params(colportorId: ''),
      'ids': () => params(
        ids: const IdsAgendarVisita(agenda: '', nota: 'x'),
      ),
    };
    invalidos.forEach((campo, armar) {
      test(
        'dado un pedido sin $campo, cuando se agenda, entonces falla de validación y no guarda',
        () async {
          final r = await caso(armar());
          final falla = r.fold((f) => f, (_) => null);
          expect(falla, isA<FailureValidacion>());
          expect((falla! as FailureValidacion).campos.keys, contains(campo));
          expect(repo.recibidas, isEmpty);
          expect(recordatorios.llamadas, isEmpty);
        },
      );
    });

    test(
      'dada una hora que ya pasó sin confirmar, cuando se agenda, entonces pide confirmar',
      () async {
        final res = resultado(await caso(params(cuando: DateTime(2026, 10, 23, 11))));
        expect(res, isA<HoraPasadaSinConfirmar>());
        expect((res as HoraPasadaSinConfirmar).ahora, ahora);
        expect(repo.recibidas, isEmpty);
        expect(recordatorios.llamadas, isEmpty);
      },
    );

    test(
      'dada una hora pasada confirmada, cuando se agenda, entonces guarda sin recordatorio',
      () async {
        final ok =
            resultado(await caso(params(cuando: DateTime(2026, 10, 23, 11), confirmo: true)))
                as VisitaAgendada;
        expect(ok.recordatorio, isNull);
        expect(repo.cuantasQuedaron, 1);
        expect(recordatorios.llamadas, isEmpty);
      },
    );

    test('dado el minuto en curso, cuando se agenda, entonces no cuenta como pasada', () async {
      final res = resultado(await caso(params(cuando: DateTime(2026, 10, 23, 14, 35))));
      expect(res, isA<VisitaAgendada>());
    });

    test('dado el minuto anterior, cuando se agenda, entonces cuenta como pasada', () async {
      final res = resultado(await caso(params(cuando: DateTime(2026, 10, 23, 14, 34))));
      expect(res, isA<HoraPasadaSinConfirmar>());
    });

    test('dado un reloj en UTC, cuando se compara la hora, entonces mantiene el huso', () async {
      ahora = DateTime.utc(2026, 10, 23, 17, 35, 59);
      final res = resultado(await caso(params(cuando: DateTime.utc(2026, 10, 23, 17, 35))));
      expect(res, isA<VisitaAgendada>());
    });

    for (final forzado in ResultadoRecordatorio.values) {
      test(
        'dado un recordatorio que devuelve $forzado, cuando se agenda, entonces lo informa',
        () async {
          recordatorios.resultadoForzado = forzado;
          final ok = resultado(await caso(params())) as VisitaAgendada;
          expect(ok.recordatorio, forzado);
          expect(repo.cuantasQuedaron, 1);
        },
      );
    }

    test(
      'dado un recordatorio que lanza, cuando se agenda, entonces la agenda queda y dice noSePudo',
      () async {
        final otro = AgendarVisitaUseCase(
          repo,
          _RecordatoriosQueLanzan(),
          generarId: () => 'x-${++n}',
          ahora: () => ahora,
        );
        final ok =
            resultado(
                  await otro(
                    AgendarVisitaParams(
                      ids: otro.nuevosIds(),
                      espacioId: 'esp-1',
                      colportorId: 'col-1',
                      tipo: TipoAgenda.entrevista,
                      fechaProgramada: DateTime(2026, 10, 24, 14, 30),
                    ),
                  ),
                )
                as VisitaAgendada;
        expect(ok.recordatorio, ResultadoRecordatorio.noSePudo);
        expect(repo.cuantasQuedaron, 1);
      },
    );

    test(
      'dada una falla del repositorio, cuando se agenda, entonces no programa el recordatorio',
      () async {
        repo.fallas.add(const FailureInesperado());
        final r = await caso(params());
        expect(r.fold((f) => f, (_) => null), isA<FailureInesperado>());
        expect(recordatorios.llamadas, isEmpty);
      },
    );

    test(
      'dado el mismo formulario enviado varias veces, cuando se agenda, entonces queda una agenda',
      () async {
        final ids = caso.nuevosIds();
        final p = params(ids: ids);
        await Future.wait([caso(p), caso(p)]);
        await caso(p);
        expect(repo.cuantasQuedaron, 1);
        expect(repo.recibidas.map((e) => e.agenda.id).toSet(), {ids.agenda});
      },
    );

    test('dado un reintento tras una falla, cuando se agenda, entonces repite los ids', () async {
      final ids = caso.nuevosIds();
      repo.fallas.add(const FailureInesperado());
      await caso(params(ids: ids));
      await caso(params(ids: ids));
      expect(repo.recibidas.map((e) => e.agenda.id).toSet().length, 1);
      expect(repo.cuantasQuedaron, 1);
    });

    test('dados los parámetros con nota, cuando se imprimen, entonces no filtran la nota', () {
      final p = params(nota: 'Tiene perro bravo');
      expect(p.toString(), isNot(contains('perro')));
    });
  });
}
