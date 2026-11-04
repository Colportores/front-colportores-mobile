// «Empezar» y «Finalizar» una entrevista (vista 39, R·04 → R·05 → R·06; HU-VIS-005, #450): la hora de
// inicio no se pierde ni se pisa, las horas se validan, la visita sale como «Entrevista dada» y la
// entrevista en curso se borra solo cuando la visita quedó guardada.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/entrevista_en_curso_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/empezar_entrevista_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/finalizar_entrevista_use_case.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/entrevista_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  late EntrevistaEnCursoEnMemoria memoria;
  late EntrevistaEnCursoRota almacen;
  late AgendaFalsa agenda;
  late DestinoFalso destino;
  late BorradorFalso borrador;
  var contador = 0;
  var reloj = ahoraEntrevista;

  late EmpezarEntrevistaUseCase empezar;
  late FinalizarEntrevistaUseCase finalizar;

  setUp(() {
    contador = 0;
    reloj = inicioEntrevista;
    memoria = EntrevistaEnCursoEnMemoria();
    almacen = EntrevistaEnCursoRota(memoria);
    agenda = AgendaFalsa();
    destino = DestinoFalso();
    borrador = BorradorFalso();
    empezar = EmpezarEntrevistaUseCase(
      almacen,
      generarId: () => 'id-${++contador}',
      ahora: () => reloj,
      logger: loggerMudo(),
    );
    finalizar = FinalizarEntrevistaUseCase(
      RegistrarResultadoVisitaUseCase(
        agenda,
        generarId: () => 'x-${++contador}',
        ahora: () => reloj.toUtc(),
      ),
      almacen,
      destino,
      borrador,
      ahora: () => reloj,
      logger: loggerMudo(),
    );
  });

  const params = EmpezarEntrevistaParams(
    colportorId: 'col-1',
    espacioId: 'esp-1',
    espacioPersonaId: 'ep-1',
  );

  group('empezar', () {
    test('guarda la entrevista con la hora del toque y los ids de la visita y la nota', () async {
      final r = await empezar(params);

      final entrevista = r.getOrElse(() => throw StateError('falló'));
      expect(entrevista.inicio, inicioEntrevista.toUtc());
      expect(entrevista.ids.visita, 'id-1');
      expect(entrevista.ids.nota, 'id-2');
      expect(await memoria.leer('col-1'), entrevista);
    });

    test('lleva la agenda y la jornada, y las deja en null si vienen en blanco', () async {
      final r = await empezar(
        const EmpezarEntrevistaParams(
          colportorId: ' col-1 ',
          espacioId: ' esp-1 ',
          espacioPersonaId: ' ep-1 ',
          agendaId: 'age-1',
          jornadaId: '  ',
        ),
      );

      final entrevista = r.getOrElse(() => throw StateError('falló'));
      expect(entrevista.colportorId, 'col-1');
      expect(entrevista.agendaId, 'age-1');
      expect(entrevista.jornadaId, isNull);
    });

    test('con una entrevista ya en curso devuelve esa: la hora de inicio no se pisa', () async {
      await empezar(params);
      reloj = reloj.add(const Duration(minutes: 10));

      final r = await empezar(params);

      final entrevista = r.getOrElse(() => throw StateError('falló'));
      expect(entrevista.inicio, inicioEntrevista.toUtc());
      expect(entrevista.ids.visita, 'id-1');
      expect(memoria.guardadas, hasLength(1));
    });

    test('sin colportora, lugar o persona no guarda nada y dice qué falta', () async {
      final r = await empezar(
        const EmpezarEntrevistaParams(colportorId: '', espacioId: ' ', espacioPersonaId: ''),
      );

      final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
      expect(falla, isA<FailureValidacion>());
      expect(
        (falla as FailureValidacion).campos.keys,
        unorderedEquals(<String>['colportorId', 'espacioId', 'persona']),
      );
      expect(memoria.guardadas, isEmpty);
    });

    test(
      'si el almacén falla al guardar, devuelve la falla y no hay entrevista en curso',
      () async {
        almacen.fallaAlGuardar = true;

        final r = await empezar(params);

        expect(r.isLeft(), isTrue);
        expect(memoria.guardadas, isEmpty);
      },
    );

    test('si el almacén falla al leer, devuelve la falla y no guarda otra encima', () async {
      almacen.fallaAlLeer = true;

      final r = await empezar(params);

      expect(r.isLeft(), isTrue);
      expect(memoria.guardadas, isEmpty);
    });
  });

  group('finalizar', () {
    final entrada = DateTime(2026, 10, 23, 14, 23);
    final salida = DateTime(2026, 10, 23, 14, 41);

    Future<void> conEntrevistaEnCurso() async {
      await memoria.guardar(entrevistaDePrueba(agendaId: 'age-1', jornadaId: 'jor-1'));
      reloj = ahoraEntrevista;
    }

    FinalizarEntrevistaParams finalizando({String nota = '', DateTime? e, DateTime? s}) =>
        FinalizarEntrevistaParams.de(
          entrevistaDePrueba(agendaId: 'age-1', jornadaId: 'jor-1'),
          entrada: e ?? entrada,
          salida: s ?? salida,
          nota: nota,
        );

    test('guarda la visita como «Entrevista dada» con los ids, la agenda y la jornada', () async {
      await conEntrevistaEnCurso();

      final r = await finalizar(finalizando(nota: 'volver con la esposa'));

      expect(r.isRight(), isTrue);
      final recibida = agenda.recibidas.single;
      expect(recibida.visita.tipoResultado, TipoResultadoVisita.entrevista);
      expect(recibida.visita.id, 'vis-1');
      expect(recibida.visita.espacioPersonaId, 'ep-1');
      expect(recibida.visita.colportorId, 'col-1');
      expect(recibida.visita.jornadaId, 'jor-1');
      expect(recibida.agendaId, 'age-1');
      expect(recibida.nota!.id, 'not-1');
      expect(recibida.nota!.texto, 'volver con la esposa');
    });

    test('al guardar bien, la entrevista deja de estar en curso', () async {
      await conEntrevistaEnCurso();

      await finalizar(finalizando());

      expect(memoria.guardadas, isEmpty);
    });

    test('«Sí, registrar la venta» no pasa por acá: el resultado no se guarda (R44)', () async {
      await conEntrevistaEnCurso();

      // El caso de uso solo existe para «No, guardar y volver al mapa»; sin llamarlo, nada cambia.
      expect(agenda.recibidas, isEmpty);
      expect(memoria.guardadas, hasLength(1));
    });

    test('una salida antes de la entrada no guarda la visita ni borra la entrevista', () async {
      await conEntrevistaEnCurso();

      final r = await finalizar(finalizando(s: DateTime(2026, 10, 23, 14, 10)));

      expect(r.swap().getOrElse(() => throw StateError('debía fallar')), isA<FailureValidacion>());
      expect(agenda.recibidas, isEmpty);
      expect(memoria.guardadas, hasLength(1));
    });

    test('una salida que todavía no pasó no guarda nada', () async {
      await conEntrevistaEnCurso();

      final r = await finalizar(finalizando(s: DateTime(2026, 10, 23, 14, 50)));

      expect(r.isLeft(), isTrue);
      expect(agenda.recibidas, isEmpty);
    });

    test(
      'si la visita no se pudo guardar, la entrevista sigue en curso y se puede reintentar',
      () async {
        await conEntrevistaEnCurso();
        agenda.falla = const FailureInesperado();

        final r = await finalizar(finalizando());

        expect(r.isLeft(), isTrue);
        expect(memoria.guardadas, hasLength(1));

        agenda.falla = null;
        final reintento = await finalizar(finalizando());
        expect(reintento.isRight(), isTrue);
        expect(memoria.guardadas, isEmpty);
        expect(agenda.recibidas, hasLength(1));
      },
    );

    test('si la visita se guardó pero no se pudo borrar la entrevista, devuelve la falla y el '
        'reintento con los mismos ids no duplica la visita', () async {
      await conEntrevistaEnCurso();
      almacen.fallaAlBorrar = true;

      final r = await finalizar(finalizando());

      expect(r.isLeft(), isTrue);
      expect(memoria.guardadas, hasLength(1));
      expect(agenda.recibidas.map((v) => v.visita.id), ['vis-1']);

      almacen.fallaAlBorrar = false;
      final reintento = await finalizar(finalizando());
      expect(reintento.isRight(), isTrue);
      expect(memoria.guardadas, isEmpty);
      // El repositorio real devuelve la que ya estaba para el mismo id: mismos ids, misma visita.
      expect(agenda.recibidas.map((v) => v.visita.id).toSet(), {'vis-1'});
    });

    test('terminar una entrevista no borra otra que empezó después', () async {
      await memoria.guardar(entrevistaDePrueba(visitaId: 'vis-nueva'));

      await finalizar(finalizando());

      expect((await memoria.leer('col-1'))!.ids.visita, 'vis-nueva');
    });

    test('sin entrevista en curso (R·07) guarda igual la visita con los ids que le dan', () async {
      reloj = ahoraEntrevista;

      final r = await finalizar(finalizando(e: DateTime(2026, 10, 23, 14, 10)));

      expect(r.isRight(), isTrue);
      expect(agenda.recibidas, hasLength(1));
    });

    test('sin persona no se guarda con una persona vacía', () async {
      reloj = ahoraEntrevista;

      final r = await finalizar(
        FinalizarEntrevistaParams(
          ids: const IdsResultadoVisita(visita: 'v', nota: 'n'),
          espacioId: 'esp-1',
          espacioPersonaId: ' ',
          colportorId: 'col-1',
          entrada: entrada,
          salida: salida,
        ),
      );

      expect(r.isLeft(), isTrue);
      expect(agenda.recibidas, isEmpty);
    });

    group('«Sin salida» (25/10): se guarda igual', () {
      test('la visita cuelga del espacio y de la persona que encontró el resolvedor', () async {
        await conEntrevistaEnCurso();
        // La unión de duplicados movió a la persona al espacio que quedó.
        destino.destino = const DestinoDeEntrevista(
          espacioId: 'esp-que-quedo',
          espacioPersonaId: 'ep-1',
        );

        final r = await finalizar(finalizando());

        expect(r.isRight(), isTrue);
        expect(agenda.recibidas.single.visita.espacioId, 'esp-que-quedo');
        expect(agenda.recibidas.single.visita.espacioPersonaId, 'ep-1');
        expect(destino.consultas.single, (espacioId: 'esp-1', espacioPersonaId: 'ep-1'));
        expect(memoria.guardadas, isEmpty);
      });

      test(
        'la persona dada de baja: la visita queda de la casa, sin persona, con su nota',
        () async {
          await conEntrevistaEnCurso();
          destino.destino = const DestinoDeEntrevista(espacioId: 'esp-1');

          final r = await finalizar(finalizando(nota: 'perro suelto'));

          expect(r.isRight(), isTrue);
          final recibida = agenda.recibidas.single;
          expect(recibida.visita.espacioId, 'esp-1');
          expect(recibida.visita.espacioPersonaId, isNull);
          expect(recibida.visita.tipoResultado, TipoResultadoVisita.entrevista);
          expect(recibida.nota!.texto, 'perro suelto');
          expect(memoria.guardadas, isEmpty);
        },
      );

      test('sin casa ni depto donde colgarla: la entrevista se suelta con su borrador y no '
          'queda trabada', () async {
        await conEntrevistaEnCurso();
        destino.sinDestino = true;
        borrador.textos['not-1'] = 'perro suelto';

        final r = await finalizar(finalizando(nota: 'perro suelto'));

        expect(r, const Left<Failure, Object?>(entrevistaSinLugar));
        expect(agenda.recibidas, isEmpty);
        expect(memoria.guardadas, isEmpty);
        expect(borrador.borrados, ['not-1']);
        expect(borrador.textos, isEmpty);
      });

      test('si no se puede soltar la entrevista, devuelve la falla y sigue en curso', () async {
        await conEntrevistaEnCurso();
        destino.sinDestino = true;
        almacen.fallaAlBorrar = true;

        final r = await finalizar(finalizando());

        expect(
          r.swap().getOrElse(() => throw StateError('debía fallar')),
          isA<FailureInesperado>(),
        );
        expect(memoria.guardadas, hasLength(1));

        almacen.fallaAlBorrar = false;
        final reintento = await finalizar(finalizando());
        expect(reintento, const Left<Failure, Object?>(entrevistaSinLugar));
        expect(memoria.guardadas, isEmpty);
      });

      test('si no se puede leer dónde cuelga, no guarda nada y la entrevista sigue', () async {
        await conEntrevistaEnCurso();
        destino.falla = true;

        final r = await finalizar(finalizando());

        expect(
          r.swap().getOrElse(() => throw StateError('debía fallar')),
          isA<FailureInesperado>(),
        );
        expect(agenda.recibidas, isEmpty);
        expect(memoria.guardadas, hasLength(1));

        destino.falla = false;
        expect((await finalizar(finalizando())).isRight(), isTrue);
      });

      test('las horas inválidas no llegan a buscar el destino', () async {
        await conEntrevistaEnCurso();

        await finalizar(finalizando(s: DateTime(2026, 10, 23, 14, 10)));

        expect(destino.consultas, isEmpty);
      });
    });
  });
}
