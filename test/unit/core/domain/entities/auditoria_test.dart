// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:test/test.dart';

void main() {
  final ahora = DateTime(2026, 9, 18, 10, 0);

  Auditoria construir({DateTime? deletedAt, int syncVersion = 0, String? createdBy}) => Auditoria(
    createdAt: ahora,
    updatedAt: ahora,
    createdBy: createdBy,
    deletedAt: deletedAt,
    syncVersion: syncVersion,
  );

  group('Auditoria', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir(createdBy: 'u1');
      final b = construir(createdBy: 'u1');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que syncVersion difiere, cuando se comparan dos instancias, no son iguales', () {
      final a = construir(syncVersion: 1);
      final b = construir(syncVersion: 2);

      expect(a, isNot(equals(b)));
    });

    test('dado que deletedAt es null, cuando se consulta estaBorrada, es false', () {
      expect(construir().estaBorrada, isFalse);
    });

    test('dado que deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      expect(construir(deletedAt: ahora).estaBorrada, isTrue);
    });

    test('dado que no se pasa syncVersion, cuando se construye, el default es 0', () {
      final a = Auditoria(createdAt: ahora, updatedAt: ahora);
      expect(a.syncVersion, equals(0));
    });
  });
}
