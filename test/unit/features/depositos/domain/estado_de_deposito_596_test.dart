// Test de dominio: Dart puro. El estado de un depósito (#596): por validar, validado o rechazado, según
// lo que baja del servidor («Acredita V1», 23/10; «Rechazo ret.», 28/10).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:test/test.dart';

Deposito _deposito({
  DateTime? validadoEn,
  String? validadoPor,
  DateTime? rechazadoEn,
  String? motivoRechazo,
}) => Deposito(
  id: 'd-1',
  montoCentavos: 180000,
  fecha: DateTime.utc(2026, 10, 28, 15),
  destino: DestinoDeDeposito.banco,
  concepto: ConceptoDeDeposito.casaEditora,
  ticketId: 't-1',
  validadoEn: validadoEn,
  validadoPor: validadoPor,
  rechazadoEn: rechazadoEn,
  motivoRechazo: motivoRechazo,
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 10, 28, 15),
    updatedAt: DateTime.utc(2026, 10, 28, 15),
    createdBy: 'col-1',
  ),
);

void main() {
  test('dado un depósito recién registrado, cuando se pregunta su estado, está por validar', () {
    expect(_deposito().estado, EstadoDeDeposito.porValidar);
  });

  test(
    'dado un depósito que el coordinador validó, cuando se pregunta su estado, está validado',
    () {
      final d = _deposito(validadoEn: DateTime.utc(2026, 10, 29, 9), validadoPor: 'coord-1');

      expect(d.estado, EstadoDeDeposito.validado);
      expect(d.validadoPor, 'coord-1');
    },
  );

  test('dado un retiro que el coordinador rechazó, cuando se pregunta su estado, está rechazado '
      'y conserva el motivo', () {
    final d = _deposito(
      rechazadoEn: DateTime.utc(2026, 10, 29, 9),
      motivoRechazo: 'Recibí \$ 5.000, no \$ 6.000.',
    );

    expect(d.estado, EstadoDeDeposito.rechazado);
    expect(d.motivoRechazo, 'Recibí \$ 5.000, no \$ 6.000.');
  });

  test('dado un depósito con las dos marcas (no debería pasar), cuando se pregunta su estado, gana '
      'el rechazo: ante la duda no se acredita', () {
    final d = _deposito(
      validadoEn: DateTime.utc(2026, 10, 29, 9),
      rechazadoEn: DateTime.utc(2026, 10, 29, 10),
      motivoRechazo: 'x',
    );

    expect(d.estado, EstadoDeDeposito.rechazado);
  });

  test('dos depósitos con las mismas fechas son iguales; con otro estado, no', () {
    final a = _deposito(validadoEn: DateTime.utc(2026, 10, 29, 9));
    final b = _deposito(validadoEn: DateTime.utc(2026, 10, 29, 9));

    expect(a, b);
    expect(a, isNot(_deposito()));
  });

  test('las fechas del servidor se guardan al milisegundo, como el resto de la app', () {
    final d = _deposito(validadoEn: DateTime.utc(2026, 10, 29, 9, 0, 0, 123, 456));

    expect(d.validadoEn, DateTime.utc(2026, 10, 29, 9, 0, 0, 123));
  });
}
