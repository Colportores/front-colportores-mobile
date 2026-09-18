// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Venta construir({int montoTotalCentavos = 150000}) => Venta(
    id: 'venta-1',
    espacioPersonaId: 'ep-1',
    numeroTalonario: 'A-0001',
    montoTotalCentavos: montoTotalCentavos,
    fecha: DateTime(2026, 9, 18),
    colportorId: 'u-1',
    visitaId: 'vis-1',
    auditoria: auditoria,
  );

  group('Venta', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que montoTotalCentavos difiere, cuando se comparan, no son iguales', () {
      final a = construir(montoTotalCentavos: 150000);
      final b = construir(montoTotalCentavos: 200000);

      expect(a, isNot(equals(b)));
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final venta = Venta(
        id: 'venta-1',
        espacioPersonaId: 'ep-1',
        numeroTalonario: 'A-0001',
        montoTotalCentavos: 150000,
        fecha: DateTime(2026, 9, 18),
        colportorId: 'u-1',
        visitaId: 'vis-1',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(venta.estaBorrada, isTrue);
    });
  });
}
