// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Visita construir({
    TipoResultadoVisita tipo = TipoResultadoVisita.venta,
    String? jornadaId = 'jor-1',
    Auditoria? auditoriaPropia,
  }) => Visita(
    id: 'vis-1',
    espacioPersonaId: 'ep-1',
    fecha: DateTime(2026, 9, 18),
    tipoResultado: tipo,
    colportorId: 'u-1',
    jornadaId: jornadaId,
    auditoria: auditoriaPropia ?? auditoria,
  );

  group('Visita', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir();
      final b = construir();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que tipoResultado difiere, cuando se comparan, no son iguales', () {
      final a = construir(tipo: TipoResultadoVisita.venta);
      final b = construir(tipo: TipoResultadoVisita.rechazo);

      expect(a, isNot(equals(b)));
    });

    test('dado una visita sin jornada, cuando se construye, jornadaId queda en null como en el '
        'servidor', () {
      expect(construir(jornadaId: null).jornadaId, isNull);
    });

    test('dado el catalogo de resultados, cuando se listan los valores, cubre los 4 del esquema '
        'con el codigo de la columna', () {
      expect(
        {for (final t in TipoResultadoVisita.values) t: t.codigo},
        {
          TipoResultadoVisita.venta: 'VENTA',
          TipoResultadoVisita.noContesto: 'NO_CONTESTO',
          TipoResultadoVisita.rechazo: 'RECHAZO',
          TipoResultadoVisita.entrevista: 'ENTREVISTA',
        },
      );
    });

    test('dado el codigo de cada resultado, cuando se lee de vuelta, es el mismo resultado', () {
      for (final tipo in TipoResultadoVisita.values) {
        expect(TipoResultadoVisita.desdeCodigo(tipo.codigo), tipo);
      }
    });

    test('dado un codigo que no existe, cuando se lee, lanza ArgumentError', () {
      expect(() => TipoResultadoVisita.desdeCodigo('COBRANZA'), throwsArgumentError);
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final visita = construir(
        auditoriaPropia: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(visita.estaBorrada, isTrue);
    });
  });
}
