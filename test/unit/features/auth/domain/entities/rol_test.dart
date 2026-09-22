// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/rol.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Rol construir({NombreRol nombre = NombreRol.colportor, Auditoria? auditoriaCustom}) =>
      Rol(id: 'rol-1', nombre: nombre, auditoria: auditoriaCustom ?? auditoria);

  group('Rol', () {
    test('dado que dos roles tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que el nombre difiere, cuando se comparan dos roles, no son iguales', () {
      final a = construir(nombre: NombreRol.colportor);
      final b = construir(nombre: NombreRol.admin);

      expect(a, isNot(equals(b)));
    });

    test('dado un catalogo de roles, cuando se listan los valores, cubre los 6 del esquema', () {
      expect(NombreRol.values, hasLength(6));
      expect(
        NombreRol.values,
        containsAll(<NombreRol>[
          NombreRol.guest,
          NombreRol.colportor,
          NombreRol.coordinador,
          NombreRol.admin,
          NombreRol.asistenteFin,
          NombreRol.acompanante,
        ]),
      );
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final rol = construir(
        auditoriaCustom: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(rol.estaBorrada, isTrue);
    });
  });
}
