// «No volver a mostrar» del aviso de privacidad del alta de persona (#445, decisión de Cristian
// 23/10 «Aviso privado»): se esconde por cuenta, se puede recuperar desde Configuración y no deja
// nada trabado si falla o si se toca dos veces.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/data/repositories/aviso_privacidad_repository_impl.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/aviso_privacidad_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> _montar(
  WidgetTester tester,
  AvisoPrivacidadEnMemoria repo, {
  String cuenta = 'u-1',
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [avisoPrivacidadRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AvisoPrivacidadPersona(colportorId: cuenta),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

Finder get _aviso => find.byKey(ClavesAvisoPrivacidad.aviso);
Finder get _noVolver => find.byKey(ClavesAvisoPrivacidad.noVolverAMostrar);
Finder get _escondido => find.byKey(ClavesAvisoPrivacidad.escondido);
Finder get _falla => find.byKey(ClavesAvisoPrivacidad.falla);

void main() {
  testWidgets(
    'el aviso dice que los datos solo viven en el celular y ofrece «No volver a mostrar»',
    (tester) async {
      await _montar(tester, AvisoPrivacidadEnMemoria());

      expect(_aviso, findsOneWidget);
      expect(
        find.text('Estos datos solo viven en tu celular. Nunca se suben a la nube.'),
        findsOneWidget,
      );
      expect(find.text('No volver a mostrar'), findsOneWidget);
      expect(tester.getSize(_noVolver).height, greaterThanOrEqualTo(48));
    },
  );

  testWidgets('al tocar «No volver a mostrar» se esconde, se guarda para la cuenta y dice cómo '
      'recuperarlo', (tester) async {
    final repo = AvisoPrivacidadEnMemoria();
    await _montar(tester, repo);

    await tester.tap(_noVolver);
    await tester.pumpAndSettle();

    expect(_aviso, findsNothing);
    expect(repo.ocultas, {'u-1'});
    expect(_escondido, findsOneWidget);
    expect(find.text(TextosPersonas.avisoEscondido), findsOneWidget);
    expect(find.textContaining('Configuración'), findsOneWidget);
  });

  testWidgets('si la cuenta ya lo había escondido, no sale ni deja lugar vacío', (tester) async {
    await _montar(tester, AvisoPrivacidadEnMemoria(['u-1']));

    expect(_aviso, findsNothing);
    expect(_escondido, findsNothing);
    expect(find.byType(AvisoPrivacidadPersona), findsOneWidget);
    expect(tester.getSize(find.byType(AvisoPrivacidadPersona)).height, 0);
  });

  testWidgets('lo escondió otra cuenta del mismo teléfono: esta lo sigue viendo', (tester) async {
    await _montar(tester, AvisoPrivacidadEnMemoria(['u-2']));

    expect(_aviso, findsOneWidget);
  });

  testWidgets('volver a mostrarlo desde Configuración lo trae de vuelta', (tester) async {
    final repo = AvisoPrivacidadEnMemoria(['u-1']);
    final container = await _montar(tester, repo);
    expect(_aviso, findsNothing);

    await container.read(avisoPrivacidadOcultoProvider('u-1').notifier).mostrar();
    await tester.pumpAndSettle();

    expect(_aviso, findsOneWidget);
    expect(repo.ocultas, isEmpty);
  });

  testWidgets(
    'falla a mitad: el aviso sigue a la vista, dice que no se guardó y se puede reintentar',
    (tester) async {
      final repo = AvisoPrivacidadEnMemoria()..fallaAlEscribir = true;
      await _montar(tester, repo);

      await tester.tap(_noVolver);
      await tester.pumpAndSettle();

      expect(_aviso, findsOneWidget);
      expect(_falla, findsOneWidget);
      expect(find.text('No pudimos guardar tu elección. Probá de nuevo.'), findsOneWidget);
      expect(repo.ocultas, isEmpty);

      repo.fallaAlEscribir = false;
      await tester.tap(_noVolver);
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(_falla, findsNothing);
      expect(repo.ocultas, {'u-1'});
    },
  );

  testWidgets('doble toque: se guarda una sola vez', (tester) async {
    final compuerta = Completer<void>();
    final repo = AvisoPrivacidadEnMemoria()..compuerta = compuerta;
    await _montar(tester, repo);

    await tester.tap(_noVolver);
    await tester.pump();
    await tester.tap(_noVolver, warnIfMissed: false);
    await tester.pump();
    compuerta.complete();
    await tester.pumpAndSettle();

    expect(repo.escrituras, 1);
    expect(_aviso, findsNothing);
  });

  testWidgets('si no se puede leer la preferencia, el aviso se ve', (tester) async {
    await _montar(tester, AvisoPrivacidadEnMemoria(['u-1'])..fallaAlLeer = true);

    expect(_aviso, findsOneWidget);
  });

  testWidgets('a 360 px y texto 2.0 el aviso no desborda y la acción sigue al alcance', (
    tester,
  ) async {
    await _montar(tester, AvisoPrivacidadEnMemoria(), escala: 2, tamano: const Size(360, 740));

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_noVolver).right, lessThanOrEqualTo(360));
    expect(tester.getSize(_noVolver).height, greaterThanOrEqualTo(48));
  });

  testWidgets('el lector de pantalla encuentra «No volver a mostrar» como un botón', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await _montar(tester, AvisoPrivacidadEnMemoria());

    expect(
      tester.getSemantics(_noVolver),
      matchesSemantics(
        label: 'No volver a mostrar',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    semantica.dispose();
  });
}
