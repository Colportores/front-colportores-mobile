// QA de «Gestionar espacios dentro de una ubicación» (HU-UBI-007, #212, PR #501): las guías de
// accesibilidad de Flutter (tamaño de toque de Android e iOS, etiqueta en lo tocable y contraste del
// texto) en los estados del recorrido de la baja, con la DB real. Archivo aparte con la letra de
// prueba (Ahem): con las fuentes reales el `textContrastGuideline` da falsos negativos.
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_depto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_hu_ubi_007_212_arnes.dart';
import 'hoja_espacios_arnes.dart' show botonAgregarDepto, botonDarDeBaja, filaDepto;

typedef _Llegar = Future<void> Function(WidgetTester tester);

Future<void> _lista(WidgetTester tester) async {}

Future<void> _alta(WidgetTester tester) => tocar212(tester, botonAgregarDepto);

Future<void> _avisoConPersonas(WidgetTester tester) async {
  await tocar212(tester, filaDepto('esp-1'));
  await tocar212(tester, botonDarDeBaja);
}

Future<void> _clientesDeBaja(WidgetTester tester) async {
  await _avisoConPersonas(tester);
  await tocar212(tester, find.byKey(ClavesHojaDepto.confirmarBaja));
  await cerrarHoja212(tester);
  await tocar212(tester, find.text('abrir clientes'));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final estados = <String, (_Llegar, Future<void> Function(Telefono212))>{
    'lista de deptos': (_lista, edificioConDosDeptos212),
    'alta del depto': (_alta, edificioConDosDeptos212),
    'aviso de la baja con personas': (_avisoConPersonas, edificioConDosDeptos212),
    'baja bloqueada (último espacio)': (_avisoConPersonas, edificioConUnDepto212),
    'clientes del depto dado de baja': (_clientesDeBaja, edificioConDosDeptos212),
  };

  for (final tamano in const [Size(360, 640), Size(412, 915)]) {
    for (final e in estados.entries) {
      final donde = '${e.key} a ${tamano.width.toInt()}×${tamano.height.toInt()}';

      Future<void> llegar(WidgetTester tester, {double escala = 1}) async {
        await montar212(tester, tamano: tamano, escala: escala);
        await abrirHoja212(tester);
        await e.value.$1(tester);
        expect(tester.takeException(), isNull);
      }

      prueba212('tamaño de toque de Android (48 dp) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegar(tester);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        h.dispose();
      }, sembrar: e.value.$2);

      prueba212('tamaño de toque de iOS (44 dp) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegar(tester);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        h.dispose();
      }, sembrar: e.value.$2);

      prueba212('toda acción tocable tiene nombre en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegar(tester);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      }, sembrar: e.value.$2);

      prueba212('contraste del texto (AA) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegar(tester);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        h.dispose();
      }, sembrar: e.value.$2);

      prueba212('tamaño de toque y nombre con el texto al 200 % en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegar(tester, escala: 2);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      }, sembrar: e.value.$2);
    }
  }
}
