// De qué campaña es una jornada (HU-JOR-003: la lista de acompañantes; HU-JOR-002: la tendencia): la
// inscripción en curso el día en que empezó, en el día de Montevideo.
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/jornada/domain/services/campania_de_la_jornada.dart';
import 'package:flutter_test/flutter_test.dart';

CampaniaInscripta _c(String id, String inicio, [String? fin]) =>
    CampaniaInscripta(campaniaId: id, nombre: id, fechaInicio: inicio, fechaFin: fin);

void main() {
  final enNoviembre = DateTime.utc(2026, 11, 20, 15);

  test('dada una campaña en curso ese día, es esa', () {
    final c = CampaniaDeLaJornada.de([_c('verano', '2026-11-01', '2026-11-30')], enNoviembre);

    expect(c?.campaniaId, 'verano');
  });

  test('una campaña permanente (sin fin) cubre cualquier día desde su inicio', () {
    expect(CampaniaDeLaJornada.de([_c('perm', '2026-01-01')], enNoviembre)?.campaniaId, 'perm');
  });

  test('con dos en curso gana la que empezó más tarde, y a igual inicio la de menor id', () {
    final a = _c('a', '2026-10-01');
    final b = _c('b', '2026-11-10');
    final c = _c('c', '2026-11-10');

    expect(CampaniaDeLaJornada.de([a, c, b], enNoviembre)?.campaniaId, 'b');
  });

  test('una campaña que ya terminó o que todavía no empezó no es la de la jornada', () {
    final c = CampaniaDeLaJornada.de([
      _c('vieja', '2026-01-01', '2026-02-28'),
      _c('futura', '2026-12-01', '2026-12-31'),
    ], enNoviembre);

    expect(c, isNull);
  });

  test('sin poder leer las inscripciones no se sabe: null', () {
    expect(CampaniaDeLaJornada.de(null, enNoviembre), isNull);
  });

  test('el día es el de Montevideo: a las 01:00 UTC del 1/12 todavía es 30/11', () {
    final c = CampaniaDeLaJornada.de([
      _c('noviembre', '2026-11-01', '2026-11-30'),
    ], DateTime.utc(2026, 12, 1, 1));

    expect(c?.campaniaId, 'noviembre');
  });
}
