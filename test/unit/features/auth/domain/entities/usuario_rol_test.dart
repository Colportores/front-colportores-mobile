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

    test('dado que no se pasa ahora, cuando se consulta esVigente, usa el instante actual del '
        'sistema y no un valor fijo', () {
      final ahoraReal = DateTime.now();
      final vigente = construir(
        validoDesde: ahoraReal.subtract(const Duration(days: 1)),
        validoHasta: ahoraReal.add(const Duration(days: 1)),
      );
      final expirado = construir(
        validoDesde: ahoraReal.subtract(const Duration(days: 2)),
        validoHasta: ahoraReal.subtract(const Duration(days: 1)),
      );
      final futuro = construir(validoDesde: ahoraReal.add(const Duration(days: 1)));

      // Los tres a la vez fijan el default a "ahora": un centinela fijo (epoch, año 3000)
      // haría fallar alguno.
      expect(vigente.esVigente(), isTrue);
      expect(expirado.esVigente(), isFalse);
      expect(futuro.esVigente(), isFalse);
    });

    test('dado un rol revocado por soft delete, cuando se consulta esVigente dentro de la '
        'ventana temporal, es false (esquema-datos.md §Principios 6)', () {
      final revocado = UsuarioRol(
        id: 'ur-1',
        usuarioId: 'u-1',
        rolId: 'rol-1',
        validoDesde: DateTime(2026, 1, 1),
        validoHasta: DateTime(2026, 12, 1),
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 3, 1),
          // Revocar es setear deleted_at; no toca validoDesde/validoHasta.
          deletedAt: DateTime(2026, 3, 1),
        ),
      );

      expect(revocado.esVigente(ahora: DateTime(2026, 6, 1)), isFalse);
      expect(revocado.esVigente(), isFalse);
    });

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
