// Quién revisa el ticket (R1 de #427): «lo revisa Administración» sale del dato que manda el servidor,
// nunca de un cálculo del teléfono.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:test/test.dart';

import '../../../../helpers/tickets_falsos.dart';

Ticket _ticket({DateTime? subidoEn, String? campania}) => Ticket(
  id: 't-1',
  tipo: TipoDeTicket.cobroTarjeta,
  montoCentavos: 100,
  fecha: ahoraTicket,
  auditoria: Auditoria(createdAt: ahoraTicket, updatedAt: ahoraTicket, createdBy: 'col-1'),
  subidoEn: subidoEn,
  campaniaValidadoraId: campania,
);

void main() {
  test('recién creado en el teléfono no se sabe quién lo valida', () {
    final t = _ticket();

    expect(t.llegoAlServidor, isFalse);
    expect(t.loRevisaAdministracion, isFalse);
  });

  test('con la fila de vuelta y sin campaña lo revisa Administración', () {
    final t = _ticket(subidoEn: ahoraTicket);

    expect(t.llegoAlServidor, isTrue);
    expect(t.loRevisaAdministracion, isTrue);
  });

  test('con la fila de vuelta y una campaña lo revisa su coordinadora', () {
    final t = _ticket(subidoEn: ahoraTicket, campania: 'camp-1');

    expect(t.llegoAlServidor, isTrue);
    expect(t.loRevisaAdministracion, isFalse);
  });
}
