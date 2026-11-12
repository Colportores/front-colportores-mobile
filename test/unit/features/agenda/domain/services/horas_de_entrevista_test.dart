// Las reglas de las horas de una entrevista (vista 39, R·06 y R·07).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/services/horas_de_entrevista.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final entrada = DateTime(2026, 10, 23, 14, 23);
  final ahora = DateTime(2026, 10, 23, 15);

  group('validar', () {
    test('una salida entre la entrada y ahora vale', () {
      expect(
        HorasDeEntrevista.validar(
          entrada: entrada,
          salida: DateTime(2026, 10, 23, 14, 41),
          ahora: ahora,
        ),
        isNull,
      );
    });

    test('la salida en el mismo minuto de la entrada o de ahora vale (se compara al minuto)', () {
      expect(
        HorasDeEntrevista.validar(
          entrada: entrada,
          salida: DateTime(2026, 10, 23, 14, 23, 50),
          ahora: ahora,
        ),
        isNull,
      );
      expect(
        HorasDeEntrevista.validar(
          entrada: entrada,
          salida: DateTime(2026, 10, 23, 15, 0, 40),
          ahora: DateTime(2026, 10, 23, 15, 0, 10),
        ),
        isNull,
      );
    });

    test('una salida antes de la entrada no vale y dice qué hacer', () {
      final falla = HorasDeEntrevista.validar(
        entrada: entrada,
        salida: DateTime(2026, 10, 23, 14, 22),
        ahora: ahora,
      );

      expect(falla, isA<FailureValidacion>());
      expect(
        falla!.mensaje,
        'La salida no puede ser antes de la entrada. Corregí una de las dos horas.',
      );
    });

    test('una salida que todavía no pasó no vale', () {
      final falla = HorasDeEntrevista.validar(
        entrada: entrada,
        salida: DateTime(2026, 10, 23, 15, 1),
        ahora: ahora,
      );

      expect(falla, isA<FailureValidacion>());
      expect((falla! as FailureValidacion).campos.keys, ['salida']);
    });

    test('más de 12 horas no vale; justo 12 sí', () {
      final tarde = DateTime(2026, 10, 24, 12);
      final demasiado = HorasDeEntrevista.validar(
        entrada: entrada,
        salida: DateTime(2026, 10, 24, 2, 24),
        ahora: tarde,
      );
      expect(demasiado, isA<FailureValidacion>());
      expect(demasiado!.mensaje, contains('12 horas'));
      expect(
        HorasDeEntrevista.validar(
          entrada: entrada,
          salida: DateTime(2026, 10, 24, 2, 23),
          ahora: tarde,
        ),
        isNull,
      );
    });

    test('cruzar la medianoche vale si no pasa de 12 h', () {
      expect(
        HorasDeEntrevista.validar(
          entrada: DateTime(2026, 10, 23, 23, 50),
          salida: DateTime(2026, 10, 24, 0, 10),
          ahora: DateTime(2026, 10, 24, 0, 30),
        ),
        isNull,
      );
    });
  });

  group('topeDeLaSalida', () {
    test('es ahora si la entrevista es corta', () {
      expect(HorasDeEntrevista.topeDeLaSalida(entrada: entrada, ahora: ahora), ahora);
    });

    test('es entrada + 12 h si pasó más tiempo', () {
      expect(
        HorasDeEntrevista.topeDeLaSalida(entrada: entrada, ahora: DateTime(2026, 10, 25)),
        DateTime(2026, 10, 24, 2, 23),
      );
    });
  });

  test('alMinuto descarta los segundos', () {
    expect(
      HorasDeEntrevista.alMinuto(DateTime(2026, 10, 23, 14, 41, 59, 999)),
      DateTime(2026, 10, 23, 14, 41),
    );
  });
}
