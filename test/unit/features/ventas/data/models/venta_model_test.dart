// Test de dominio/datos: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/ventas/data/models/venta_model.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta.dart';
import 'package:test/test.dart';

void main() {
  test('dado una venta, cuando se arma el JSON del contrato, montoTotalCentavos sube como '
      'monto_total en centavos (#544)', () {
    final venta = Venta(
      id: 'venta-1',
      espacioPersonaId: 'ep-1',
      numeroTalonario: 'A-0001',
      montoTotalCentavos: 150050,
      fecha: DateTime.utc(2026, 9, 18),
      colportorId: 'u-1',
      visitaId: null,
      auditoria: Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1)),
    );

    final json = VentaModel.toJson(venta);

    expect(json['monto_total'], 150050);
    expect(json.containsKey('monto_total_centavos'), isFalse);
  });

  group('items_esperados (#608, «Total arriba»)', () {
    final venta = Venta(
      id: 'venta-1',
      espacioPersonaId: 'ep-1',
      numeroTalonario: 'A-0001',
      montoTotalCentavos: 150050,
      fecha: DateTime.utc(2026, 9, 18),
      colportorId: 'u-1',
      visitaId: null,
      auditoria: Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1)),
    );

    test('dado una venta con tres renglones, cuando se arma el push, sube cuántos lleva', () {
      expect(VentaModel.toJson(venta, itemsEsperados: 3)['items_esperados'], 3);
    });

    test('dado que no se sabe cuántos renglones lleva (o son cero), no manda la clave: el '
        'servidor aplica la regla de siempre', () {
      expect(VentaModel.toJson(venta).containsKey('items_esperados'), isFalse);
      expect(VentaModel.toJson(venta, itemsEsperados: 0).containsKey('items_esperados'), isFalse);
    });
  });
}
