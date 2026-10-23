// Registrar el resultado de una visita (HU-VIS-005, #410): validación, armado de la visita y su nota,
// ids estables y el punto de enganche de la venta. El guardado real, contra la DB, está en
// `registrar_resultado_visita_datos_test.dart`.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/nota_de_campo.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

typedef _Recibida = ({Visita visita, String? agendaId, NotaDeCampo? nota});

final class _RepositorioFalso implements AgendaRepository {
  final recibidas = <_Recibida>[];

  /// Lo que devuelve la próxima llamada (si no, la visita guardada tal cual).
  Either<Failure, VisitaGuardada>? respuesta;

  @override
  Future<Either<Failure, VisitaGuardada>> registrarVisita(
    Visita visita, {
    String? agendaId,
    NotaDeCampo? nota,
  }) async {
    recibidas.add((visita: visita, agendaId: agendaId, nota: nota));
    return respuesta ?? Right(VisitaGuardada(visita: visita));
  }

  @override
  Future<Either<Failure, Agenda>> agendar(Agenda agenda, {NotaDeCampo? nota}) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Agenda>> cancelar(String agendaId, {required DateTime ahora}) =>
      throw UnimplementedError();
}

void main() {
  final ahora = DateTime.utc(2026, 10, 23, 15, 30, 5, 123);
  late _RepositorioFalso repositorio;
  late RegistrarResultadoVisitaUseCase casoDeUso;
  var contador = 0;

  setUp(() {
    contador = 0;
    repositorio = _RepositorioFalso();
    casoDeUso = RegistrarResultadoVisitaUseCase(
      repositorio,
      generarId: () => 'id-${++contador}',
      ahora: () => ahora,
    );
  });

  RegistrarResultadoVisitaParams params({
    TipoResultadoVisita resultado = TipoResultadoVisita.entrevista,
    String espacioPersonaId = 'ep-1',
    String colportorId = 'col-1',
    String? agendaId,
    String? jornadaId,
    String nota = '',
    IdsResultadoVisita? ids,
  }) => RegistrarResultadoVisitaParams(
    ids: ids ?? casoDeUso.nuevosIds(),
    espacioPersonaId: espacioPersonaId,
    colportorId: colportorId,
    resultado: resultado,
    agendaId: agendaId,
    jornadaId: jornadaId,
    nota: nota,
  );

  Map<String, String> camposDe(Either<Failure, ResultadoVisitaRegistrado> resultado) {
    final izquierda = resultado.fold<Failure?>((f) => f, (_) => null);
    expect(izquierda, isA<FailureValidacion>());
    return (izquierda! as FailureValidacion).campos;
  }

  group('dado un resultado, cuando se registra', () {
    test('arma la visita con el instante, la persona, el colportor y el resultado', () async {
      final r = await casoDeUso(
        params(resultado: TipoResultadoVisita.rechazo, jornadaId: ' jor-1 '),
      );

      expect(r.isRight(), isTrue);
      final visita = repositorio.recibidas.single.visita;
      expect(visita.id, 'id-1');
      expect(visita.espacioPersonaId, 'ep-1');
      expect(visita.colportorId, 'col-1');
      expect(visita.tipoResultado, TipoResultadoVisita.rechazo);
      expect(visita.jornadaId, 'jor-1');
      expect(visita.fecha, ahora);
      expect(visita.auditoria.createdBy, 'col-1');
      expect(visita.auditoria.createdAt, ahora);
    });

    test('sin nota, sin agenda y sin jornada, pasa null a las tres', () async {
      await casoDeUso(params(agendaId: '  ', jornadaId: ' ', nota: '  \n '));

      final recibida = repositorio.recibidas.single;
      expect(recibida.nota, isNull);
      expect(recibida.agendaId, isNull);
      expect(recibida.visita.jornadaId, isNull);
    });

    test('con nota, la guarda sin espacios de más y con su propio id', () async {
      await casoDeUso(params(nota: '  No hay nadie de día; volver a las 19  '));

      final nota = repositorio.recibidas.single.nota!;
      expect(nota.id, 'id-2');
      expect(nota.texto, 'No hay nadie de día; volver a las 19');
      expect(nota.auditoria.createdBy, 'col-1');
    });

    test('con una nota larga y con saltos de línea, no la corta', () async {
      final larga = List.generate(400, (i) => 'renglón $i').join('\n');

      await casoDeUso(params(nota: larga));

      expect(repositorio.recibidas.single.nota!.texto, larga);
    });

    test('con la agenda de la casa, se la pasa al repositorio sin espacios', () async {
      await casoDeUso(params(agendaId: ' age-1 '));

      expect(repositorio.recibidas.single.agendaId, 'age-1');
    });

    test('devuelve lo que guardó el repositorio con su aviso de la agenda', () async {
      final visita = Visita(
        id: 'id-1',
        espacioPersonaId: 'ep-1',
        fecha: ahora,
        tipoResultado: TipoResultadoVisita.noContesto,
        colportorId: 'col-1',
        auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: 'col-1'),
      );
      repositorio.respuesta = Right(VisitaGuardada(visita: visita, agendaQuedoPendiente: true));

      final r = await casoDeUso(params(resultado: TipoResultadoVisita.noContesto));

      final registrado = r.getOrElse(() => throw StateError('falló'));
      expect(registrado.guardada.aviso, VisitaGuardada.avisoAgendaPendiente);
      expect(registrado.seguimiento, SeguimientoDeVisita.ninguno);
    });

    test('si el repositorio falla, devuelve esa misma falla', () async {
      repositorio.respuesta = const Left(FailureInesperado(causa: 'StateError'));

      final r = await casoDeUso(params());

      expect(
        r,
        const Left<Failure, ResultadoVisitaRegistrado>(FailureInesperado(causa: 'StateError')),
      );
    });
  });

  group('dado un formulario con ids, cuando se repite el envío', () {
    test('los ids de un formulario nuevo son distintos entre sí y de otro formulario', () {
      final a = casoDeUso.nuevosIds();
      final b = casoDeUso.nuevosIds();

      expect({a.visita, a.nota, b.visita, b.nota}.length, 4);
    });

    test('el mismo formulario manda siempre la misma visita y la misma nota', () async {
      final ids = casoDeUso.nuevosIds();

      await casoDeUso(params(ids: ids, nota: 'una nota'));
      await casoDeUso(params(ids: ids, nota: 'una nota'));

      expect(repositorio.recibidas.map((r) => r.visita.id).toSet(), {ids.visita});
      expect(repositorio.recibidas.map((r) => r.nota!.id).toSet(), {ids.nota});
    });
  });

  group('dado el seguimiento de cada resultado (el enganche de la venta)', () {
    test('solo VENTA sigue al flujo de venta', () async {
      final seguimientos = <TipoResultadoVisita, SeguimientoDeVisita>{};
      for (final resultado in TipoResultadoVisita.values) {
        final r = await casoDeUso(params(resultado: resultado));
        seguimientos[resultado] = r.getOrElse(() => throw StateError('falló')).seguimiento;
      }

      expect(seguimientos, {
        TipoResultadoVisita.venta: SeguimientoDeVisita.venta,
        TipoResultadoVisita.noContesto: SeguimientoDeVisita.ninguno,
        TipoResultadoVisita.rechazo: SeguimientoDeVisita.ninguno,
        TipoResultadoVisita.entrevista: SeguimientoDeVisita.ninguno,
      });
    });
  });

  group('dado un dato que falta, cuando se registra', () {
    test('sin persona, no guarda nada y dice qué hacer (P3 de #151: sin persona vacía)', () async {
      for (final vacia in ['', '   ']) {
        final r = await casoDeUso(params(espacioPersonaId: vacia));

        expect(camposDe(r).keys, ['persona']);
        expect(camposDe(r)['persona'], contains('Elegí'));
      }
      expect(repositorio.recibidas, isEmpty);
    });

    test('sin colportor, no guarda nada', () async {
      final r = await casoDeUso(params(colportorId: ' '));

      expect(camposDe(r).keys, ['colportorId']);
      expect(repositorio.recibidas, isEmpty);
    });

    test('sin ids, no guarda nada', () async {
      final r = await casoDeUso(
        params(
          ids: const IdsResultadoVisita(visita: '', nota: 'n'),
        ),
      );

      expect(camposDe(r).keys, ['ids']);
      expect(repositorio.recibidas, isEmpty);
    });

    test('con todo mal, avisa de cada campo a la vez', () async {
      final r = await casoDeUso(
        params(
          espacioPersonaId: '',
          colportorId: '',
          ids: const IdsResultadoVisita(visita: '', nota: ''),
        ),
      );

      expect(camposDe(r).keys.toSet(), {'persona', 'colportorId', 'ids'});
    });
  });

  test('los parametros no imprimen la nota (es un dato personal)', () {
    final p = params(nota: 'la hija de Ana Martínez, 099 123 456');

    expect('$p', isNot(contains('Ana')));
    expect('$p', isNot(contains('099')));
  });
}
