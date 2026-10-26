// Arnés de QA del aviso de privacidad con «No volver a mostrar» dentro del alta de persona real (32A,
// #445, PR #476): lleva el alta a cada estado del aviso.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/data/repositories/aviso_privacidad_repository_impl.dart';
import 'package:colportores_mobile/features/configuracion/presentation/providers/aviso_privacidad_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/personas_arnes.dart' show asentar, contextoActivo;
import 'persona_falsos.dart';

enum EstadoAviso445 { visible, recienEscondido, falla, oculto }

/// Abre el alta de persona (32A) con la cuenta `col-1` y el aviso en [estado].
Future<AvisoPrivacidadEnMemoria> llegarAlAviso445(
  WidgetTester tester,
  EstadoAviso445 estado, {
  Size tamano = const Size(412, 915),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = AvisoPrivacidadEnMemoria(estado == EstadoAviso445.oculto ? ['col-1'] : const []);
  if (estado == EstadoAviso445.falla) repo.fallaAlEscribir = true;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        avisoPrivacidadRepositoryProvider.overrideWithValue(repo),
        personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
        espacioRepositoryProvider.overrideWithValue(
          EspacioRepositorioParaPersonas(contextoActivo()),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    AltaPersonaPage.abrir(context, espacioId: 'esp-1', colportorId: 'col-1'),
                child: const Text('abrir alta'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir alta'));
  await asentar(tester);
  if (estado == EstadoAviso445.recienEscondido || estado == EstadoAviso445.falla) {
    await tester.tap(find.byKey(ClavesAvisoPrivacidad.noVolverAMostrar));
    await asentar(tester);
  }
  return repo;
}
