// Qué campaña le toca al colportor hoy (HU-AUTH-008, «Cuenta antes», #62): la que frena la jornada y
// la venta, la de «Ya te asignaron» y la que frenó una jornada rechazada. Solo mira fechas.
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:colportores_mobile/features/auth/domain/services/situacion_de_campania.dart';
import 'package:flutter_test/flutter_test.dart';

CampaniaInscripta _campania(
  String id, {
  String? nombre,
  required String inicio,
  String? fin,
  String? zona,
  String? ciudad,
}) => CampaniaInscripta(
  campaniaId: id,
  nombre: nombre ?? 'Campaña $id',
  fechaInicio: inicio,
  fechaFin: fin,
  zona: zona,
  ciudad: ciudad,
);

const _hoy = '2026-11-20';

void main() {
  group('porEmpezar: la campaña que frena la jornada y la venta', () {
    test('con una sola campaña por empezar: esa, con su nombre y el día en dd/mm', () {
      final frena = SituacionDeCampania.porEmpezar([
        _campania('a', nombre: 'Verano 2027', inicio: '2026-12-01', fin: '2027-02-28'),
      ], hoy: _hoy);

      expect(frena?.nombre, 'Verano 2027');
      expect(frena?.fechaInicio, '2026-12-01');
      expect(frena?.diaYMes, '01/12');
    });

    test('sin inscripciones no frena nada (la cuenta pendiente la dice el servidor)', () {
      expect(SituacionDeCampania.porEmpezar(const [], hoy: _hoy), isNull);
    });

    test('con una campaña en curso no frena, aunque haya otra por empezar', () {
      expect(
        SituacionDeCampania.porEmpezar([
          _campania('en-curso', inicio: '2026-10-01', fin: '2026-11-30'),
          _campania('proxima', inicio: '2026-12-01', fin: '2027-02-28'),
        ], hoy: _hoy),
        isNull,
      );
    });

    test('una campaña permanente (sin fin) que ya empezó está en curso y no frena', () {
      expect(
        SituacionDeCampania.porEmpezar([_campania('perm', inicio: '2026-01-01')], hoy: _hoy),
        isNull,
      );
    });

    test('el primer día de la campaña ya no frena, y el último todavía no la termina', () {
      final unica = [_campania('a', inicio: '2026-12-01', fin: '2026-12-31')];

      expect(SituacionDeCampania.porEmpezar(unica, hoy: '2026-11-30')?.nombre, 'Campaña a');
      expect(SituacionDeCampania.porEmpezar(unica, hoy: '2026-12-01'), isNull);
      expect(SituacionDeCampania.porEmpezar(unica, hoy: '2026-12-31'), isNull);
    });

    test('una campaña que ya terminó no cuenta como en curso ni como por empezar', () {
      expect(
        SituacionDeCampania.porEmpezar([
          _campania('vieja', inicio: '2026-01-01', fin: '2026-02-28'),
        ], hoy: _hoy),
        isNull,
      );
    });

    test('con una terminada y otra por empezar frena por la que empieza', () {
      final frena = SituacionDeCampania.porEmpezar([
        _campania('vieja', inicio: '2026-01-01', fin: '2026-02-28'),
        _campania('proxima', nombre: 'Verano 2027', inicio: '2026-12-01'),
      ], hoy: _hoy);

      expect(frena?.nombre, 'Verano 2027');
    });

    test('con varias por empezar, la que empieza primero (y el id desempata)', () {
      final frena = SituacionDeCampania.porEmpezar([
        _campania('c', nombre: 'Tercera', inicio: '2027-03-01'),
        _campania('b', nombre: 'Segunda', inicio: '2026-12-01'),
        _campania('a', nombre: 'Primera', inicio: '2026-12-01'),
      ], hoy: _hoy);

      expect(frena?.nombre, 'Primera');
    });
  });

  group('vigenteOProxima: la campaña de «Ya te asignaron»', () {
    test('la que está en curso, antes que una por empezar', () {
      final elegida = SituacionDeCampania.vigenteOProxima([
        _campania('proxima', inicio: '2026-12-01'),
        _campania('en-curso', inicio: '2026-10-01', fin: '2027-02-28'),
      ], hoy: _hoy);

      expect(elegida?.campaniaId, 'en-curso');
    });

    test('sin ninguna en curso, la que empieza primero', () {
      final elegida = SituacionDeCampania.vigenteOProxima([
        _campania('tarde', inicio: '2027-03-01'),
        _campania('pronto', inicio: '2026-12-01'),
      ], hoy: _hoy);

      expect(elegida?.campaniaId, 'pronto');
    });

    test('con dos en curso, la que empezó última', () {
      final elegida = SituacionDeCampania.vigenteOProxima([
        _campania('vieja', inicio: '2026-09-01'),
        _campania('nueva', inicio: '2026-11-01'),
      ], hoy: _hoy);

      expect(elegida?.campaniaId, 'nueva');
    });

    test('las terminadas no cuentan: sin otra, ninguna', () {
      expect(
        SituacionDeCampania.vigenteOProxima([
          _campania('vieja', inicio: '2026-01-01', fin: '2026-02-28'),
        ], hoy: _hoy),
        isNull,
      );
      expect(SituacionDeCampania.vigenteOProxima(const [], hoy: _hoy), isNull);
    });
  });

  group('queFrenoElDia: la campaña de una jornada rechazada', () {
    test('la que empieza primero después de ese día', () {
      final elegida = SituacionDeCampania.queFrenoElDia([
        _campania('vieja', inicio: '2026-01-01', fin: '2026-02-28'),
        _campania('tarde', inicio: '2027-03-01'),
        _campania('pronto', inicio: '2026-12-01'),
      ], '2026-11-20');

      expect(elegida?.campaniaId, 'pronto');
    });

    test('si ninguna empieza después de ese día, ninguna', () {
      expect(
        SituacionDeCampania.queFrenoElDia([_campania('a', inicio: '2026-10-01')], '2026-11-20'),
        isNull,
      );
    });

    test('empezar el mismo día de la jornada no es empezar después', () {
      expect(
        SituacionDeCampania.queFrenoElDia([_campania('a', inicio: '2026-11-20')], '2026-11-20'),
        isNull,
      );
    });
  });

  test('diaYMesDe: dd/mm de un día AAAA-MM-DD; algo que no es fecha queda como vino', () {
    expect(diaYMesDe('2026-12-01'), '01/12');
    expect(diaYMesDe('2027-01-04'), '04/01');
    expect(diaYMesDe('mañana'), 'mañana');
  });
}
