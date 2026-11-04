// HU-NOT-003 (#187) — 24C·08, «Aviso con la app abierta»: el aviso sutil de arriba cuando llega una
// push con la app al frente. Tarjeta con el glifo, «AHORA», el título y «Tocá para ver el detalle»;
// tocarla abre el aviso, la ✕ la cierra, y el aviso siempre queda en el centro.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/push_remotas_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/aviso_push_en_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Notificacion _aviso(
  String id, {
  String titulo = 'Tu pedido fue autorizado',
  String? detalle,
  DestinoNotificacion? destino,
}) => Notificacion(
  id: id,
  tipo: TipoNotificacion.pedidoAutorizado,
  titulo: titulo,
  detalle: detalle,
  destino: destino,
  recibidaEn: DateTime.utc(2026, 11, 9, 15, 30),
);

final _abrir = find.byKey(const Key('aviso_push_en_app_abrir'));
final _cerrar = find.byKey(const Key('aviso_push_en_app_cerrar'));

void _pantalla(WidgetTester tester, {Size tamano = const Size(390, 844), double texto = 1}) {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  group('la tarjeta', () {
    Future<void> montar(
      WidgetTester tester,
      Notificacion aviso, {
      VoidCallback? onAbrir,
      VoidCallback? onCerrar,
      Size tamano = const Size(390, 844),
      double texto = 1,
    }) async {
      _pantalla(tester, tamano: tamano, texto: texto);
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AvisoPushEnApp(
                  aviso: aviso,
                  onAbrir: onAbrir ?? () {},
                  onCerrar: onCerrar ?? () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('dado un aviso con destino, entonces dice «AHORA», el título y «Tocá para ver el '
        'detalle»', (tester) async {
      await montar(tester, _aviso('a', destino: const DestinoAgenda('x')));

      expect(find.text('AHORA'), findsOneWidget);
      expect(find.text('Tu pedido fue autorizado'), findsOneWidget);
      expect(find.text('Tocá para ver el detalle'), findsOneWidget);
    });

    testWidgets('dado un aviso sin destino ni detalle, entonces no promete un detalle que no hay', (
      tester,
    ) async {
      await montar(tester, _aviso('a'));

      expect(find.text('Tu pedido fue autorizado'), findsOneWidget);
      expect(find.text('Tocá para ver el detalle'), findsNothing);
    });

    testWidgets(
      'dado un aviso con segunda línea propia, entonces la muestra en lugar de la frase',
      (tester) async {
        await montar(
          tester,
          _aviso('a', detalle: 'Av. Italia 2810', destino: const DestinoAgenda('x')),
        );

        expect(find.text('Av. Italia 2810'), findsOneWidget);
        expect(find.text('Tocá para ver el detalle'), findsNothing);
      },
    );

    testWidgets(
      'cuando se toca la tarjeta, entonces se abre el aviso y no se cierra por su cuenta',
      (tester) async {
        var abrio = 0;
        var cerro = 0;
        await montar(tester, _aviso('a'), onAbrir: () => abrio++, onCerrar: () => cerro++);

        await tester.tap(_abrir);

        expect(abrio, 1);
        expect(cerro, 0);
      },
    );

    testWidgets('cuando se toca la ✕, entonces solo se cierra', (tester) async {
      var abrio = 0;
      var cerro = 0;
      await montar(tester, _aviso('a'), onAbrir: () => abrio++, onCerrar: () => cerro++);

      await tester.tap(_cerrar);

      expect(cerro, 1);
      expect(abrio, 0);
    });

    testWidgets('para el lector de pantalla es un solo botón que lo dice todo, con la ✕ aparte y '
        'con nombre', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester, _aviso('a', destino: const DestinoAgenda('x')));

      expect(
        tester.getSemantics(_abrir),
        isSemantics(
          label: 'AHORA. Tu pedido fue autorizado. Tocá para ver el detalle',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(_cerrar),
        isSemantics(label: 'Cerrar aviso', isButton: true, hasTapAction: true),
      );
      semantica.dispose();
    });

    testWidgets('la ✕ tiene un blanco de toque de 48 × 48 como mínimo', (tester) async {
      await montar(tester, _aviso('a'));

      final tamano = tester.getSize(_cerrar);
      expect(tamano.width, greaterThanOrEqualTo(48));
      expect(tamano.height, greaterThanOrEqualTo(48));
    });
  });

  group('arriba de toda la app', () {
    late _Abridor abridor;
    var activo = true;
    late StateSetter cambiarActivo;

    setUp(() {
      abridor = _Abridor();
      activo = true;
    });

    Future<ProviderContainer> montar(
      WidgetTester tester, {
      Size tamano = const Size(390, 844),
      double texto = 1,
    }) async {
      _pantalla(tester, tamano: tamano, texto: texto);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [abridorAvisoPushProvider.overrideWithValue(abridor.call)],
          child: StatefulBuilder(
            builder: (context, setState) {
              cambiarActivo = setState;
              return MaterialApp(
                theme: temaClaro(),
                builder: (context, child) =>
                    AvisoPushEnAppHost(activo: activo, child: child ?? const SizedBox.shrink()),
                home: Scaffold(
                  appBar: AppBar(title: const Text('Hoy')),
                  body: Center(
                    child: TextButton(
                      onPressed: () => abridor.toquesAlFondo++,
                      child: const Text('Botón del fondo'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      return ProviderScope.containerOf(tester.element(find.byType(AvisoPushEnAppHost)));
    }

    Future<void> llega(WidgetTester tester, ProviderContainer c, Notificacion aviso) async {
      c.read(canalAvisosPushProvider).mostrar(aviso);
      // Un cuadro para que llegue el evento y otro para que se dibuje.
      await tester.pump();
      await tester.pump();
    }

    testWidgets('dado que llega una push, cuando la app está abierta, entonces el aviso aparece '
        'arriba, sobre la barra de la pantalla, y la pantalla sigue usable', (tester) async {
      final c = await montar(tester);
      expect(_abrir, findsNothing);

      await llega(tester, c, _aviso('a'));

      expect(_abrir, findsOneWidget);
      expect(tester.getTopLeft(find.byType(AvisoPushEnApp)).dy, lessThan(40));
      await tester.tap(find.text('Botón del fondo'));
      expect(abridor.toquesAlFondo, 1);
      expect(_abrir, findsOneWidget, reason: 'tocar otra cosa no lo cierra');
    });

    testWidgets('dado un aviso a la vista, cuando pasan 8 segundos, entonces se va solo', (
      tester,
    ) async {
      final c = await montar(tester);
      await llega(tester, c, _aviso('a'));

      await tester.pump(duracionAvisoPushEnApp - const Duration(milliseconds: 1));
      expect(_abrir, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2));

      expect(_abrir, findsNothing);
      expect(abridor.abiertos, isEmpty);
    });

    testWidgets(
      'dado un lector de pantalla encendido, entonces el aviso no se va solo: espera a que '
      'se cierre (WCAG 2.2.1)',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
          accessibleNavigation: true,
        );
        addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        final c = await montar(tester);
        await llega(tester, c, _aviso('a'));

        await tester.pump(duracionAvisoPushEnApp * 3);
        expect(_abrir, findsOneWidget);

        await tester.tap(_cerrar);
        await tester.pump();
        expect(_abrir, findsNothing);
      },
    );

    testWidgets('dado el foco del teclado en el aviso, cuando pasan los 8 segundos, entonces se '
        'queda y se va apenas se suelta el foco', (tester) async {
      final c = await montar(tester);
      await llega(tester, c, _aviso('a'));
      // El foco del teclado llega a la ✕ del aviso.
      Focus.of(
        tester.element(find.descendant(of: _cerrar, matching: find.byType(Icon))),
      ).requestFocus();
      await tester.pump();
      await tester.pump();

      await tester.pump(duracionAvisoPushEnApp * 2);
      expect(_abrir, findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump();
      expect(_abrir, findsNothing);
    });

    testWidgets('dado un aviso a la vista, cuando llega otro, entonces el nuevo lo reemplaza y '
        'cuenta sus propios 8 segundos', (tester) async {
      final c = await montar(tester);
      await llega(tester, c, _aviso('a', titulo: 'Primero'));
      await tester.pump(const Duration(seconds: 5));

      await llega(tester, c, _aviso('b', titulo: 'Segundo'));
      expect(find.text('Primero'), findsNothing);
      expect(find.text('Segundo'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Segundo'), findsOneWidget, reason: 'el reloj del primero no lo saca');
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Segundo'), findsNothing);
    });

    testWidgets(
      'cuando se toca el aviso, entonces se abre una vez y se va para no tapar el destino',
      (tester) async {
        final c = await montar(tester);
        await llega(tester, c, _aviso('a'));

        await tester.tap(_abrir);
        await tester.pump();

        expect(abridor.abiertos.map((n) => n.id), ['a']);
        expect(_abrir, findsNothing);
      },
    );

    testWidgets('dado un doble toque mientras se abre, entonces se abre una sola vez', (
      tester,
    ) async {
      final c = await montar(tester);
      abridor.puerta = Completer<void>();
      await llega(tester, c, _aviso('a'));
      final boton = tester.widget<InkWell>(_abrir);

      boton.onTap!();
      boton.onTap!();
      await tester.pump();

      expect(abridor.abiertos, hasLength(1));
      abridor.puerta!.complete();
      await tester.pump();
    });

    testWidgets('dado que abrir falla, cuando llega y se toca otro aviso, entonces la guarda de '
        'doble toque no queda trabada', (tester) async {
      final c = await montar(tester);
      abridor.falla = StateError('sin pantalla');
      await llega(tester, c, _aviso('a'));
      await tester.tap(_abrir);
      await tester.pump();
      expect(tester.takeException(), isNull);

      abridor.falla = null;
      await llega(tester, c, _aviso('b'));
      await tester.tap(_abrir);
      await tester.pump();

      expect(abridor.abiertos.map((n) => n.id), ['a', 'b']);
    });

    testWidgets('cuando se toca la ✕, entonces el aviso se cierra y no se abre nada', (
      tester,
    ) async {
      final c = await montar(tester);
      await llega(tester, c, _aviso('a'));

      await tester.tap(_cerrar);
      await tester.pump();

      expect(_abrir, findsNothing);
      expect(abridor.abiertos, isEmpty);
    });

    testWidgets('dado que no hay sesión, cuando llega un aviso, entonces no se muestra nada', (
      tester,
    ) async {
      final c = await montar(tester);
      cambiarActivo(() => activo = false);
      await tester.pump();

      await llega(tester, c, _aviso('a'));

      expect(_abrir, findsNothing);
    });

    testWidgets('dado un aviso a la vista, cuando se cierra la sesión, entonces se saca', (
      tester,
    ) async {
      final c = await montar(tester);
      await llega(tester, c, _aviso('a'));
      expect(_abrir, findsOneWidget);

      cambiarActivo(() => activo = false);
      await tester.pump();

      expect(_abrir, findsNothing);
      await tester.pump(duracionAvisoPushEnApp);
    });
  });
}

final class _Abridor {
  final abiertos = <Notificacion>[];
  Object? falla;
  Completer<void>? puerta;
  int toquesAlFondo = 0;

  Future<void> call(Notificacion aviso) async {
    abiertos.add(aviso);
    final p = puerta;
    if (p != null) await p.future;
    if (falla case final error?) throw error;
  }
}
