// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_duplicado_ubicacion.dart';
import 'package:test/test.dart';

/// Metros → grados de latitud con el radio de la Tierra de `Coordenadas`.
double _grados(double metros) => metros / 111195.08;

Ubicacion _ubicacion({
  String id = 'ub-existente',
  String? calle = 'Av. Italia',
  String? numero = '1234',
  double metrosAlNorte = 0,
  String ciudadId = 'mvd',
  DateTime? deletedAt,
}) => Ubicacion(
  id: id,
  tipo: TipoUbicacion.casa,
  calle: calle,
  numero: numero,
  lat: -34.891 + _grados(metrosAlNorte),
  lon: -56.125,
  ciudadId: ciudadId,
  auditoria: Auditoria(
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
    deletedAt: deletedAt,
  ),
);

void main() {
  const criterio = CriterioDuplicadoUbicacion();
  final nueva = _ubicacion(id: 'ub-nueva');

  group('CriterioDuplicadoUbicacion.esDuplicado', () {
    test('dado "Av. Italia 1234" activa en la misma ciudad a 15 m, cuando se compara, es duplicado '
        '(escenario "Detección de duplicado")', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(metrosAlNorte: 15)), isTrue);
    });

    test('dado la existente a 29,99 m, cuando se compara, es duplicado (radio ≤ 30 m)', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(metrosAlNorte: 29.99)), isTrue);
    });

    test('dado la existente a 31 m, cuando se compara, no es duplicado', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(metrosAlNorte: 31)), isFalse);
    });

    test('dado otra ciudad, cuando se compara, no es duplicado', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(ciudadId: 'canelones')), isFalse);
    });

    test('dado la existente dada de baja, cuando se compara, no es duplicado', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(deletedAt: DateTime.utc(2026, 9, 2))), isFalse);
    });

    test('dado la misma fila (mismo id), cuando se compara, no es duplicado de sí misma', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(id: 'ub-nueva')), isFalse);
    });

    test('dado otro número, cuando se compara, no es duplicado (número exacto)', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(numero: '1236')), isFalse);
    });

    test('dado el número con espacios o en otra caja, cuando se compara, es duplicado', () {
      final conBis = _ubicacion(id: 'ub-nueva', numero: '1234 BIS');

      expect(criterio.esDuplicado(conBis, _ubicacion(numero: '  1234 bis ')), isTrue);
    });

    test(
      'dado la calle con acentos, ñ o mayúsculas distintas, cuando se compara, es duplicado',
      () {
        final conAcentos = _ubicacion(id: 'ub-nueva', calle: 'Avenida  Ñandú Á');

        expect(criterio.esDuplicado(conAcentos, _ubicacion(calle: 'avenida nandu a')), isTrue);
      },
    );

    test('dado "Av. Italia" contra "Av Italia", cuando se compara, es duplicado (similitud ≥ '
        '0,85)', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(calle: 'Av Italia')), isTrue);
    });

    test('dado una calle distinta en el mismo radio y número, cuando se compara, no es '
        'duplicado', () {
      expect(criterio.esDuplicado(nueva, _ubicacion(calle: 'Comercio')), isFalse);
    });

    test('dado que alguna de las dos no tiene calle o número, cuando se compara, no es duplicado '
        '(la cercanía sola marcaría a los vecinos)', () {
      expect(criterio.esDuplicado(_ubicacion(id: 'n', calle: null), _ubicacion()), isFalse);
      expect(criterio.esDuplicado(_ubicacion(id: 'n', numero: null), _ubicacion()), isFalse);
      expect(criterio.esDuplicado(nueva, _ubicacion(calle: null)), isFalse);
      expect(criterio.esDuplicado(nueva, _ubicacion(numero: null)), isFalse);
    });
  });

  group('CriterioDuplicadoUbicacion.candidatas', () {
    test('dado varias existentes, cuando se buscan candidatas, devuelve solo las duplicadas de la '
        'más cercana a la más lejana', () {
      final a20 = _ubicacion(id: 'a20', metrosAlNorte: 20);
      final a5 = _ubicacion(id: 'a5', metrosAlNorte: 5);
      final lejos = _ubicacion(id: 'lejos', metrosAlNorte: 80);

      expect(criterio.candidatas(nueva, [a20, lejos, a5]), [a5, a20]);
    });
  });

  group('CriterioDuplicadoUbicacion — normalización y similitud', () {
    test('dado un texto con acentos, ñ y espacios de más, cuando se normaliza, queda plano', () {
      expect(
        CriterioDuplicadoUbicacion.normalizar('  Güemes   Ñandubay  Él '),
        'guemes nandubay el',
      );
    });

    test('dado dos textos, cuando se mide la similitud, es 1 − distancia / largo mayor', () {
      expect(CriterioDuplicadoUbicacion.similitud('', ''), 1);
      expect(CriterioDuplicadoUbicacion.similitud('abc', 'abc'), 1);
      expect(CriterioDuplicadoUbicacion.similitud('kitten', 'sitting'), closeTo(1 - 3 / 7, 1e-9));
      expect(CriterioDuplicadoUbicacion.similitud('abc', ''), 0);
    });
  });
}
