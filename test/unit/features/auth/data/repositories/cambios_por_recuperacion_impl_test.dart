// 15-A07: la única pista para distinguir un enlace ya usado de uno vencido es que este teléfono
// acaba de completar un cambio con un enlace. Se guarda solo el instante, y vale una hora. La hora
// sale del reloj de la sesión (no vuelve atrás) y las operaciones salen en el orden en que se piden.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'package:colportores_mobile/features/auth/data/repositories/cambios_por_recuperacion_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Almacén donde escribir y leer tardan, para probar el orden de las operaciones. La primera
/// escritura tarda más que las siguientes: sin una cola, la segunda terminaría antes y la primera
/// la pisaría.
final class _AlmacenLento implements AlmacenSeguro {
  final AlmacenSeguroEnMemoria _real = AlmacenSeguroEnMemoria();
  int _escrituras = 0;

  @override
  Future<String?> leer(ClaveSegura clave) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _real.leer(clave);
  }

  @override
  Future<void> escribir(ClaveSegura clave, String valor) async {
    await Future<void>.delayed(Duration(milliseconds: _escrituras++ == 0 ? 80 : 10));
    return _real.escribir(clave, valor);
  }

  @override
  Future<void> borrar(ClaveSegura clave) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return _real.borrar(clave);
  }

  @override
  Future<void> borrarTodo() => _real.borrarTodo();
}

void main() {
  late AlmacenSeguroEnMemoria almacen;
  late DateTime ahora;
  late RelojSesionEnMemoria reloj;
  late CambiosPorRecuperacionEnAlmacen cambios;

  CambiosPorRecuperacionEnAlmacen nuevo(AlmacenSeguro a, RelojSesionEnMemoria r) =>
      CambiosPorRecuperacionEnAlmacen(a, r, logger: loggerMudo());

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    ahora = DateTime.utc(2026, 10, 2, 12);
    reloj = RelojSesionEnMemoria(sistema: () => ahora);
    cambios = nuevo(almacen, reloj);
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

    test('una marca guardada que quedó en el futuro no cuenta', () async {
      await almacen.escribir(
        ClaveSegura.cambioPorRecuperacion,
        ahora.add(const Duration(minutes: 5)).toIso8601String(),
      );

      expect(await cambios.hayUnoReciente(), isFalse);
    });
  });

  group('el reloj de la sesión no vuelve atrás', () {
    test('si el teléfono atrasa la hora, la marca no queda en el futuro ni se estira', () async {
      await cambios.registrar();

      // Pasan 30 minutos (el reloj de la sesión los ve) y después el teléfono atrasa la hora un día.
      ahora = ahora.add(const Duration(minutes: 30));
      expect(await cambios.hayUnoReciente(), isTrue);
      ahora = ahora.subtract(const Duration(days: 1));

      // El reloj sigue en las 12:30: la marca sigue vigente, pero no se estira con el atraso.
      expect(await cambios.hayUnoReciente(), isTrue);
      ahora = ahora.add(const Duration(days: 1, minutes: 31));
      expect(await cambios.hayUnoReciente(), isFalse, reason: 'pasada la hora, vence igual');
    });

    test(
      'registra con la hora que ya había visto el reloj aunque el sistema vaya atrasado',
      () async {
        await reloj.registrar(ahora.add(const Duration(hours: 3)));
        ahora = ahora.subtract(const Duration(days: 2));

        await cambios.registrar();

        expect(almacen.contenido, {
          ClaveSegura.cambioPorRecuperacion: DateTime.utc(2026, 10, 2, 15).toIso8601String(),
        });
      },
    );
  });

  test('lo lee una app que se abre de nuevo (arranque en frío)', () async {
    await cambios.registrar();
    ahora = ahora.add(const Duration(minutes: 10));

    final reabierto = nuevo(almacen, RelojSesionEnMemoria(sistema: () => ahora));

    expect(await reabierto.hayUnoReciente(), isTrue);
  });

  test('un valor ilegible en el almacén se trata como que no hay cambio', () async {
    await almacen.escribir(ClaveSegura.cambioPorRecuperacion, 'no-es-una-fecha');

    expect(await cambios.hayUnoReciente(), isFalse);
  });

  group('olvidar (borrar los datos locales)', () {
    test('borra la marca del almacén y de la memoria: no queda ningún rastro', () async {
      await cambios.registrar();
      expect(await cambios.hayUnoReciente(), isTrue);

      await cambios.olvidar();

      expect(almacen.contenido, isEmpty);
      expect(await cambios.hayUnoReciente(), isFalse, reason: '_enMemoria también se borra');
    });

    test('sin nada anotado no falla', () async {
      await expectLater(cambios.olvidar(), completes);
      expect(await cambios.hayUnoReciente(), isFalse);
    });

    test('con el almacén roto no lanza (el borrado fallido queda en el log)', () async {
      await cambios.registrar();
      almacen.simularFalla = true;

      await expectLater(cambios.olvidar(), completes);
    });

    test('un registro y un olvido seguidos, sin esperar: queda olvidado', () async {
      final lento = _AlmacenLento();
      final c = nuevo(lento, reloj);

      final registro = c.registrar();
      final olvido = c.olvidar();
      await Future.wait([registro, olvido]);

      expect(await c.hayUnoReciente(), isFalse);
      expect(await lento.leer(ClaveSegura.cambioPorRecuperacion), isNull);
    });
  });

  group('en el orden en que se piden', () {
    test('un otp_expired que llega justo después del cambio ya ve la marca', () async {
      final lento = _AlmacenLento();
      final c = nuevo(lento, reloj);

      final registro = c.registrar();
      final consulta = c.hayUnoReciente();
      await registro;

      expect(await consulta, isTrue);
    });

    test('dos registros seguidos, el primero con la escritura más lenta: gana el último', () async {
      final lento = _AlmacenLento();
      var llamadas = 0;
      final base = ahora;
      final c = nuevo(
        lento,
        RelojSesionEnMemoria(sistema: () => base.add(Duration(minutes: llamadas++))),
      );

      await Future.wait([c.registrar(), c.registrar()]);

      expect(
        await lento.leer(ClaveSegura.cambioPorRecuperacion),
        base.add(const Duration(minutes: 1)).toIso8601String(),
      );
    });
  });

  group('con el almacén roto', () {
    setUp(() => almacen.simularFalla = true);

    test('registrar y leer no lanzan', () async {
      await expectLater(cambios.registrar(), completes);
      almacen.simularFalla = true;
      final otro = nuevo(almacen, reloj);

      expect(await otro.hayUnoReciente(), isFalse);
    });

    test('lo anotado en esta corrida cuenta aunque no se haya podido guardar', () async {
      await cambios.registrar();

      expect(await cambios.hayUnoReciente(), isTrue);
    });
  });

  group('CambiosPorRecuperacionEnMemoria sigue la misma regla', () {
    test('ventana de una hora', () async {
      final memoria = CambiosPorRecuperacionEnMemoria(ahora: () => ahora);
      expect(await memoria.hayUnoReciente(), isFalse);

      await memoria.registrar();
      expect(await memoria.hayUnoReciente(), isTrue);

      ahora = ahora.add(const Duration(minutes: 61));
      expect(await memoria.hayUnoReciente(), isFalse);
    });

    test('olvidar la borra', () async {
      final memoria = CambiosPorRecuperacionEnMemoria(ahora: () => ahora);
      await memoria.registrar();

      await memoria.olvidar();

      expect(await memoria.hayUnoReciente(), isFalse);
    });
  });
}
