// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Visita construir({TipoResultadoVisita tipo = TipoResultadoVisita.venta, String? notas}) => Visita(
    id: 'vis-1',
    espacioPersonaId: 'ep-1',
    fecha: DateTime(2026, 9, 18),
    tipoResultado: tipo,
    notas: notas,
    colportorId: 'u-1',
    jornadaId: 'jor-1',
    auditoria: auditoria,
  );

  group('Visita', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir(notas: 'atendio en la puerta');
      final b = construir(notas: 'atendio en la puerta');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que tipoResultado difiere, cuando se comparan, no son iguales', () {
      final a = construir(tipo: TipoResultadoVisita.venta);
      final b = construir(tipo: TipoResultadoVisita.rechazo);

      expect(a, isNot(equals(b)));
    });

    test(
      'dado el catalogo de resultados, cuando se listan los valores, cubre los 4 del esquema',
      () {
        expect(TipoResultadoVisita.values, hasLength(4));
        expect(
          TipoResultadoVisita.values,
          containsAll(<TipoResultadoVisita>[
            TipoResultadoVisita.venta,
            TipoResultadoVisita.noContesto,
            TipoResultadoVisita.rechazo,
            TipoResultadoVisita.entrevista,
          ]),
        );
      },
    );

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final visita = Visita(
        id: 'vis-1',
        espacioPersonaId: 'ep-1',
        fecha: DateTime(2026, 9, 18),
        tipoResultado: TipoResultadoVisita.venta,
        colportorId: 'u-1',
        jornadaId: 'jor-1',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(visita.estaBorrada, isTrue);
    });
  });
}
