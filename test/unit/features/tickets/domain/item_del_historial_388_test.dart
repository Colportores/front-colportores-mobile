// «Mis tickets» (vista 38B, HU-COB-009, #388): cómo se arma cada fila del historial con un depósito y
// su ticket, un retiro sin ticket o un ticket suelto, y qué filtro acepta cada una.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/item_del_historial.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:equatable/equatable.dart';
import 'package:test/test.dart';

import '../../../../helpers/tickets_falsos.dart';

final _fecha = DateTime.utc(2026, 11, 10, 15);

Deposito _deposito({
  String id = 'd-1',
  DestinoDeDeposito destino = DestinoDeDeposito.banco,
  ConceptoDeDeposito concepto = ConceptoDeDeposito.casaEditora,
  String? ticketId = 't-1',
  int syncVersion = 3,
  DateTime? validadoEn,
  DateTime? rechazadoEn,
  String? motivoRechazo,
  DateTime? anuladoAt,
}) => Deposito(
  id: id,
  montoCentavos: 480000,
  fecha: _fecha,
  destino: destino,
  concepto: concepto,
  campaniaId: concepto == ConceptoDeDeposito.alquiler ? 'camp-1' : null,
  ticketId: destino.llevaTicket ? ticketId : null,
  validadoEn: validadoEn,
  rechazadoEn: rechazadoEn,
  motivoRechazo: motivoRechazo,
  anuladoAt: anuladoAt,
  auditoria: Auditoria(createdAt: _fecha, updatedAt: _fecha, syncVersion: syncVersion),
);

Ticket _ticket({
  String id = 't-1',
  int syncVersion = 3,
  EstadoDeTicket estado = EstadoDeTicket.pendiente,
  String? motivo,
  DateTime? revisadoEn,
  TipoDeTicket tipo = TipoDeTicket.deposito,
  String? urlCloud,
}) => Ticket(
  id: id,
  tipo: tipo,
  montoCentavos: 480000,
  fecha: _fecha,
  numeroAutorizacion: '004512',
  tarjetaTipo: TipoDeTarjeta.debito,
  estado: estado,
  motivoRechazo: motivo,
  revisadoEn: revisadoEn,
  urlCloud: urlCloud,
  auditoria: Auditoria(createdAt: _fecha, updatedAt: _fecha, syncVersion: syncVersion),
);

void main() {
  group('un depósito con su ticket', () {
    test('baja y espera: «por validar», con los datos del ticket', () {
      final item = ItemDelHistorial.deDeposito(_deposito(), ticket: _ticket());

      expect(item.estado, EstadoDelItem.porValidar);
      expect(item.id, 'd-1');
      expect(item.ticketId, 't-1');
      expect(item.lugar, LugarDelTicket.banco);
      expect(item.concepto, ConceptoDeDeposito.casaEditora);
      expect(item.montoCentavos, 480000);
      expect(item.numeroAutorizacion, '004512');
      expect(item.tarjetaTipo, TipoDeTarjeta.debito);
      expect(item.motivoRechazo, isNull);
    });

    test('sin llegar al servidor (la fila o el ticket sin versión) está «en cola»', () {
      expect(
        ItemDelHistorial.deDeposito(_deposito(syncVersion: 0), ticket: _ticket()).estado,
        EstadoDelItem.enCola,
      );
      expect(
        ItemDelHistorial.deDeposito(_deposito(), ticket: _ticket(syncVersion: 0)).estado,
        EstadoDelItem.enCola,
      );
    });

    test('lo validó el coordinador: «validado», con cuándo', () {
      final validado = DateTime.utc(2026, 11, 11, 15);
      final item = ItemDelHistorial.deDeposito(
        _deposito(validadoEn: validado),
        ticket: _ticket(estado: EstadoDeTicket.validado, revisadoEn: DateTime.utc(2026, 11, 12)),
      );

      expect(item.estado, EstadoDelItem.validado);
      expect(item.validadoEn, validado, reason: 'gana la fecha del depósito');
    });

    test('el ticket validado sin la marca del depósito también cuenta como validado', () {
      final revisado = DateTime.utc(2026, 11, 12);
      final item = ItemDelHistorial.deDeposito(
        _deposito(),
        ticket: _ticket(estado: EstadoDeTicket.validado, revisadoEn: revisado),
      );

      expect(item.estado, EstadoDelItem.validado);
      expect(item.validadoEn, revisado);
    });

    test('el ticket rechazado trae su motivo, sin espacios de más', () {
      final item = ItemDelHistorial.deDeposito(
        _deposito(),
        ticket: _ticket(estado: EstadoDeTicket.rechazado, motivo: '  La foto no se lee  '),
      );

      expect(item.estado, EstadoDelItem.rechazado);
      expect(item.motivoRechazo, 'La foto no se lee');
      expect(item.sePuedeCargarDeNuevo, isTrue);
    });

    test('un pago validado que el coordinador devolvió es «devuelto», no «validado»', () {
      final item = ItemDelHistorial.deDeposito(
        _deposito(concepto: ConceptoDeDeposito.alquiler, validadoEn: _fecha, anuladoAt: _fecha),
        ticket: _ticket(estado: EstadoDeTicket.validado, revisadoEn: _fecha),
      );

      expect(item.estado, EstadoDelItem.devuelto);
      expect(item.validadoEn, isNull, reason: 'no se dice «se acreditó»');
      expect(item.sePuedeCargarDeNuevo, isFalse);
      expect(FiltroDeTickets.todos.acepta(item), isTrue, reason: 'la fila no sale del historial');
      expect(FiltroDeTickets.alquiler.acepta(item), isTrue);
      expect(FiltroDeTickets.porValidar.acepta(item), isFalse);
      expect(FiltroDeTickets.rechazados.acepta(item), isFalse);
    });

    test('un depósito sin anular sigue validado', () {
      final item = ItemDelHistorial.deDeposito(
        _deposito(validadoEn: _fecha),
        ticket: _ticket(estado: EstadoDeTicket.validado, revisadoEn: _fecha),
      );

      expect(item.estado, EstadoDelItem.validado);
    });

    test('rechazado gana sobre validado: ante la duda no se acredita', () {
      final item = ItemDelHistorial.deDeposito(
        _deposito(validadoEn: _fecha, rechazadoEn: _fecha, motivoRechazo: 'No coincide'),
        ticket: _ticket(),
      );

      expect(item.estado, EstadoDelItem.rechazado);
      expect(item.validadoEn, isNull);
      expect(item.motivoRechazo, 'No coincide');
    });

    test('un motivo en blanco es «sin motivo»', () {
      final item = ItemDelHistorial.deDeposito(
        _deposito(),
        ticket: _ticket(estado: EstadoDeTicket.rechazado, motivo: '   '),
      );

      expect(item.motivoRechazo, isNull);
    });

    test('lo de la foto: subida, copia local y rechazo del servidor', () {
      final item = ItemDelHistorial.deDeposito(
        _deposito(),
        ticket: _ticket(urlCloud: 'u/t-1.jpg'),
        foto: fotoLocalDePrueba('t-1', estado: EstadoDeSubida.rechazada),
      );

      expect(item.fotoSubida, isTrue);
      expect(item.hayCopiaLocal, isTrue);
      expect(item.fotoRechazada, isTrue);
    });
  });

  group('un retiro por el coordinador (sin ticket)', () {
    test('espera, se valida o se rechaza con la marca del depósito', () {
      final retiro = _deposito(destino: DestinoDeDeposito.retiroCoordinador);

      expect(ItemDelHistorial.deDeposito(retiro).estado, EstadoDelItem.porValidar);
      expect(ItemDelHistorial.deDeposito(retiro).ticketId, isNull);
      expect(ItemDelHistorial.deDeposito(retiro).lugar, LugarDelTicket.retiro);
      expect(
        ItemDelHistorial.deDeposito(
          _deposito(destino: DestinoDeDeposito.retiroCoordinador, validadoEn: _fecha),
        ).estado,
        EstadoDelItem.validado,
      );
      final rechazado = ItemDelHistorial.deDeposito(
        _deposito(
          destino: DestinoDeDeposito.retiroCoordinador,
          rechazadoEn: _fecha,
          motivoRechazo: 'No lo recibí',
        ),
      );
      expect(rechazado.estado, EstadoDelItem.rechazado);
      expect(rechazado.motivoRechazo, 'No lo recibí');
      expect(rechazado.sePuedeCargarDeNuevo, isTrue);
    });

    test('sin versión del servidor está «en cola»', () {
      final retiro = _deposito(destino: DestinoDeDeposito.retiroCoordinador, syncVersion: 0);

      expect(ItemDelHistorial.deDeposito(retiro).estado, EstadoDelItem.enCola);
    });
  });

  group('un ticket que ningún depósito nombra', () {
    test(
      'el de un cobro con tarjeta: su estado sale del ticket y no se vuelve a cargar de acá',
      () {
        final item = ItemDelHistorial.deTicket(
          _ticket(
            tipo: TipoDeTicket.cobroTarjeta,
            estado: EstadoDeTicket.rechazado,
            motivo: 'No se ve el número',
          ),
        );

        expect(item.lugar, LugarDelTicket.cobroConTarjeta);
        expect(item.concepto, isNull);
        expect(item.depositoId, isNull);
        expect(item.id, 't-1');
        expect(item.estado, EstadoDelItem.rechazado);
        expect(item.motivoRechazo, 'No se ve el número');
        expect(item.sePuedeCargarDeNuevo, isFalse);
      },
    );

    test('pendiente: «en cola» sin versión y «por validar» con ella', () {
      expect(ItemDelHistorial.deTicket(_ticket(syncVersion: 0)).estado, EstadoDelItem.enCola);
      expect(ItemDelHistorial.deTicket(_ticket()).estado, EstadoDelItem.porValidar);
    });

    test('un ticket de depósito cuyo depósito no bajó no dice dónde fue', () {
      expect(ItemDelHistorial.deTicket(_ticket()).lugar, LugarDelTicket.deposito);
      expect(
        ItemDelHistorial.deTicket(_ticket(tipo: TipoDeTicket.otro)).lugar,
        LugarDelTicket.otro,
      );
    });
  });

  group('los filtros', () {
    final porValidar = ItemDelHistorial.deDeposito(_deposito(), ticket: _ticket());
    final enCola = ItemDelHistorial.deDeposito(_deposito(syncVersion: 0), ticket: _ticket());
    final validado = ItemDelHistorial.deDeposito(
      _deposito(validadoEn: _fecha, concepto: ConceptoDeDeposito.alquiler),
      ticket: _ticket(),
    );
    final rechazado = ItemDelHistorial.deDeposito(
      _deposito(),
      ticket: _ticket(estado: EstadoDeTicket.rechazado),
    );
    final suelto = ItemDelHistorial.deTicket(_ticket(tipo: TipoDeTicket.cobroTarjeta));

    test('«Todos» las acepta a todas', () {
      for (final i in [porValidar, enCola, validado, rechazado, suelto]) {
        expect(FiltroDeTickets.todos.acepta(i), isTrue);
      }
    });

    test('«Por validar» incluye lo que todavía está en cola', () {
      expect(FiltroDeTickets.porValidar.acepta(porValidar), isTrue);
      expect(FiltroDeTickets.porValidar.acepta(enCola), isTrue);
      expect(FiltroDeTickets.porValidar.acepta(validado), isFalse);
      expect(FiltroDeTickets.porValidar.acepta(rechazado), isFalse);
    });

    test('«Rechazados» y «Alquiler»', () {
      expect(FiltroDeTickets.rechazados.acepta(rechazado), isTrue);
      expect(FiltroDeTickets.rechazados.acepta(porValidar), isFalse);
      expect(FiltroDeTickets.alquiler.acepta(validado), isTrue);
      expect(FiltroDeTickets.alquiler.acepta(porValidar), isFalse);
      expect(FiltroDeTickets.alquiler.acepta(suelto), isFalse);
    });

    test('el historial cuenta cuántos esperan validación', () {
      final historial = HistorialDeTickets(items: [porValidar, enCola, validado, rechazado]);

      expect(historial.porValidar, 2);
      expect(const HistorialDeTickets(items: []).porValidar, 0);
    });
  });

  test('toString no filtra el motivo del rechazo (texto libre de otra persona)', () {
    final antes = EquatableConfig.stringify;
    EquatableConfig.stringify = true;
    addTearDown(() => EquatableConfig.stringify = antes);
    final item = ItemDelHistorial.deDeposito(
      _deposito(),
      ticket: _ticket(estado: EstadoDeTicket.rechazado, motivo: 'Es de María Fernández'),
    );

    expect('$item', isNot(contains('María')));
  });
}
