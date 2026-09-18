// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Jornada construir({DateTime? fin, int totalVisitas = 0}) => Jornada(
    id: 'jor-1',
    colportorId: 'u-1',
    inicio: DateTime(2026, 9, 18, 9, 0),
    fin: fin,
    totalVisitas: totalVisitas,
    auditoria: auditoria,
  );

  group('Jornada', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que totalVisitas difiere, cuando se comparan, no son iguales', () {
      final a = construir(totalVisitas: 3);
      final b = construir(totalVisitas: 5);

      expect(a, isNot(equals(b)));
    });

    test('dado que no se asigna fin, cuando se construye, estaAbierta es true', () {
      expect(construir().estaAbierta, isTrue);
    });

    test('dado que se asigna fin, cuando se consulta estaAbierta, es false', () {
      expect(construir(fin: DateTime(2026, 9, 18, 18, 0)).estaAbierta, isFalse);
    });

    test(
      'dado que no se pasan totales, cuando se construye, totalVisitas y totalVentas default a 0',
      () {
        final j = Jornada(
          id: 'jor-1',
          colportorId: 'u-1',
          inicio: DateTime(2026, 1, 1),
          auditoria: auditoria,
        );
        expect(j.totalVisitas, equals(0));
        expect(j.totalVentas, equals(0));
      },
    );

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final jornada = Jornada(
        id: 'jor-1',
        colportorId: 'u-1',
        inicio: DateTime(2026, 9, 18, 9, 0),
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(jornada.estaBorrada, isTrue);
    });
  });
}
