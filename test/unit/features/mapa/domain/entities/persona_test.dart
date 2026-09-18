// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Persona construir({String apellido = 'Perez'}) => Persona(
    id: 'per-1',
    nombre: 'Juan',
    apellido: apellido,
    telefono: null,
    notasGlobales: null,
    auditoria: auditoria,
  );

  group('Persona', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que apellido difiere, cuando se comparan, no son iguales', () {
      final a = construir(apellido: 'Perez');
      final b = construir(apellido: 'Gomez');

      expect(a, isNot(equals(b)));
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final persona = Persona(
        id: 'per-1',
        nombre: 'Juan',
        apellido: 'Perez',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(persona.estaBorrada, isTrue);
    });
  });
}
