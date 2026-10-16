// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_item.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  VentaItem construir({int cantidad = 2}) => VentaItem(
    id: 'vi-1',
    ventaId: 'venta-1',
    productoId: 'prod-1',
    cantidad: cantidad,
    precioUnitarioCentavos: 50000,
    subtotalCentavos: 100000,
    auditoria: auditoria,
  );

  group('VentaItem', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que cantidad difiere, cuando se comparan, no son iguales', () {
      final a = construir(cantidad: 2);
      final b = construir(cantidad: 3);

      expect(a, isNot(equals(b)));
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final item = VentaItem(
        id: 'vi-1',
        ventaId: 'venta-1',
        productoId: 'prod-1',
        cantidad: 2,
        precioUnitarioCentavos: 50000,
        subtotalCentavos: 100000,
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(item.estaBorrada, isTrue);
    });
  });
}
