// Test de dominio: Dart puro. «Registrar depósito» (HU-CTA-004, #442) con un repositorio falso.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/repositories/deposito_repository.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

final class _Repo implements DepositoRepository {
  Failure? respuesta;
  final guardados = <Deposito>[];

  @override
  Future<Either<Failure, DepositoRegistrado>> registrar(Deposito deposito) async {
    guardados.add(deposito);
    final falla = respuesta;
    return falla == null ? Right(DepositoRegistrado(deposito: deposito)) : Left(falla);
  }

  @override
  Future<Either<Failure, List<Deposito>>> todos() async => const Right([]);
}

void main() {
  // 30/10/2026 02:00 en Montevideo (UTC-3) = 05:00 UTC.
  final ahora = DateTime.utc(2026, 10, 30, 5);
  late _Repo repo;

  setUp(() => repo = _Repo());

  RegistrarDepositoUseCase caso() => RegistrarDepositoUseCase(repo, ahora: () => ahora);

  RegistrarDepositoParams params({
    String depositoId = 'd-1',
    String colportorId = 'col-1',
    int monto = 180000,
    DestinoDeDeposito destino = DestinoDeDeposito.banco,
    ConceptoDeDeposito concepto = ConceptoDeDeposito.casaEditora,
    DateTime? fecha,
    String? campaniaId,
    String? ticketId = 't-1',
  }) => RegistrarDepositoParams(
    depositoId: depositoId,
    colportorId: colportorId,
    montoCentavos: monto,
    destino: destino,
    concepto: concepto,
    fecha: fecha,
    campaniaId: campaniaId,
    ticketId: ticketId,
  );

  Failure? falla(Either<Failure, DepositoRegistrado> r) => r.fold((f) => f, (_) => null);

  group('lo que se guarda', () {
    test(
      'dado un depósito en el banco con su ticket, cuando se registra, guarda el monto, el destino, '
      'el concepto, el ticket y quién lo hizo, con la hora de ahora',
      () async {
        final r = await caso()(params());

        final d = r.getOrElse(() => throw StateError('falló')).deposito;
        expect(d.id, 'd-1');
        expect(d.montoCentavos, 180000);
        expect(d.destino, DestinoDeDeposito.banco);
        expect(d.concepto, ConceptoDeDeposito.casaEditora);
        expect(d.ticketId, 't-1');
        expect(d.campaniaId, isNull);
        expect(d.fecha, ahora);
        expect(d.auditoria.createdAt, ahora);
        expect(d.auditoria.updatedAt, ahora);
        expect(d.auditoria.createdBy, 'col-1');
        expect(d.auditoria.syncVersion, 0);
        expect(repo.guardados, hasLength(1));
      },
    );

    test('dado una hora local, cuando se registra, la fecha se guarda en UTC', () async {
      final r = await caso()(params(fecha: DateTime(2026, 10, 29, 10)));

      final d = r.getOrElse(() => throw StateError('falló')).deposito;
      expect(d.fecha.isUtc, isTrue);
      expect(d.fecha, DateTime(2026, 10, 29, 10).toUtc());
    });

    test('dado un depósito en la oficina, cuando se registra, lleva su ticket', () async {
      final r = await caso()(params(destino: DestinoDeDeposito.oficina));

      expect(r.getOrElse(() => throw StateError('falló')).deposito.ticketId, 't-1');
    });

    test(
      'dado un retiro por el coordinador sin ticket, cuando se registra, queda sin ticket',
      () async {
        final r = await caso()(
          params(destino: DestinoDeDeposito.retiroCoordinador, ticketId: null),
        );

        final d = r.getOrElse(() => throw StateError('falló')).deposito;
        expect(d.destino, DestinoDeDeposito.retiroCoordinador);
        expect(d.ticketId, isNull);
      },
    );

    test('dado el alquiler con su campaña, cuando se registra, guarda la campaña', () async {
      final r = await caso()(
        params(concepto: ConceptoDeDeposito.alquiler, campaniaId: 'camp-1', monto: 150000),
      );

      final d = r.getOrElse(() => throw StateError('falló')).deposito;
      expect(d.concepto, ConceptoDeDeposito.alquiler);
      expect(d.campaniaId, 'camp-1');
    });

    test(
      'dado la casa editora con una campaña, cuando se registra, la guarda (puede ir o no)',
      () async {
        final r = await caso()(params(campaniaId: 'camp-1'));

        expect(r.getOrElse(() => throw StateError('falló')).deposito.campaniaId, 'camp-1');
      },
    );

    test('dado ids y textos con espacios de más, cuando se registra, los recorta', () async {
      final r = await caso()(
        params(depositoId: '  d-1 ', colportorId: ' col-1  ', ticketId: ' t-1 '),
      );

      final d = r.getOrElse(() => throw StateError('falló')).deposito;
      expect(d.id, 'd-1');
      expect(d.auditoria.createdBy, 'col-1');
      expect(d.ticketId, 't-1');
    });
  });

  group('lo que no se guarda', () {
    test('dado un id o un colportor vacío, cuando se registra, no guarda nada', () async {
      for (final p in [params(depositoId: ' '), params(colportorId: '')]) {
        final f = falla(await caso()(p));

        expect(f, isA<FailureDepositoNoGuardado>());
        expect((f! as FailureDepositoNoGuardado).causa, 'faltan_ids');
      }
      expect(repo.guardados, isEmpty);
    });

    test(
      'dado un monto en cero, negativo o más grande que el entero de la app, cuando se registra, '
      'es FailureDepositoMontoInvalido y no guarda nada',
      () async {
        for (final monto in [0, -1, RegistrarDepositoUseCase.maximoCentavos + 1]) {
          expect(falla(await caso()(params(monto: monto))), isA<FailureDepositoMontoInvalido>());
        }
        expect(repo.guardados, isEmpty);
      },
    );

    test('dado el monto más grande que entra, cuando se registra, lo guarda', () async {
      final r = await caso()(params(monto: RegistrarDepositoUseCase.maximoCentavos));

      expect(r.isRight(), isTrue);
    });

    test(
      'dado una fecha de mañana en Montevideo, cuando se registra, es FailureDepositoFechaInvalida',
      () async {
        final f = falla(await caso()(params(fecha: DateTime.utc(2026, 10, 31, 3))));

        expect(f, isA<FailureDepositoFechaInvalida>());
        expect(repo.guardados, isEmpty);
      },
    );

    test(
      'dado hoy a la noche en Montevideo (ya es mañana en UTC), cuando se registra, es válido',
      () async {
        // 30/10 23:30 en Montevideo = 31/10 02:30 UTC: el mismo día de Montevideo que `ahora` (30/10).
        final r = await caso()(params(fecha: DateTime.utc(2026, 10, 31, 2, 30)));

        expect(r.isRight(), isTrue);
      },
    );

    test('dado el banco o la oficina sin ticket (o con uno en blanco), cuando se registra, es '
        'FailureDepositoSinTicket', () async {
      for (final destino in [DestinoDeDeposito.banco, DestinoDeDeposito.oficina]) {
        for (final ticket in [null, '', '   ']) {
          expect(
            falla(await caso()(params(destino: destino, ticketId: ticket))),
            isA<FailureDepositoSinTicket>(),
          );
        }
      }
      expect(repo.guardados, isEmpty);
    });

    test('dado un retiro por el coordinador con ticket, cuando se registra, es '
        'FailureDepositoRetiroConTicket', () async {
      final f = falla(await caso()(params(destino: DestinoDeDeposito.retiroCoordinador)));

      expect(f, isA<FailureDepositoRetiroConTicket>());
      expect(repo.guardados, isEmpty);
    });

    test(
      'dado el alquiler sin campaña (o en blanco), cuando se registra, es FailureDepositoSinCampania',
      () async {
        for (final campania in [null, '', '  ']) {
          expect(
            falla(
              await caso()(params(concepto: ConceptoDeDeposito.alquiler, campaniaId: campania)),
            ),
            isA<FailureDepositoSinCampania>(),
          );
        }
        expect(repo.guardados, isEmpty);
      },
    );
  });

  group('lo que dice el repositorio', () {
    test(
      'dado un repositorio que falla, cuando se registra, devuelve esa falla tal cual',
      () async {
        repo.respuesta = const FailureDepositoTicketYaUsado();

        final f = falla(await caso()(params()));

        expect(f, isA<FailureDepositoTicketYaUsado>());
      },
    );

    test(
      'dado el mismo id dos veces (doble toque), cuando se registra, el id llega igual las dos veces '
      'para que el repositorio lo reconozca',
      () async {
        await caso()(params());
        await caso()(params());

        expect(repo.guardados.map((d) => d.id), ['d-1', 'd-1']);
      },
    );
  });

  group('las entidades', () {
    test('dado el destino, cuando se pregunta si lleva ticket, solo el retiro no lo lleva', () {
      expect(DestinoDeDeposito.banco.llevaTicket, isTrue);
      expect(DestinoDeDeposito.oficina.llevaTicket, isTrue);
      expect(DestinoDeDeposito.retiroCoordinador.llevaTicket, isFalse);
    });

    test(
      'dado una fecha con microsegundos, cuando se arma el depósito, se trunca al milisegundo en UTC',
      () {
        final d = Deposito(
          id: 'd-1',
          montoCentavos: 1,
          fecha: DateTime.utc(2026, 10, 30, 5, 0, 0, 123, 456),
          destino: DestinoDeDeposito.retiroCoordinador,
          concepto: ConceptoDeDeposito.casaEditora,
          auditoria: Auditoria(createdAt: ahora, updatedAt: ahora),
        );

        expect(d.fecha, DateTime.utc(2026, 10, 30, 5, 0, 0, 123));
      },
    );
  });
}
