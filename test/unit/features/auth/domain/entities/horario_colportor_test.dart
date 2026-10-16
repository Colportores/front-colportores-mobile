// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/horario_colportor.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  HorarioColportor construir({DiaSemana dia = DiaSemana.lunes, String slot = 'AM1'}) =>
      HorarioColportor(
        id: 'hc-1',
        usuarioId: 'u-1',
        diaSemana: dia,
        slotCodigo: slot,
        auditoria: auditoria,
      );

  group('HorarioColportor', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que diaSemana difiere, cuando se comparan, no son iguales', () {
      final a = construir(dia: DiaSemana.lunes);
      final b = construir(dia: DiaSemana.martes);

      expect(a, isNot(equals(b)));
    });

    test('dado que slotCodigo difiere, cuando se comparan, no son iguales', () {
      final a = construir(slot: 'AM1');
      final b = construir(slot: 'PM2');

      expect(a, isNot(equals(b)));
    });

    test('dado un catalogo de dias, cuando se listan los valores, cubre los 7 dias', () {
      expect(DiaSemana.values, hasLength(7));
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final hc = HorarioColportor(
        id: 'hc-1',
        usuarioId: 'u-1',
        diaSemana: DiaSemana.lunes,
        slotCodigo: 'AM1',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(hc.estaBorrada, isTrue);
    });
  });
}
