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

    test('dado que RF-CO01..04 exige venta_id NOT NULL, cuando se declara Cobranza.ventaId, su '
        'tipo estatico es no-nullable', () {
      // [_exigeNoNullable] tiene `T extends Object`: si `ventaId` pasara a `String?` esta línea
      // deja de compilar y el build se pone rojo — que es exactamente la regresión que cuida.
      // Un `expect(..., isNotEmpty)` no la detectaría: pasa igual con un tipo nullable.
      expect(_exigeNoNullable(construir().ventaId), equals('venta-1'));
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

/// Acepta únicamente valores de un tipo no-nullable (`T extends Object`). Pasarle un `String?`
/// es un error de compilación, así que sirve para fijar por tipo una regla de integridad que no
/// se puede comprobar en runtime.
T _exigeNoNullable<T extends Object>(T valor) => valor;
