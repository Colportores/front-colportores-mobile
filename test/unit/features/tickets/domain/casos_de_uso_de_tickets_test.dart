// Los casos de uso de los tickets (HU-COB-007, #426) contra un repositorio falso.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/borrar_copia_local_de_ticket_use_case.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/registrar_ticket_use_case.dart';
import 'package:colportores_mobile/features/tickets/domain/usecases/subir_fotos_de_tickets_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../helpers/tickets_falsos.dart';

/// Un repositorio que anota lo que le piden y devuelve lo que se le guionó.
final class _RepoFalso implements TicketRepository {
  final registrados = <({Ticket ticket, int bytes, String? cobroId})>[];
  List<FotoPorSubir> porSubir = [];
  Uint8List? bytes = fotoDePrueba();
  final marcadas = <(String, String)>[];
  final intentos = <(String, String, bool)>[];
  final borradas = <String>[];
  Failure? falla;
  Failure? fallaAlMarcar;

  @override
  Future<Either<Failure, TicketRegistrado>> registrar(
    Ticket ticket, {
    required Uint8List foto,
    required TipoDeImagen tipoDeImagen,
    String? cobroId,
  }) async {
    registrados.add((ticket: ticket, bytes: foto.length, cobroId: cobroId));
    final f = falla;
    if (f != null) return Left(f);
    return Right(TicketRegistrado(ticket: ticket, foto: fotoLocalDePrueba(ticket.id)));
  }

  @override
  Future<Either<Failure, List<FotoPorSubir>>> fotosPorSubir() async {
    final f = falla;
    return f != null ? Left(f) : Right(porSubir);
  }

  @override
  Stream<int> cantidadDeFotosPorSubir() => const Stream.empty();

  @override
  Future<Either<Failure, Uint8List?>> bytesDeLaFoto(String ticketId) async => Right(bytes);

  @override
  Future<Either<Failure, Ticket>> marcarFotoSubida(String ticketId, String ruta) async {
    marcadas.add((ticketId, ruta));
    final f = fallaAlMarcar;
    return f != null ? Left(f) : Right(ticketDePrueba(ticketId, urlCloud: ruta));
  }

  @override
  Future<Either<Failure, Unit>> anotarIntentoFallido(
    String ticketId, {
    required String codigo,
    required bool definitivo,
  }) async {
    intentos.add((ticketId, codigo, definitivo));
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> borrarCopiaLocal(String ticketId) async {
    borradas.add(ticketId);
    final f = falla;
    return f != null ? Left(f) : const Right(unit);
  }

  @override
  Stream<TicketRegistrado?> observarTicket(String ticketId) => const Stream.empty();

  @override
  Stream<Set<String>> cobrosConTicketPendiente() => const Stream.empty();
}

RegistrarTicketParams _params({
  String ticketId = 't-1',
  TipoDeTicket tipo = TipoDeTicket.cobroTarjeta,
  int monto = 150000,
  DateTime? fecha,
  String? autorizacion = ' 123456 ',
  TipoDeTarjeta? tarjeta = TipoDeTarjeta.credito,
  String? marca = ' Visa ',
  Uint8List? foto,
  String? cobroId = 'c-1',
}) => RegistrarTicketParams(
  ticketId: ticketId,
  colportorId: 'col-1',
  tipo: tipo,
  montoCentavos: monto,
  foto: foto ?? fotoDePrueba(),
  tipoDeImagen: TipoDeImagen.jpeg,
  fecha: fecha,
  numeroAutorizacion: autorizacion,
  tarjetaTipo: tarjeta,
  tarjetaMarca: marca,
  cobroId: cobroId,
);

void main() {
  group('RegistrarTicketUseCase', () {
    late _RepoFalso repo;
    late RegistrarTicketUseCase registrar;

    setUp(() {
      repo = _RepoFalso();
      registrar = RegistrarTicketUseCase(repo, ahora: () => ahoraTicket);
    });

    test(
      'dado un ticket de tarjeta completo, cuando se registra, guarda los cinco datos limpios, con '
      'el colportor como creador, la foto y el cobro',
      () async {
        final r = await registrar(_params());

        expect(r.isRight(), isTrue);
        final guardado = repo.registrados.single;
        expect(guardado.ticket.id, 't-1');
        expect(guardado.ticket.tipo, TipoDeTicket.cobroTarjeta);
        expect(guardado.ticket.montoCentavos, 150000);
        expect(guardado.ticket.fecha, ahoraTicket);
        expect(guardado.ticket.numeroAutorizacion, '123456');
        expect(guardado.ticket.tarjetaTipo, TipoDeTarjeta.credito);
        expect(guardado.ticket.tarjetaMarca, 'Visa');
        expect(guardado.ticket.estado, EstadoDeTicket.pendiente);
        expect(guardado.ticket.urlCloud, isNull);
        expect(guardado.ticket.auditoria.createdBy, 'col-1');
        expect(guardado.ticket.auditoria.createdAt, ahoraTicket);
        expect(guardado.bytes, 1000);
        expect(guardado.cobroId, 'c-1');
      },
    );

    test('«Falta el número de autorización»: en blanco o vacío en un ticket de tarjeta no guarda '
        'nada', () async {
      for (final vacio in [null, '', '   ']) {
        final r = await registrar(_params(autorizacion: vacio));
        expect(r.swap().toOption().toNullable(), isA<FailureTicketSinAutorizacion>());
      }
      expect(repo.registrados, isEmpty);
    });

    test('al ticket de tarjeta sin crédito ni débito no lo guarda', () async {
      final r = await registrar(_params(tarjeta: null));

      expect(r.swap().toOption().toNullable(), isA<FailureTicketSinTarjeta>());
      expect(repo.registrados, isEmpty);
    });

    test('monto cero, negativo o enorme: no guarda', () async {
      for (final monto in [0, -1, 2147483648]) {
        final r = await registrar(_params(monto: monto));
        expect(
          r.swap().toOption().toNullable(),
          isA<FailureTicketMontoInvalido>(),
          reason: '$monto',
        );
      }
      expect(repo.registrados, isEmpty);
    });

    test('fecha de mañana: no guarda; la de hoy a la noche (Montevideo) sí', () async {
      final manana = await registrar(_params(fecha: ahoraTicket.add(const Duration(days: 1))));
      expect(manana.swap().toOption().toNullable(), isA<FailureTicketFechaInvalida>());

      final hoy = await RegistrarTicketUseCase(
        repo,
        ahora: () => DateTime.utc(2026, 10, 31, 2, 30),
      )(_params(fecha: DateTime.utc(2026, 10, 31, 2, 0)));
      expect(hoy.isRight(), isTrue);
    });

    test('autorización o marca de más de 40 caracteres: no guarda', () async {
      final a = await registrar(_params(autorizacion: '1' * 41));
      final m = await registrar(_params(marca: 'V' * 41));

      expect(a.swap().toOption().toNullable(), isA<FailureTicketTextoLargo>());
      expect(m.swap().toOption().toNullable(), isA<FailureTicketTextoLargo>());
      expect(repo.registrados, isEmpty);
    });

    test('foto vacía o de más de 2 MiB: no guarda', () async {
      final vacia = await registrar(_params(foto: Uint8List(0)));
      final grande = await registrar(_params(foto: Uint8List(2 * 1024 * 1024 + 1)));

      expect(vacia.swap().toOption().toNullable(), isA<FailureTicketFotoInvalida>());
      expect(grande.swap().toOption().toNullable(), isA<FailureTicketFotoInvalida>());
      expect(repo.registrados, isEmpty);
    });

    test('el ticket de un depósito no pide tarjeta ni autorización y no guarda los datos de la '
        'tarjeta aunque lleguen', () async {
      final r = await registrar(
        _params(
          tipo: TipoDeTicket.deposito,
          autorizacion: null,
          tarjeta: TipoDeTarjeta.debito,
          cobroId: null,
        ),
      );

      expect(r.isRight(), isTrue);
      final t = repo.registrados.single.ticket;
      expect(t.tarjetaTipo, isNull);
      expect(t.tarjetaMarca, isNull);
    });

    test('un ticket que no es de tarjeta no se liga a un cobro', () async {
      final r = await registrar(
        _params(tipo: TipoDeTicket.deposito, autorizacion: null, tarjeta: null),
      );

      expect(r.swap().toOption().toNullable(), isA<FailureTicketCobroInvalido>());
      expect(repo.registrados, isEmpty);
    });

    test('ids vacíos: no guarda', () async {
      final r = await registrar(_params(ticketId: ' '));

      expect(r.swap().toOption().toNullable(), isA<FailureTicketNoGuardado>());
    });

    test('lo que devuelve el repositorio pasa tal cual (falla)', () async {
      repo.falla = const FailureTicketNoGuardado(causa: 'X');

      final r = await registrar(_params());

      expect(r.swap().toOption().toNullable(), const FailureTicketNoGuardado(causa: 'X'));
    });
  });

  group('SubirFotosDeTicketsUseCase', () {
    late _RepoFalso repo;

    FotoPorSubir pendiente(String id) =>
        FotoPorSubir(ticket: ticketDePrueba(id, syncVersion: 1), foto: fotoLocalDePrueba(id));

    setUp(() {
      repo = _RepoFalso()..porSubir = [pendiente('t-1'), pendiente('t-2')];
    });

    Future<ResumenDeSubidaDeFotos> correr(ServidorDeFotosGuionado servidor) async {
      final r = await SubirFotosDeTicketsUseCase(repo, servidor)(const NoParams());
      return r.getOrElse(() => throw StateError('falló'));
    }

    test('«Subida exitosa»: sube cada foto con su tipo y su tamaño y guarda la ruta que devolvió '
        'el servidor', () async {
      final servidor = ServidorDeFotosGuionado([
        const FotoSubida('u/t-1.jpg'),
        const FotoSubida('u/t-2.jpg'),
      ]);

      final resumen = await correr(servidor);

      expect(resumen, const ResumenDeSubidaDeFotos(subidas: 2));
      expect(servidor.pedidos.map((p) => (p.ticketId, p.tipo, p.bytes)), [
        ('t-1', TipoDeImagen.jpeg, 1000),
        ('t-2', TipoDeImagen.jpeg, 1000),
      ]);
      expect(repo.marcadas, [('t-1', 'u/t-1.jpg'), ('t-2', 'u/t-2.jpg')]);
    });

    test('el servidor ya tenía la foto (409): se toma como subida', () async {
      final servidor = ServidorDeFotosGuionado([
        const FotoYaEstaba('u/t-1.jpg'),
        const FotoSubida('u/t-2.jpg'),
      ]);

      final resumen = await correr(servidor);

      expect(resumen.subidas, 2);
      expect(repo.marcadas.first, ('t-1', 'u/t-1.jpg'));
    });

    test('«Sin red»: la foto queda pendiente, se anota el intento y las otras siguen', () async {
      final servidor = ServidorDeFotosGuionado([
        const SubidaFallida(codigo: 'red', reintentable: true),
        const FotoSubida('u/t-2.jpg'),
      ]);

      final resumen = await correr(servidor);

      expect(resumen, const ResumenDeSubidaDeFotos(subidas: 1, pendientes: 1));
      expect(repo.intentos, [('t-1', 'red', false)]);
      expect(repo.marcadas, [('t-2', 'u/t-2.jpg')]);
    });

    test('un rechazo definitivo (foto muy pesada) no se reintenta', () async {
      final servidor = ServidorDeFotosGuionado([
        const SubidaFallida(codigo: 'foto_muy_pesada', reintentable: false),
        const FotoSubida('u/t-2.jpg'),
      ]);

      final resumen = await correr(servidor);

      expect(resumen, const ResumenDeSubidaDeFotos(subidas: 1, rechazadas: 1));
      expect(repo.intentos, [('t-1', 'foto_muy_pesada', true)]);
    });

    test('si la copia local ya no está, se anota como rechazada y no llama al servidor', () async {
      repo.bytes = null;
      final servidor = ServidorDeFotosGuionado([const FotoSubida('u/x.jpg')]);

      final resumen = await correr(servidor);

      expect(resumen, const ResumenDeSubidaDeFotos(rechazadas: 2));
      expect(servidor.pedidos, isEmpty);
      expect(repo.intentos.first, ('t-1', 'copia_local_ausente', true));
    });

    test('si no puede guardar la ruta, la foto cuenta como pendiente (se reintenta; el servidor '
        'contesta 409 y se toma como subida)', () async {
      repo.fallaAlMarcar = const FailureTicketNoGuardado();
      final servidor = ServidorDeFotosGuionado([const FotoSubida('u/t-1.jpg')]);

      final resumen = await correr(servidor);

      expect(resumen, const ResumenDeSubidaDeFotos(pendientes: 2));
    });

    test('sin nada para subir, no llama al servidor', () async {
      repo.porSubir = [];
      final servidor = ServidorDeFotosGuionado([const FotoSubida('x')]);

      expect(await correr(servidor), const ResumenDeSubidaDeFotos());
      expect(servidor.pedidos, isEmpty);
    });

    test('si no puede leer la lista, devuelve la falla', () async {
      repo.falla = const FailureTicketNoDisponible();

      final r = await SubirFotosDeTicketsUseCase(
        repo,
        ServidorDeFotosGuionado([const FotoSubida('x')]),
      )(const NoParams());

      expect(r.swap().toOption().toNullable(), isA<FailureTicketNoDisponible>());
    });

    test('dos pasadas a la vez no suben dos veces la misma foto', () async {
      repo.porSubir = [pendiente('t-1')];
      final liberar = Completer<void>();
      final servidor = ServidorDeFotosGuionado([const FotoSubida('u/t-1.jpg')])
        ..espera = liberar.future;
      final caso = SubirFotosDeTicketsUseCase(repo, servidor);

      final primera = caso(const NoParams());
      await pumpEventQueue();
      final segunda = await caso(const NoParams());
      liberar.complete();
      final resultado = await primera;

      expect(segunda.getOrElse(() => throw StateError('')), const ResumenDeSubidaDeFotos());
      expect(resultado.getOrElse(() => throw StateError('')).subidas, 1);
      expect(servidor.pedidos, hasLength(1));
    });

    test('después de una pasada que falló a mitad, la siguiente puede correr', () async {
      repo.falla = const FailureTicketNoDisponible();
      final caso = SubirFotosDeTicketsUseCase(
        repo,
        ServidorDeFotosGuionado([const FotoSubida('x')]),
      );
      await caso(const NoParams());
      repo
        ..falla = null
        ..porSubir = [pendiente('t-1')];

      final r = await caso(const NoParams());

      expect(r.getOrElse(() => throw StateError('')).subidas, 1);
    });
  });

  group('BorrarCopiaLocalDeTicketUseCase', () {
    test('le pide al repositorio borrar la copia del ticket', () async {
      final repo = _RepoFalso();

      final r = await BorrarCopiaLocalDeTicketUseCase(repo)('t-1');

      expect(r.isRight(), isTrue);
      expect(repo.borradas, ['t-1']);
    });

    test('con la foto sin subir, devuelve la falla que explica por qué', () async {
      final repo = _RepoFalso()..falla = const FailureTicketCopiaSinSubir();

      final r = await BorrarCopiaLocalDeTicketUseCase(repo)('t-1');

      expect(r.swap().toOption().toNullable(), isA<FailureTicketCopiaSinSubir>());
    });
  });
}
