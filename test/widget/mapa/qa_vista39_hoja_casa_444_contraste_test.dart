// QA ronda 1 de la vista 39 (base), C·01 y E·01 a E·05 (HU-UBI-003, #444, PR #471): contraste del texto
// (`textContrastGuideline`) de la hoja de la casa entera en cada estado. Va aparte y SIN cargar las
// fuentes reales: con la letra real la guía lee los bordes suavizados y da falsos negativos; con Ahem
// cada letra es un bloque y el par de colores se mide limpio.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart' show ahoraLista;

class _Estado {
  const _Estado(this.nombre, {this.item, this.lectura, this.registrar});

  final String nombre;
  final ItemListaUbicacion Function()? item;
  final Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa)? lectura;
  final bool? registrar;
}

final _estados = <_Estado>[
  const _Estado('C·01 completo', registrar: true),
  _Estado('C·01 sin personas ni nota', lectura: (_) => Stream.value(const ContextoDeLaCasa())),
  _Estado('E·02 error', lectura: (_) => Stream.error(StateError('x'))),
  _Estado(
    'E·04 baja con Reactivar',
    item: () => itemDeLaHoja(baja: DateTime.utc(2026, 10, 18, 15), estado: null),
  ),
  _Estado('E·05 lejos', item: () => itemDeLaHoja(metros: 650), registrar: true),
  const _Estado('falla de «Registrar visita»', registrar: true),
];

void main() {
  for (final e in _estados) {
    for (final escala in [1.0, 2.0]) {
      testWidgets('${e.nombre} · texto $escala×: el texto cumple el contraste AA', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final falla = e.nombre.startsWith('falla');
        await tester.pumpWidget(
          ProviderScope(
            overrides: overridesHojaCasa(
              lectura: e.lectura,
              registrarVisita: e.registrar == true
                  ? (falla ? (_) => throw StateError('no abre') : (_) {})
                  : null,
              cobrar: e.registrar == true ? (_) {} : null,
            ),
            child: MaterialApp(
              theme: temaClaro(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
                child: child!,
              ),
              home: Scaffold(
                backgroundColor: Colors.white,
                body: Align(
                  alignment: Alignment.topCenter,
                  child: HojaCasa(
                    item: e.item?.call() ?? itemDeLaHoja(),
                    ahora: ahoraLista,
                    alCerrar: () {},
                    alReactivar: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        if (falla) {
          await tester.ensureVisible(find.byKey(ClavesHojaCasa.registrarVisita));
          await tester.tap(find.byKey(ClavesHojaCasa.registrarVisita));
          await tester.pump();
          await tester.pump();
        }
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }
}
