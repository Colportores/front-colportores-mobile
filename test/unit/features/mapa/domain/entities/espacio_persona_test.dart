// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio_persona.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  EspacioPersona construir({String? ubicacionCobranzaAltId}) => EspacioPersona(
    id: 'ep-1',
    espacioId: 'esp-1',
    personaId: 'per-1',
    ubicacionCobranzaAltId: ubicacionCobranzaAltId,
    auditoria: auditoria,
  );

  group('EspacioPersona', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir(ubicacionCobranzaAltId: 'ub-2');
      final b = construir(ubicacionCobranzaAltId: 'ub-2');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que ubicacionCobranzaAltId difiere, cuando se comparan, no son iguales', () {
      final a = construir(ubicacionCobranzaAltId: 'ub-2');
      final b = construir(ubicacionCobranzaAltId: 'ub-3');

      expect(a, isNot(equals(b)));
    });

    test('dado el caso normal sin cobranza alternativa, cuando se construye, el campo es null', () {
      expect(construir().ubicacionCobranzaAltId, isNull);
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final ep = EspacioPersona(
        id: 'ep-1',
        espacioId: 'esp-1',
        personaId: 'per-1',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(ep.estaBorrada, isTrue);
    });
  });
}
