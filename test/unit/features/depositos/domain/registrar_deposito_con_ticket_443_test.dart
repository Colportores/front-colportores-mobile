// Test de dominio: Dart puro. «Registrar depósito» con el ticket del banco en un solo paso (HU-CTA-004,
// decisión «Paso ticket», #443), con repositorios falsos y una transacción que anota si se revirtió.
import 'dart:typed_data';

import 'package:colportores_mobile/core/domain/transaccion_local.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/totales_de_depositos.dart';
import 'package:colportores_mobile/features/depositos/domain/repositories/deposito_repository.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/registrar_ticket_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../helpers/tickets_falsos.dart';

/// Lo que pasó, en orden: «ticket», «deposito», «revertida».
final _pasos = <String>[];

final class _Transaccion implements TransaccionLocal {
  var corridas = 0;

  @override
  Future<T> correr<T>(Future<T> Function() cuerpo) async {
    corridas++;
    try {
      return await cuerpo();
    } on Object {
      _pasos.add('revertida');
      rethrow;
    }
  }
}

final class _Tickets implements TicketRepository {
  _Tickets(this.almacen);

  /// Donde «escribe» la foto, como el repositorio de verdad.
  final AlmacenDeFotosEnMemoria almacen;
  Failure? respuesta;
  var yaEstaba = false;
  Object? lanzar;
  final guardados = <({Ticket ticket, Uint8List foto})>[];

  @override
  Future<Either<Failure, TicketRegistrado>> registrar(
    Ticket ticket, {
    required Uint8List foto,
    required TipoDeImagen tipoDeImagen,
    String? cobroId,
  }) async {
    final error = lanzar;
    if (error != null) throw error;
    _pasos.add('ticket');
    guardados.add((ticket: ticket, foto: foto));
    final falla = respuesta;
    if (falla != null) return Left(falla);
    final ruta = await almacen.guardar(ticket.id, tipoDeImagen, foto);
    return Right(
      TicketRegistrado(
        yaEstaba: yaEstaba,
        ticket: ticket,
        foto: FotoLocalDeTicket(
          ticketId: ticket.id,
          tipoDeImagen: tipoDeImagen,
          bytes: foto.length,
          estado: EstadoDeSubida.pendiente,
          creadaEn: ticket.auditoria.createdAt,
          rutaLocal: ruta,
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Depositos implements DepositoRepository {
  Failure? respuesta;
  final guardados = <Deposito>[];

  @override
  Future<Either<Failure, DepositoRegistrado>> registrar(Deposito deposito) async {
    _pasos.add('deposito');
    guardados.add(deposito);
    final falla = respuesta;
    return falla == null ? Right(DepositoRegistrado(deposito: deposito)) : Left(falla);
  }

  @override
  Future<Either<Failure, List<Deposito>>> todos() async => const Right([]);

  @override
  Stream<List<Deposito>> observar() => const Stream.empty();

  @override
  Future<Either<Failure, TotalesDeDepositos>> totales() async =>
      const Right(TotalesDeDepositos(validadoCentavos: 0, porValidarCentavos: 0));
}

void main() {
  // 30/10/2026 02:00 en Montevideo (UTC-3) = 05:00 UTC.
  final ahora = DateTime.utc(2026, 10, 30, 5);
  final foto = Uint8List.fromList(List.generate(500, (i) => i % 200));
  late _Transaccion transaccion;
  late AlmacenDeFotosEnMemoria almacen;
  late _Tickets tickets;
  late _Depositos depositos;
  late RegistrarDepositoConTicketUseCase caso;

  setUp(() {
    _pasos.clear();
    transaccion = _Transaccion();
    almacen = AlmacenDeFotosEnMemoria();
    tickets = _Tickets(almacen);
    depositos = _Depositos();
    caso = RegistrarDepositoConTicketUseCase(
      transaccion: transaccion,
      registrarTicket: RegistrarTicketUseCase(tickets, ahora: () => ahora),
      registrarDeposito: RegistrarDepositoUseCase(depositos, ahora: () => ahora),
      almacen: almacen,
      ahora: () => ahora,
    );
  });

  RegistrarDepositoConTicketParams params({
    String depositoId = 'd-1',
    String ticketId = 't-1',
    int monto = 180000,
    DestinoDeDeposito destino = DestinoDeDeposito.banco,
    ConceptoDeDeposito concepto = ConceptoDeDeposito.casaEditora,
    DateTime? fecha,
    String? campaniaId,
    Uint8List? conFoto,
    bool sinFoto = false,
    String? referencia,
  }) => RegistrarDepositoConTicketParams(
    depositoId: depositoId,
    ticketId: ticketId,
    colportorId: 'col-1',
    montoCentavos: monto,
    destino: destino,
    concepto: concepto,
    fecha: fecha,
    campaniaId: campaniaId,
    foto: sinFoto ? null : (conFoto ?? foto),
    referencia: referencia,
  );

  group('banco u oficina: el ticket y el depósito en un solo paso', () {
    test('guarda primero el ticket (tipo depósito, mismo monto y fecha) y después el depósito que '
        'lo nombra, en una sola transacción', () async {
      final r = await caso(params(referencia: ' 004512 '));

      expect(r.isRight(), isTrue);
      expect(_pasos, ['ticket', 'deposito']);
      expect(transaccion.corridas, 1);
      final ticket = tickets.guardados.single.ticket;
      final deposito = depositos.guardados.single;
      expect(ticket.id, 't-1');
      expect(ticket.tipo, TipoDeTicket.deposito);
      expect(ticket.montoCentavos, 180000);
      expect(ticket.fecha, ahora);
      expect(
        ticket.numeroAutorizacion,
        '004512',
        reason: 'la referencia es el número de operación',
      );
      expect(ticket.tarjetaTipo, isNull);
      expect(tickets.guardados.single.foto, foto);
      expect(deposito.id, 'd-1');
      expect(deposito.ticketId, 't-1');
      expect(deposito.fecha, ahora);
      expect(deposito.montoCentavos, 180000);
      expect(deposito.estado, EstadoDeDeposito.porValidar);
    });

    test('la oficina también lleva el ticket', () async {
      final r = await caso(params(destino: DestinoDeDeposito.oficina));
      expect(r.isRight(), isTrue);
      expect(depositos.guardados.single.destino, DestinoDeDeposito.oficina);
      expect(depositos.guardados.single.ticketId, 't-1');
    });

    test('un día pasado va igual al ticket y al depósito', () async {
      final ayer = DateTime.utc(2026, 10, 28, 15);
      await caso(params(fecha: ayer));
      expect(tickets.guardados.single.ticket.fecha, ayer);
      expect(depositos.guardados.single.fecha, ayer);
    });

    test('sin foto no guarda nada: el depósito en el banco se registra con el ticket', () async {
      final r = await caso(params(sinFoto: true));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoSinTicket()));
      expect(_pasos, isEmpty);
      expect(transaccion.corridas, 0);
    });

    test('una foto vacía tampoco sirve', () async {
      final r = await caso(params(conFoto: Uint8List(0)));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoSinTicket()));
      expect(_pasos, isEmpty);
    });

    test('sin id del ticket no guarda nada', () async {
      final r = await caso(params(ticketId: '  '));
      expect(r.fold((f) => f, (_) => null), isA<FailureDepositoNoGuardado>());
      expect(_pasos, isEmpty);
    });

    test('si el depósito no entra, el ticket tampoco queda: se revierte todo', () async {
      depositos.respuesta = const FailureDepositoTicketYaUsado();

      final r = await caso(params());

      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoTicketYaUsado()));
      expect(_pasos, ['ticket', 'deposito', 'revertida']);
      expect(almacen.archivos, isEmpty, reason: 'la copia de la foto se borra con la reversión');
    });

    test('si borrar la copia falla, la respuesta es la misma', () async {
      depositos.respuesta = const FailureDepositoTicketYaUsado();
      almacen.fallarAlBorrarCon = StateError('disco');

      final r = await caso(params());

      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoTicketYaUsado()));
    });

    test('la copia de un ticket que ya estaba (reintento) no se borra si algo falla', () async {
      tickets.yaEstaba = true;
      depositos.respuesta = const FailureDepositoNoGuardado();

      await caso(params());

      expect(almacen.archivos, isNotEmpty);
    });

    test(
      'si el ticket no se guarda, no se intenta el depósito y la falla habla del depósito',
      () async {
        tickets.respuesta = const FailureTicketNoGuardado(causa: 'SqliteException');

        final r = await caso(params());

        final falla = r.fold((f) => f, (_) => null);
        expect(falla, isA<FailureDepositoNoGuardado>());
        expect((falla! as FailureDepositoNoGuardado).causa, 'SqliteException');
        expect(falla.mensaje, 'No pudimos registrar el depósito. No cambió nada.');
        expect(_pasos, ['ticket', 'revertida']);
      },
    );

    test('una foto de más de 2 MiB la rechaza el ticket, sin escribir nada', () async {
      final grande = Uint8List(2 * 1024 * 1024 + 1)..fillRange(0, 10, 1);
      final r = await caso(params(conFoto: grande));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureTicketFotoInvalida()));
      expect(depositos.guardados, isEmpty);
    });

    test('un número de operación de más de 40 caracteres lo rechaza el ticket', () async {
      final r = await caso(params(referencia: 'x' * 41));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureTicketTextoLargo()));
      expect(depositos.guardados, isEmpty);
    });

    test('una excepción en el medio se revierte y se dice como «no pudimos registrar»', () async {
      tickets.lanzar = StateError('sin base');

      final r = await caso(params());

      final falla = r.fold((f) => f, (_) => null);
      expect(falla, isA<FailureDepositoNoGuardado>());
      expect((falla! as FailureDepositoNoGuardado).causa, 'StateError');
      expect(_pasos, ['revertida']);
    });
  });

  group('retiro por el coordinador: sin ticket', () {
    test('guarda solo el depósito, sin ticket', () async {
      final r = await caso(params(destino: DestinoDeDeposito.retiroCoordinador, sinFoto: true));

      expect(r.isRight(), isTrue);
      expect(_pasos, ['deposito']);
      expect(tickets.guardados, isEmpty);
      expect(depositos.guardados.single.ticketId, isNull);
      expect(depositos.guardados.single.destino, DestinoDeDeposito.retiroCoordinador);
    });

    test('un retiro con foto no se guarda: no lleva ticket', () async {
      final r = await caso(params(destino: DestinoDeDeposito.retiroCoordinador));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoRetiroConTicket()));
      expect(_pasos, isEmpty);
    });

    test('el retiro no necesita id de ticket', () async {
      final r = await caso(
        params(destino: DestinoDeDeposito.retiroCoordinador, sinFoto: true, ticketId: ''),
      );
      expect(r.isRight(), isTrue);
    });
  });

  group('las reglas del depósito se miran antes de escribir el ticket', () {
    test('monto en cero', () async {
      final r = await caso(params(monto: 0));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoMontoInvalido()));
      expect(_pasos, isEmpty);
    });

    test('fecha de mañana (día de Montevideo)', () async {
      final r = await caso(params(fecha: DateTime.utc(2026, 10, 31, 4)));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoFechaInvalida()));
      expect(_pasos, isEmpty);
    });

    test('alquiler sin campaña', () async {
      final r = await caso(params(concepto: ConceptoDeDeposito.alquiler));
      expect(r, const Left<Failure, DepositoRegistrado>(FailureDepositoSinCampania()));
      expect(_pasos, isEmpty);
    });

    test('alquiler con su campaña', () async {
      final r = await caso(params(concepto: ConceptoDeDeposito.alquiler, campaniaId: 'camp-1'));
      expect(r.isRight(), isTrue);
      expect(depositos.guardados.single.campaniaId, 'camp-1');
      expect(depositos.guardados.single.concepto, ConceptoDeDeposito.alquiler);
    });
  });

  group('fallas del ticket dichas como del depósito', () {
    test('monto y fecha del ticket pasan a las del depósito; las demás quedan', () async {
      tickets.respuesta = const FailureTicketMontoInvalido();
      expect(
        (await caso(params())).fold((f) => f, (_) => null),
        const FailureDepositoMontoInvalido(),
      );
      tickets.respuesta = const FailureTicketFechaInvalida();
      expect(
        (await caso(params())).fold((f) => f, (_) => null),
        const FailureDepositoFechaInvalida(),
      );
      tickets.respuesta = const FailureTicketCobroInvalido();
      expect(
        (await caso(params())).fold((f) => f, (_) => null),
        const FailureTicketCobroInvalido(),
      );
    });
  });

  test('RegistrarDepositoUseCase.validar no escribe y dice lo mismo que el caso de uso', () {
    const base = RegistrarDepositoParams(
      depositoId: 'd-1',
      colportorId: 'col-1',
      montoCentavos: 100,
      destino: DestinoDeDeposito.banco,
      concepto: ConceptoDeDeposito.casaEditora,
      ticketId: 't-1',
    );
    expect(RegistrarDepositoUseCase.validar(base, ahora), isNull);
    expect(
      RegistrarDepositoUseCase.validar(
        const RegistrarDepositoParams(
          depositoId: ' ',
          colportorId: 'col-1',
          montoCentavos: 100,
          destino: DestinoDeDeposito.banco,
          concepto: ConceptoDeDeposito.casaEditora,
          ticketId: 't-1',
        ),
        ahora,
      ),
      isA<FailureDepositoNoGuardado>(),
    );
    expect(_pasos, isEmpty);
  });

  test('los parámetros se comparan por valor', () {
    expect(params(), params());
    expect(params(), isNot(params(monto: 1)));
  });
}
