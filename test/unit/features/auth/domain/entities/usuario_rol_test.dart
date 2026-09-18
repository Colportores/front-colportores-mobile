// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/usuario_rol.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  UsuarioRol construir({DateTime? validoDesde, DateTime? validoHasta}) => UsuarioRol(
    id: 'ur-1',
    usuarioId: 'u-1',
    rolId: 'rol-1',
    validoDesde: validoDesde ?? DateTime(2026, 1, 1),
    validoHasta: validoHasta,
    auditoria: auditoria,
  );

  group('UsuarioRol', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que validoHasta difiere, cuando se comparan, no son iguales', () {
      final a = construir(validoHasta: DateTime(2026, 6, 1));
      final b = construir(validoHasta: DateTime(2026, 12, 1));

      expect(a, isNot(equals(b)));
    });

    test(
      'dado un rol sin fecha de expiracion, cuando se consulta esVigente despues de validoDesde, '
      'es true',
      () {
        final ur = construir(validoDesde: DateTime(2026, 1, 1));
        expect(ur.esVigente(ahora: DateTime(2030, 1, 1)), isTrue);
      },
    );

    test('dado un rol temporal, cuando se consulta esVigente antes de validoDesde, es false', () {
      final ur = construir(validoDesde: DateTime(2026, 6, 1));
      expect(ur.esVigente(ahora: DateTime(2026, 1, 1)), isFalse);
    });

    test('dado un rol temporal, cuando se consulta esVigente despues de validoHasta, es false', () {
      final ur = construir(validoDesde: DateTime(2026, 1, 1), validoHasta: DateTime(2026, 6, 1));
      expect(ur.esVigente(ahora: DateTime(2026, 7, 1)), isFalse);
    });

    test('dado un rol temporal, cuando se consulta esVigente dentro del rango, es true', () {
      final ur = construir(validoDesde: DateTime(2026, 1, 1), validoHasta: DateTime(2026, 6, 1));
      expect(ur.esVigente(ahora: DateTime(2026, 3, 1)), isTrue);
    });

    test(
      'dado que no se pasa ahora, cuando se consulta esVigente, usa la hora actual del sistema',
      () {
        final ur = construir(validoDesde: DateTime(2020, 1, 1));
        expect(ur.esVigente(), isTrue);
      },
    );

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final ur = UsuarioRol(
        id: 'ur-1',
        usuarioId: 'u-1',
        rolId: 'rol-1',
        validoDesde: DateTime(2026, 1, 1),
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(ur.estaBorrada, isTrue);
    });
  });
}
