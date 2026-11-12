// Vista 39, R·02: la fecha que se sugiere por las entrevistas cercanas (función pura).
import 'package:colportores_mobile/features/agenda/domain/entities/entrevista_cercana.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/services/sugeridor_de_fecha.dart';
import 'package:test/test.dart';

// Viernes 23/10/2026, 14:35 (hora local del test).
final _ahora = DateTime(2026, 10, 23, 14, 35);

EntrevistaCercana _a(int dia, int hora, [int minuto = 0, String? slot]) =>
    EntrevistaCercana(fecha: DateTime(2026, 10, dia, hora, minuto), slotCodigo: slot);

void main() {
  group('dado que no hay entrevistas cerca', () {
    test('cuando la lista está vacía, entonces no se sugiere nada', () {
      expect(SugeridorDeFecha.calcular(const [], ahora: _ahora), isNull);
    });

    test('cuando todas son anteriores a ahora, entonces no se sugiere nada', () {
      expect(SugeridorDeFecha.calcular([_a(23, 9), _a(23, 14, 34)], ahora: _ahora), isNull);
    });
  });

  group('dado un día con entrevistas cerca', () {
    test(
      'cuando hay dos en la misma franja, entonces sugiere ese día al comienzo de la franja',
      () {
        final s = SugeridorDeFecha.calcular([_a(26, 10, 15), _a(26, 11)], ahora: _ahora)!;
        expect(s.momento, DateTime(2026, 10, 26, 10));
        expect(s.cantidad, 2);
        expect(s.franja, FranjaHoraria.mediaManiana);
      },
    );

    test('cuando la entrevista trae su franja, entonces gana sobre la que da su hora', () {
      // 14:30 caería en «Primera tarde»; el código guardado dice «Media mañana».
      final s = SugeridorDeFecha.calcular([_a(26, 14, 30, 'mid_morning')], ahora: _ahora)!;
      expect(s.franja, FranjaHoraria.mediaManiana);
    });

    test('cuando la hora cae en un hueco, entonces toma la franja que sigue', () {
      final s = SugeridorDeFecha.calcular([_a(26, 14, 30)], ahora: _ahora)!;
      expect(s.franja, FranjaHoraria.primeraTarde);
      expect(s.momento, DateTime(2026, 10, 26, 16, 30));
    });

    test('cuando hay una sola, entonces la cantidad es 1', () {
      expect(SugeridorDeFecha.calcular([_a(26, 10)], ahora: _ahora)!.cantidad, 1);
    });

    test(
      'cuando una sola entrevista cae después de la última franja, entonces sugiere su hora',
      () {
        final s = SugeridorDeFecha.calcular([_a(26, 21, 15)], ahora: _ahora)!;
        expect(s.franja, isNull);
        expect(s.momento, DateTime(2026, 10, 26, 21, 15));
      },
    );

    test('cuando las franjas de un día empatan, entonces elige la más temprana', () {
      final s = SugeridorDeFecha.calcular([_a(26, 17), _a(26, 9)], ahora: _ahora)!;
      expect(s.franja, FranjaHoraria.primeraManiana);
      expect(s.cantidad, 2);
    });

    test('cuando una franja tiene más entrevistas, entonces gana aunque sea más tarde', () {
      final s = SugeridorDeFecha.calcular([_a(26, 9), _a(26, 17), _a(26, 17, 30)], ahora: _ahora)!;
      expect(s.franja, FranjaHoraria.primeraTarde);
      expect(s.cantidad, 3);
    });
  });

  group('dado más de un día con entrevistas cerca', () {
    test('cuando uno tiene más, entonces gana ese aunque sea más lejano', () {
      final s = SugeridorDeFecha.calcular([
        _a(24, 10),
        _a(28, 10),
        _a(28, 11),
        _a(28, 17),
      ], ahora: _ahora)!;
      expect(s.momento.day, 28);
      expect(s.cantidad, 3);
    });

    test('cuando empatan en cantidad, entonces gana el más próximo', () {
      final s = SugeridorDeFecha.calcular([
        _a(29, 10),
        _a(29, 11),
        _a(26, 10),
        _a(26, 11),
      ], ahora: _ahora)!;
      expect(s.momento.day, 26);
    });

    test('cuando llegan desordenadas, entonces el resultado es el mismo', () {
      final lista = [_a(29, 11), _a(26, 10), _a(29, 10), _a(26, 11)];
      expect(
        SugeridorDeFecha.calcular(lista.reversed, ahora: _ahora),
        SugeridorDeFecha.calcular(lista, ahora: _ahora),
      );
    });
  });

  group('dado que hay entrevistas cerca para hoy', () {
    test('cuando la franja todavía no empezó, entonces se sugiere hoy a su comienzo', () {
      expect(
        SugeridorDeFecha.calcular([_a(23, 15)], ahora: _ahora)!.momento,
        DateTime(2026, 10, 23, 16, 30),
      );
    });

    test('cuando quedan fuera de franja pero en el futuro, entonces se sugiere su hora', () {
      expect(
        SugeridorDeFecha.calcular([_a(23, 20, 45)], ahora: _ahora)!.momento,
        DateTime(2026, 10, 23, 20, 45),
      );
    });

    test('cuando la franja ya empezó, entonces hoy no se sugiere y se cae a otro día', () {
      final tarde = DateTime(2026, 10, 23, 17);
      expect(SugeridorDeFecha.calcular([_a(23, 17, 30)], ahora: tarde), isNull);
      expect(
        SugeridorDeFecha.calcular([_a(23, 17, 30), _a(26, 10)], ahora: tarde)!.momento.day,
        26,
      );
    });
  });
}
