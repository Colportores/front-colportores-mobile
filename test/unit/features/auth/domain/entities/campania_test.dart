// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania.dart';
import 'package:test/test.dart';

void main() {
  final auditoria = Auditoria(createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 1));

  Campania construir({
    String? coordinadorId,
    TipoCampania tipo = TipoCampania.verano,
    DateTime? fechaFin,
  }) => Campania(
    id: 'camp-1',
    nombre: 'Verano 2026',
    tipo: tipo,
    fechaInicio: DateTime(2026, 12, 1),
    fechaFin: fechaFin ?? DateTime(2027, 2, 28),
    ciudadId: 'ciudad-1',
    coordinadorId: coordinadorId,
    auditoria: auditoria,
  );

  group('Campania', () {
    test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
        'comparten hashCode', () {
      final a = construir(coordinadorId: 'u-1');
      final b = construir(coordinadorId: 'u-1');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('dado que tipo difiere, cuando se comparan, no son iguales', () {
      final a = construir(tipo: TipoCampania.verano);
      final b = construir(tipo: TipoCampania.invierno);

      expect(a, isNot(equals(b)));
    });

    test(
      'dado que no se asigna coordinador todavia, cuando se construye, coordinadorId es null',
      () {
        expect(construir().coordinadorId, isNull);
      },
    );

    test('dado que la campania es permanente y no tiene fecha de fin, cuando se construye, '
        'fechaFin es null y no se inventa un centinela', () {
      final permanente = Campania(
        id: 'camp-2',
        nombre: 'Permanente',
        tipo: TipoCampania.permanente,
        fechaInicio: DateTime(2026, 12, 1),
        ciudadId: 'ciudad-1',
        auditoria: auditoria,
      );

      expect(permanente.fechaFin, isNull);
      expect(permanente.fechaInicio.isUtc, isTrue);
    });

    test('dado que una con fecha de fin y otra sin, cuando se comparan, no son iguales y las '
        'dos sin fecha de fin si', () {
      final conFin = construir();
      final sinFin = Campania(
        id: 'camp-1',
        nombre: 'Verano 2026',
        tipo: TipoCampania.verano,
        fechaInicio: DateTime(2026, 12, 1),
        ciudadId: 'ciudad-1',
        auditoria: auditoria,
      );
      final otraSinFin = Campania(
        id: 'camp-1',
        nombre: 'Verano 2026',
        tipo: TipoCampania.verano,
        fechaInicio: DateTime(2026, 12, 1),
        ciudadId: 'ciudad-1',
        auditoria: auditoria,
      );

      expect(conFin, isNot(equals(sinFin)));
      expect(sinFin, equals(otraSinFin));
      expect(sinFin.hashCode, equals(otraSinFin.hashCode));
    });

    test('dado que fechaFin es igual a fechaInicio, cuando se construye, es valida (check '
        'fecha_fin >= fecha_inicio)', () {
      final campania = construir(fechaFin: DateTime(2026, 12, 1));

      expect(campania.fechaFin, equals(campania.fechaInicio));
    });

    test('dado que fechaFin es anterior a fechaInicio, cuando se construye, falla el assert', () {
      expect(() => construir(fechaFin: DateTime(2026, 11, 30)), throwsA(isA<AssertionError>()));
    });

    test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () {
      final campania = Campania(
        id: 'camp-1',
        nombre: 'Verano 2026',
        tipo: TipoCampania.verano,
        fechaInicio: DateTime(2026, 12, 1),
        fechaFin: DateTime(2027, 2, 28),
        ciudadId: 'ciudad-1',
        auditoria: Auditoria(
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          deletedAt: DateTime(2026, 1, 2),
        ),
      );

      expect(campania.estaBorrada, isTrue);
    });
  });
}
