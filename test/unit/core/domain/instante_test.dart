// Decisión de Cristian del 23/09 en #70: toda entidad trunca sus instantes al milisegundo en el
// constructor, así que un instante con microsegundos sale truncado pase por donde pase.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/domain/instante.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:test/test.dart';

void main() {
  // 10:30:00.123456 local: microsegundos y sin UTC, lo peor que puede llegar.
  final conMicros = DateTime(2026, 9, 29, 10, 30, 0, 123, 456);
  final truncado = DateTime.fromMillisecondsSinceEpoch(
    conMicros.millisecondsSinceEpoch,
    isUtc: true,
  );

  group('instanteMs', () {
    test('dado un instante local con microsegundos, cuando se normaliza, queda en UTC y sin '
        'microsegundos', () {
      final r = instanteMs(conMicros);

      expect(r.isUtc, isTrue);
      expect(r.microsecond, 0);
      expect(r.millisecond, 123);
      expect(r, truncado);
    });

    test('dado un instante ya truncado, cuando se normaliza, no cambia', () {
      expect(instanteMs(truncado), truncado);
    });
  });

  group('dado un instante con microsegundos', () {
    test('cuando se construye una Auditoria, sus tres fechas quedan truncadas', () {
      final a = Auditoria(createdAt: conMicros, updatedAt: conMicros, deletedAt: conMicros);

      expect([a.createdAt, a.updatedAt, a.deletedAt], everyElement(truncado));
    });

    test('cuando se copia una Auditoria con copyWith, la fecha nueva queda truncada', () {
      final a = Auditoria(
        createdAt: truncado,
        updatedAt: truncado,
      ).copyWith(updatedAt: conMicros, deletedAt: conMicros);

      expect(a.updatedAt, truncado);
      expect(a.deletedAt, truncado);
    });

    test('cuando se construye una Jornada, inicio y fin quedan truncados', () {
      final j = Jornada(
        id: 'jor-1',
        colportorId: 'col-1',
        inicio: conMicros,
        fin: conMicros,
        auditoria: Auditoria(createdAt: conMicros, updatedAt: conMicros),
      );

      expect(j.inicio, truncado);
      expect(j.fin, truncado);
    });
  });
}
