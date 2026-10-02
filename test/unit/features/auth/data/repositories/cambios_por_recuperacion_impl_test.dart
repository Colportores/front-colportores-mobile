// 15-A07: la única pista para distinguir un enlace ya usado de uno vencido es que este teléfono
// acaba de completar un cambio con un enlace. Se guarda solo el instante, y vale una hora.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cambios_por_recuperacion_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late DateTime ahora;
  late CambiosPorRecuperacionEnAlmacen cambios;

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    ahora = DateTime.utc(2026, 10, 2, 12);
    cambios = CambiosPorRecuperacionEnAlmacen(almacen, ahora: () => ahora, logger: loggerMudo());
  });

  test('sin ningún cambio anotado, no hay uno reciente', () async {
    expect(await cambios.hayUnoReciente(), isFalse);
  });

  test('guarda solo el instante, con la clave propia', () async {
    await cambios.registrar();

    expect(almacen.contenido, {ClaveSegura.cambioPorRecuperacion: ahora.toIso8601String()});
  });

  group('la ventana es la hora de vida del enlace', () {
    for (final (minutos, esperado) in const [
      (0, true),
      (59, true),
      (60, true),
      (61, false),
      (24 * 60, false),
    ]) {
      test('a los $minutos min del cambio: ${esperado ? 'es reciente' : 'ya no'}', () async {
        await cambios.registrar();

        ahora = ahora.add(Duration(minutes: minutos));

        expect(await cambios.hayUnoReciente(), esperado);
      });
    }

    test('si el reloj se atrasó (el cambio queda en el futuro), no cuenta', () async {
      await cambios.registrar();

      ahora = ahora.subtract(const Duration(minutes: 5));

      expect(await cambios.hayUnoReciente(), isFalse);
    });
  });

  test('lo lee una app que se abre de nuevo (arranque en frío)', () async {
    await cambios.registrar();
    ahora = ahora.add(const Duration(minutes: 10));

    final reabierto = CambiosPorRecuperacionEnAlmacen(
      almacen,
      ahora: () => ahora,
      logger: loggerMudo(),
    );

    expect(await reabierto.hayUnoReciente(), isTrue);
  });

  test('un valor ilegible en el almacén se trata como que no hay cambio', () async {
    await almacen.escribir(ClaveSegura.cambioPorRecuperacion, 'no-es-una-fecha');

    expect(await cambios.hayUnoReciente(), isFalse);
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('registrar y leer no lanzan', () async {
      await expectLater(cambios.registrar(), completes);
      almacen.simularFalla = true;
      final otro = CambiosPorRecuperacionEnAlmacen(
        almacen,
        ahora: () => ahora,
        logger: loggerMudo(),
      );

      expect(await otro.hayUnoReciente(), isFalse);
    });

    test('lo anotado en esta corrida cuenta aunque no se haya podido guardar', () async {
      await cambios.registrar();

      expect(await cambios.hayUnoReciente(), isTrue);
    });
  });

  test('CambiosPorRecuperacionEnMemoria sigue la misma regla', () async {
    final memoria = CambiosPorRecuperacionEnMemoria(ahora: () => ahora);
    expect(await memoria.hayUnoReciente(), isFalse);

    await memoria.registrar();
    expect(await memoria.hayUnoReciente(), isTrue);

    ahora = ahora.add(const Duration(minutes: 61));
    expect(await memoria.hayUnoReciente(), isFalse);
  });
}
