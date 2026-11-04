// El reinicio de la raíz de la app (HU-SYNC-006, decisión de Cristian, 04/11, «Motor vivo»): tira el
// `ProviderScope` entero y arma uno nuevo, como el primer arranque. Nada del anterior queda vivo, y
// nunca hay dos raíces a la vez.
import 'dart:async';

import 'package:colportores_mobile/core/arranque/reinicio_de_raiz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Qué le pasó a cada arranque de la raíz, en orden.
final _eventos = <String>[];

class _Contador {
  int arranques = 0;
}

/// Cuántas veces se armó la raíz (cada `construir`).
final _contadorProvider = Provider<_Contador>((ref) => _Contador());

class _Toques extends Notifier<int> {
  @override
  int build() => 0;

  void sumar() => state++;
}

final _toquesProvider = NotifierProvider<_Toques, int>(_Toques.new);

/// Lo que vive en cada arranque: se anota cuándo nace y cuándo se tira.
class _Pantalla extends ConsumerStatefulWidget {
  const _Pantalla();

  @override
  ConsumerState<_Pantalla> createState() => _PantallaState();
}

class _PantallaState extends ConsumerState<_Pantalla> {
  late final int _numero;

  @override
  void initState() {
    super.initState();
    _numero = ref.read(_contadorProvider).arranques;
    _eventos.add('nace $_numero');
  }

  @override
  void dispose() {
    _eventos.add('se tira $_numero');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cuenta = ref.watch(_toquesProvider);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Text('arranque $_numero · toques $cuenta', key: const Key('estado')),
          GestureDetector(
            key: const Key('tocar'),
            onTap: () => ref.read(_toquesProvider.notifier).sumar(),
            child: const Text('tocar'),
          ),
          GestureDetector(
            key: const Key('reiniciar'),
            onTap: () => ref.read(reiniciarRaizProvider)(),
            child: const Text('reiniciar'),
          ),
        ],
      ),
    );
  }
}

void main() {
  late _Contador contador;

  Widget raiz() => ReiniciadorDeRaiz(
    overrides: () {
      contador.arranques++;
      return [_contadorProvider.overrideWithValue(contador)];
    },
    child: const _Pantalla(),
  );

  Finder estado() => find.byKey(const Key('estado'));

  setUp(() {
    contador = _Contador();
    _eventos.clear();
  });

  testWidgets('arranca una sola vez y no vuelve a armarse solo', (tester) async {
    await tester.pumpWidget(raiz());
    await tester.pump(const Duration(seconds: 1));

    expect(contador.arranques, 1);
    expect(_eventos, ['nace 1']);
  });

  testWidgets('reiniciar tira el estado de todos los providers: arranca como la primera vez', (
    tester,
  ) async {
    await tester.pumpWidget(raiz());
    await tester.tap(find.byKey(const Key('tocar')));
    await tester.tap(find.byKey(const Key('tocar')));
    await tester.pump();
    expect(tester.widget<Text>(estado()).data, 'arranque 1 · toques 2');
    final contenedorAntes = ProviderScope.containerOf(tester.element(find.byType(_Pantalla)));

    await tester.tap(find.byKey(const Key('reiniciar')));
    await tester.pump();
    await tester.pump();

    expect(tester.widget<Text>(estado()).data, 'arranque 2 · toques 0');
    final contenedorDespues = ProviderScope.containerOf(tester.element(find.byType(_Pantalla)));
    expect(contenedorDespues, isNot(same(contenedorAntes)), reason: 'un ProviderScope nuevo');
    expect(contador.arranques, 2);
  });

  testWidgets('nunca hay dos raíces a la vez: la vieja se tira antes de armar la nueva', (
    tester,
  ) async {
    await tester.pumpWidget(raiz());

    await tester.tap(find.byKey(const Key('reiniciar')));
    await tester.pump();
    expect(find.byType(_Pantalla), findsNothing, reason: 'primero se saca la raíz vieja');
    expect(_eventos, ['nace 1', 'se tira 1']);

    await tester.pump();
    expect(find.byType(_Pantalla), findsOneWidget);
    expect(_eventos, ['nace 1', 'se tira 1', 'nace 2']);
  });

  testWidgets('pedirlo dos veces seguidas reinicia una sola vez', (tester) async {
    await tester.pumpWidget(raiz());
    final contenedor = ProviderScope.containerOf(tester.element(find.byType(_Pantalla)));
    final pedir = contenedor.read(reiniciarRaizProvider);

    pedir();
    pedir();
    await tester.pump();
    await tester.pump();

    expect(contador.arranques, 2);
    expect(_eventos, ['nace 1', 'se tira 1', 'nace 2']);
  });

  testWidgets('se puede reiniciar de nuevo después de un reinicio', (tester) async {
    await tester.pumpWidget(raiz());

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('reiniciar')));
      await tester.pump();
      await tester.pump();
    }

    expect(contador.arranques, 4);
    expect(tester.widget<Text>(estado()).data, 'arranque 4 · toques 0');
  });

  testWidgets('si la app se cierra con el reinicio a medias, no lanza', (tester) async {
    await tester.pumpWidget(raiz());
    await tester.tap(find.byKey(const Key('reiniciar')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(_Pantalla), findsNothing);
    expect(_eventos, ['nace 1', 'se tira 1'], reason: 'la raíz nueva nunca llegó a montarse');
  });

  group('alTirar: cerrar la base de la raíz que se tiró (HU-AUTH-006)', () {
    Widget raizConCierre(Future<void> Function() alTirar) => ReiniciadorDeRaiz(
      alTirar: alTirar,
      overrides: () {
        contador.arranques++;
        return [_contadorProvider.overrideWithValue(contador)];
      },
      child: const _Pantalla(),
    );

    testWidgets('el orden es: se tira 1, cierra 1, nace 2', (tester) async {
      await tester.pumpWidget(
        raizConCierre(() async {
          _eventos.add('cierra ${contador.arranques}');
        }),
      );

      await tester.tap(find.byKey(const Key('reiniciar')));
      await tester.pump();
      await tester.pump();

      expect(_eventos, ['nace 1', 'se tira 1', 'cierra 1', 'nace 2']);
    });

    testWidgets('la raíz nueva no se arma hasta que el cierre termina', (tester) async {
      final cierre = Completer<void>();
      await tester.pumpWidget(
        raizConCierre(() {
          _eventos.add('cierra ${contador.arranques}');
          return cierre.future;
        }),
      );

      await tester.tap(find.byKey(const Key('reiniciar')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(_eventos, ['nace 1', 'se tira 1', 'cierra 1']);
      expect(
        contador.arranques,
        1,
        reason: 'sus overrides (con un helper nuevo) aún no se armaron',
      );
      expect(find.byType(_Pantalla), findsNothing);

      cierre.complete();
      await tester.pump();
      await tester.pump();

      expect(_eventos, ['nace 1', 'se tira 1', 'cierra 1', 'nace 2']);
      expect(contador.arranques, 2);
    });

    testWidgets('un alTirar que lanza no frena el arranque de la raíz nueva', (tester) async {
      await tester.pumpWidget(
        raizConCierre(() async {
          _eventos.add('cierra ${contador.arranques}');
          throw StateError('no se pudo cerrar la base');
        }),
      );

      await tester.tap(find.byKey(const Key('reiniciar')));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_eventos, ['nace 1', 'se tira 1', 'cierra 1', 'nace 2']);
      expect(tester.widget<Text>(estado()).data, 'arranque 2 · toques 0');
    });

    testWidgets('pedirlo otra vez mientras se cierra no cierra ni reinicia dos veces', (
      tester,
    ) async {
      final cierre = Completer<void>();
      await tester.pumpWidget(
        raizConCierre(() {
          _eventos.add('cierra ${contador.arranques}');
          return cierre.future;
        }),
      );
      final pedir = ProviderScope.containerOf(
        tester.element(find.byType(_Pantalla)),
      ).read(reiniciarRaizProvider);

      pedir();
      await tester.pump();
      pedir();
      await tester.pump();
      cierre.complete();
      await tester.pump();
      await tester.pump();

      expect(_eventos, ['nace 1', 'se tira 1', 'cierra 1', 'nace 2']);
      expect(contador.arranques, 2);
    });

    testWidgets('si la app se cierra mientras la base se cierra, no arma nada ni lanza', (
      tester,
    ) async {
      final cierre = Completer<void>();
      await tester.pumpWidget(
        raizConCierre(() {
          _eventos.add('cierra ${contador.arranques}');
          return cierre.future;
        }),
      );
      await tester.tap(find.byKey(const Key('reiniciar')));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      cierre.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_eventos, ['nace 1', 'se tira 1', 'cierra 1']);
      expect(contador.arranques, 1);
    });

    testWidgets('se puede reiniciar varias veces: cada raíz cierra la suya', (tester) async {
      await tester.pumpWidget(
        raizConCierre(() async {
          _eventos.add('cierra ${contador.arranques}');
        }),
      );

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('reiniciar')));
        await tester.pump();
        await tester.pump();
      }

      expect(_eventos.where((e) => e.startsWith('cierra')), ['cierra 1', 'cierra 2', 'cierra 3']);
      expect(contador.arranques, 4);
    });
  });

  test('sin un reiniciador (una pantalla suelta) pedir el reinicio no hace nada ni lanza', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(() => c.read(reiniciarRaizProvider)(), returnsNormally);
  });
}
