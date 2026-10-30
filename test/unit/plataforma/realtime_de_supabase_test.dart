// `RealtimeDeSupabase`: el puerto de Realtime del motor sobre una fuente de cambios. La fuente de
// verdad (`supabase_flutter`) se reemplaza por una que el test maneja.
import 'dart:async';

import 'package:colportores_mobile/plataforma/realtime_de_supabase.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una fuente que deja ver a qué se suscribió el puerto y emitir como si fuera el servidor.
final class _FuenteFalsa implements FuenteDeCambios {
  final suscripciones = <List<String>>[];
  final cierres = <int>[];
  final _alCambiar = <void Function(String)>[];
  final _alReconectar = <void Function()>[];
  final _alFallar = <void Function(Object)>[];

  /// Si el cierre del canal falla (un canal que ya estaba caído).
  bool falloAlCerrar = false;

  @override
  Future<void> Function() escuchar(
    List<String> tablas, {
    required void Function(String tabla) alCambiar,
    required void Function() alReconectar,
    required void Function(Object error) alFallar,
  }) {
    final numero = suscripciones.length;
    suscripciones.add(List.of(tablas));
    _alCambiar.add(alCambiar);
    _alReconectar.add(alReconectar);
    _alFallar.add(alFallar);
    return () async {
      cierres.add(numero);
      if (falloAlCerrar) throw StateError('canal caído');
    };
  }

  void cambio(String tabla, {int suscripcion = 0}) => _alCambiar[suscripcion](tabla);

  void reconectado({int suscripcion = 0}) => _alReconectar[suscripcion]();

  void cayo({int suscripcion = 0}) => _alFallar[suscripcion](StateError('sin red'));
}

void main() {
  late _FuenteFalsa fuente;
  late RealtimeDeSupabase puerto;

  setUp(() {
    fuente = _FuenteFalsa();
    puerto = RealtimeDeSupabase(fuente);
  });

  Future<List<String>> recoger(Stream<String> timbres, Future<void> Function() accion) async {
    final vistos = <String>[];
    final sub = timbres.listen(vistos.add);
    await accion();
    await pumpEventQueue();
    await sub.cancel();
    return vistos;
  }

  test('se suscribe a las tablas que le pide el motor', () {
    puerto.subscribe(['producto', 'precio_por_ciudad']);

    expect(fuente.suscripciones, [
      ['producto', 'precio_por_ciudad'],
    ]);
  });

  test('cada cambio de una tabla es un timbre con su nombre, y nada más', () async {
    final timbres = puerto.subscribe(['producto', 'precio_por_ciudad']);

    final vistos = await recoger(timbres, () async {
      fuente.cambio('precio_por_ciudad');
      fuente.cambio('producto');
      fuente.cambio('precio_por_ciudad');
    });

    expect(vistos, ['precio_por_ciudad', 'producto', 'precio_por_ciudad']);
  });

  test('volver a suscribirse reemplaza la anterior: la vieja se cierra y ya no avisa', () async {
    final primeros = <String>[];
    final primera = puerto.subscribe(['producto']).listen(primeros.add);
    final timbres = puerto.subscribe(['producto', 'precio_por_ciudad']);

    final vistos = await recoger(timbres, () async {
      fuente.cambio('producto', suscripcion: 0); // evento tardío de la canal vieja
      fuente.cambio('precio_por_ciudad', suscripcion: 1);
    });
    await primera.cancel();

    expect(fuente.cierres, [0]);
    expect(primeros, isEmpty);
    expect(vistos, ['precio_por_ciudad']);
  });

  test(
    'al reconectar después de una caída avisa, porque los eventos de la caída se perdieron',
    () async {
      final timbres = puerto.subscribe(['producto', 'precio_por_ciudad']);

      final vistos = await recoger(timbres, () async {
        fuente.cayo();
        fuente.reconectado();
      });

      expect(vistos, hasLength(1));
    },
  );

  test('una caída sola no avisa ni tira nada: el próximo pull trae lo que falte', () async {
    final timbres = puerto.subscribe(['producto']);

    final vistos = await recoger(timbres, () async => fuente.cayo());

    expect(vistos, isEmpty);
  });

  test('unsubscribe cierra el canal y corta el flujo', () async {
    final cerrado = Completer<void>();
    final timbres = puerto.subscribe(['producto']);
    timbres.listen((_) {}, onDone: cerrado.complete);

    await puerto.unsubscribe();
    fuente.cambio('producto'); // tardío: nadie lo ve

    await cerrado.future.timeout(const Duration(seconds: 2));
    expect(fuente.cierres, [0]);
  });

  test('unsubscribe sin haberse suscripto no hace nada', () async {
    await puerto.unsubscribe();

    expect(fuente.cierres, isEmpty);
  });

  test('cerrar un canal que ya estaba caído no tira el motor', () async {
    fuente.falloAlCerrar = true;
    puerto.subscribe(['producto']);

    await puerto.unsubscribe();
    await pumpEventQueue();

    expect(fuente.cierres, [0]);
  });

  test('sin tablas no abre ningún canal', () {
    puerto.subscribe([]);

    expect(fuente.suscripciones, isEmpty);
  });
}
