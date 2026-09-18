// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Cobranza construir({MedioCobranza medio = MedioCobranza.efectivo, String? ticketId}) => Cobranza(
    id: 'cob-1',
    ventaId: 'venta-1',
    montoCentavos: 50000,
    medio: medio,
    fecha: DateTime(2026, 9, 18),
    ticketId: ticketId,
    numeroCuota: 1,
    auditoria: auditoria,
  );

  group('Cobranza', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir(ticketId: 'tk-1');
      final b = construir(ticketId: 'tk-1');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que medio difiere, cuando se comparan, no son iguales', () {
      final a = construir(medio: MedioCobranza.efectivo);
      final b = construir(medio: MedioCobranza.tarjeta);

      expect(a, isNot(equals(b)));
    });

    test('dado que ventaId es requerido por el tipo, cuando se construye sin venta, no compila '
        '(regla RF-CO01..04 aplicada por el sistema de tipos, no en runtime)', () {
      // Documental: Cobranza.ventaId es `String` no-nullable — omitir el argumento es un
      // error de compilación, no una excepción en runtime. No hay assert que probar acá.
      expect(construir().ventaId, isNotEmpty);
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final cobranza = Cobranza(
        id: 'cob-1',
        ventaId: 'venta-1',
        montoCentavos: 50000,
        medio: MedioCobranza.efectivo,
        fecha: DateTime(2026, 9, 18),
        numeroCuota: 1,
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(cobranza.estaBorrada, isTrue);
    });
  });
}
