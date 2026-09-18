// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Espacio construir({String? numeroDepto}) => Espacio(
    id: 'esp-1',
    ubicacionId: 'ub-1',
    numeroDepto: numeroDepto,
    piso: null,
    descripcion: null,
    auditoria: auditoria,
  );

  group('Espacio', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir(numeroDepto: '3B');
      final b = construir(numeroDepto: '3B');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que numeroDepto difiere, cuando se comparan, no son iguales', () {
      final a = construir(numeroDepto: '3B');
      final b = construir(numeroDepto: '4A');

      expect(a, isNot(equals(b)));
    });

    test('dado que es una casa (sin depto), cuando se construye, numeroDepto es null', () {
      expect(construir().numeroDepto, isNull);
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final espacio = Espacio(
        id: 'esp-1',
        ubicacionId: 'ub-1',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(espacio.estaBorrada, isTrue);
    });
  });
}
