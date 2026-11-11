// El DTO del depósito (HU-CTA-004, #442): las claves exactas que suben y los códigos del servidor.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/depositos/data/models/deposito_model.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:test/test.dart';

void main() {
  final ahora = DateTime.utc(2026, 10, 30, 12, 0, 7, 321);

  Deposito deposito({
    DestinoDeDeposito destino = DestinoDeDeposito.banco,
    ConceptoDeDeposito concepto = ConceptoDeDeposito.casaEditora,
    String? campaniaId,
    String? ticketId = 't-1',
  }) => Deposito(
    id: 'd-1',
    montoCentavos: 180000,
    fecha: ahora,
    destino: destino,
    concepto: concepto,
    campaniaId: campaniaId,
    ticketId: ticketId,
    auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: 'col-1'),
  );

  group('toJson', () {
    test('dado un depósito, cuando se arma el payload, lleva exactamente las columnas del servidor '
        'con las fechas en ISO-8601 UTC', () {
      final json = DepositoModel.toJson(deposito(campaniaId: 'camp-1'));

      expect(json, {
        'id': 'd-1',
        'monto': 180000,
        'fecha': '2026-10-30T12:00:07.321Z',
        'destino': 'BANCO',
        'concepto': 'CASA_EDITORA',
        'campania_id': 'camp-1',
        'ticket_id': 't-1',
        'created_at': '2026-10-30T12:00:07.321Z',
        'updated_at': '2026-10-30T12:00:07.321Z',
        'created_by': 'col-1',
        'deleted_at': null,
        'sync_version': 0,
      });
    });

    test(
      'dado que el servidor fija al dueño y la validación, cuando se arma el payload, no los manda',
      () {
        final claves = DepositoModel.toJson(deposito()).keys;

        for (final delServidor in [
          'colportor_id',
          'validado_en',
          'validado_por',
          'rechazado_en',
          'rechazado_por',
          'motivo_rechazo',
        ]) {
          expect(claves, isNot(contains(delServidor)));
        }
      },
    );

    test(
      'dado un retiro por el coordinador sin ticket, cuando se arma el payload, el ticket va nulo',
      () {
        final json = DepositoModel.toJson(
          deposito(destino: DestinoDeDeposito.retiroCoordinador, ticketId: null),
        );

        expect(json['destino'], 'RETIRO_COORDINADOR');
        expect(json['ticket_id'], isNull);
      },
    );
  });

  group('los códigos', () {
    test(
      'dado cada destino y cada concepto, cuando se codifica y se decodifica, vuelve el mismo',
      () {
        for (final destino in DestinoDeDeposito.values) {
          expect(
            DepositoModel.destinoDesdeCodigo(DepositoModel.codigoDelDestino(destino)),
            destino,
          );
        }
        for (final concepto in ConceptoDeDeposito.values) {
          expect(
            DepositoModel.conceptoDesdeCodigo(DepositoModel.codigoDelConcepto(concepto)),
            concepto,
          );
        }
      },
    );

    test('dado un código que el servidor no tiene, cuando se decodifica, falla a la vista', () {
      expect(() => DepositoModel.destinoDesdeCodigo('CAJERO'), throwsArgumentError);
      expect(() => DepositoModel.conceptoDesdeCodigo('OTRO'), throwsArgumentError);
    });
  });
}
