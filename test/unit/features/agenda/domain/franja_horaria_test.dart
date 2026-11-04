// HU-VIS-001 (#408): las seis franjas de §8.5.2 y cuál se recomienda para una hora.
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:flutter_test/flutter_test.dart';

int _m(int h, int m) => h * 60 + m;

void main() {
  group('FranjaHoraria', () {
    test('dado el catálogo, cuando se listan, entonces son las seis de §8.5.2 con su código', () {
      expect(FranjaHoraria.values.map((f) => f.codigo), [
        'early_morning',
        'mid_morning',
        'late_morning',
        'early_afternoon',
        'mid_afternoon',
        'late_afternoon',
      ]);
      expect(FranjaHoraria.primeraTarde.rango, '16:30 a 18:00');
      expect(FranjaHoraria.primeraManiana.rango, '08:30 a 10:00');
      expect(FranjaHoraria.finDeTarde.rango, '19:15 a 20:30');
    });

    test('dada cada franja, cuando se busca su código, entonces vuelve la misma', () {
      for (final f in FranjaHoraria.values) {
        expect(FranjaHoraria.desdeCodigo(f.codigo), f);
      }
      expect(FranjaHoraria.desdeCodigo('otra'), isNull);
      expect(FranjaHoraria.desdeCodigo(null), isNull);
    });

    test('dada una hora dentro de una franja, cuando se sugiere, entonces es esa', () {
      expect(FranjaHoraria.sugeridaPara(_m(10, 0)), FranjaHoraria.mediaManiana);
      expect(FranjaHoraria.sugeridaPara(_m(11, 29)), FranjaHoraria.mediaManiana);
      expect(FranjaHoraria.sugeridaPara(_m(11, 30)), FranjaHoraria.finDeManiana);
      expect(FranjaHoraria.sugeridaPara(_m(17, 59)), FranjaHoraria.primeraTarde);
      expect(FranjaHoraria.sugeridaPara(_m(18, 0)), FranjaHoraria.mediaTarde);
      expect(FranjaHoraria.sugeridaPara(_m(20, 29)), FranjaHoraria.finDeTarde);
    });

    test('dada una hora en un hueco, cuando se sugiere, entonces es la franja que sigue', () {
      // El canvas 23A·01 dibuja 14:30 con «Primera tarde».
      expect(FranjaHoraria.sugeridaPara(_m(14, 30)), FranjaHoraria.primeraTarde);
      expect(FranjaHoraria.sugeridaPara(_m(13, 30)), FranjaHoraria.primeraTarde);
      expect(FranjaHoraria.sugeridaPara(_m(16, 29)), FranjaHoraria.primeraTarde);
    });

    test('dada una hora antes de las 08:30, cuando se sugiere, entonces es la primera del día', () {
      expect(FranjaHoraria.sugeridaPara(0), FranjaHoraria.primeraManiana);
      expect(FranjaHoraria.sugeridaPara(_m(8, 29)), FranjaHoraria.primeraManiana);
    });

    test('dada una hora desde las 20:30, cuando se sugiere, entonces no hay franja', () {
      expect(FranjaHoraria.sugeridaPara(_m(20, 30)), isNull);
      expect(FranjaHoraria.sugeridaPara(_m(23, 59)), isNull);
    });
  });
}
