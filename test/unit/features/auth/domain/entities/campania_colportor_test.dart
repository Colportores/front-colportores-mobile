// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_colportor.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  CampaniaColportor construir({int metaLibros = 100}) => CampaniaColportor(
    id: 'cc-1',
    campaniaId: 'camp-1',
    usuarioId: 'u-1',
    zonaId: 'zona-1',
    metaLibros: metaLibros,
    auditoria: auditoria,
  );

  group('CampaniaColportor', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que metaLibros difiere, cuando se comparan, no son iguales', () {
      final a = construir(metaLibros: 100);
      final b = construir(metaLibros: 150);

      expect(a, isNot(equals(b)));
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final cc = CampaniaColportor(
        id: 'cc-1',
        campaniaId: 'camp-1',
        usuarioId: 'u-1',
        zonaId: 'zona-1',
        metaLibros: 100,
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(cc.estaBorrada, isTrue);
    });
  });
}
