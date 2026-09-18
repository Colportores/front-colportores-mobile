import 'dart:io';

import 'package:test/test.dart';

/// Verifica ADR-009: `domain` no importa Flutter, Drift ni Supabase.
///
/// Recorre los `.dart` bajo `lib/**/domain/**` (cualquier feature) y `lib/core/domain/**` y
/// falla si alguno importa `package:flutter`, `package:drift` o `package:supabase`.
///
/// No usa `git ls-files` (gotcha conocido: no anda en el contenedor sobre worktrees de
/// Windows) — recorre el filesystem directo con `dart:io`.
void main() {
  test(
    'dado el codigo de dominio, cuando se listan sus imports, ninguno es de flutter/drift/supabase',
    () {
      final raiz = Directory('lib');
      final archivosDominio = raiz
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) {
            final normalizado = f.path.replaceAll('\\', '/');
            return normalizado.contains('/domain/');
          })
          .toList();

      expect(
        archivosDominio,
        isNotEmpty,
        reason: 'no se encontró ningún archivo bajo lib/**/domain/** — ¿cambió la estructura?',
      );

      final prohibidos = ['package:flutter', 'package:drift', 'package:supabase'];
      final violaciones = <String>[];

      for (final archivo in archivosDominio) {
        final contenido = archivo.readAsStringSync();
        for (final prohibido in prohibidos) {
          if (contenido.contains("import '$prohibido") ||
              contenido.contains('import "$prohibido')) {
            violaciones.add('${archivo.path} importa $prohibido');
          }
        }
      }

      expect(
        violaciones,
        isEmpty,
        reason: 'archivos de dominio con imports prohibidos:\n${violaciones.join('\n')}',
      );
    },
  );
}
