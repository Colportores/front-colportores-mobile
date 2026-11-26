// Capturas de QA de las vistas 20 y 21 (#146): un PNG por estado, tamaño y escala de texto en
// `.dart_tool/qa_capturas/` (gitignored, nunca se commitea). Solo corre con `QA_CAPTURAS=true`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista20_21_146_arnes.dart';

void main() {
  final activo = Platform.environment['QA_CAPTURAS'] == 'true';
  for (final entrada in estados146.entries) {
    for (final (nombreTam, tam) in [
      ('360x640', telefonoChico146),
      ('412x915', telefonoGrande146),
    ]) {
      for (final esc in [1.0, 2.0]) {
        testWidgets('captura ${entrada.key} $nombreTam ×$esc', skip: !activo, (tester) async {
          await cargarFuentes146(tester);
          await entrada.value(tester, tam, esc);
          tester.takeException();
          await capturar146(tester, '${entrada.key}_${nombreTam}_x$esc');
        });
      }
    }
  }
}
