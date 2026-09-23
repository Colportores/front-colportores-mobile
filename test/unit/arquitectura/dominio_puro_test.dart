// Conformidad con ADR-009: el dominio es Dart puro.
//
// Escanea los imports de lib/features/*/domain/** y lib/core/{domain,error,usecases}: si alguno
// trae Flutter, Riverpod, Drift o Supabase, el test falla. La regla deja de depender del review.
//
// La lectura del árbol usa `leerArbolDartResiliente` (test/helpers/lectura_resiliente_arbol.dart,
// issue #83): un solo recorrido con `dir.list(recursive: true)`, con reintento ante una carrera
// entre listar y leer. Antes usaba `listSync` + una foto del árbol y fallaba de forma intermitente.
import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/lectura_resiliente_arbol.dart';

const _prohibidos = [
  'package:flutter/',
  'package:flutter_riverpod/',
  'package:riverpod',
  'package:drift',
  'package:supabase',
  'package:sqlcipher',
  'package:dio/',
  'package:http/',
];

Iterable<Directory> _directoriosDeDominio() sync* {
  final features = Directory('lib/features');
  if (features.existsSync()) {
    for (final feature in features.listSync().whereType<Directory>()) {
      final domain = Directory('${feature.path}/domain');
      if (domain.existsSync()) yield domain;
    }
  }
  for (final core in ['lib/core/domain', 'lib/core/error', 'lib/core/usecases']) {
    final dir = Directory(core);
    if (dir.existsSync()) yield dir;
  }
}

void main() {
  group('Arquitectura — dominio puro (ADR-009)', () {
    test('existe al menos un directorio de dominio para verificar', () {
      expect(_directoriosDeDominio(), isNotEmpty);
    });

    for (final dir in _directoriosDeDominio()) {
      test('${dir.path} no importa Flutter, Riverpod, Drift, Supabase ni HTTP', () async {
        final archivos = await leerArbolDartResiliente(dir);

        final violaciones = <String>[];
        for (final archivo in archivos) {
          for (var i = 0; i < archivo.lineas.length; i++) {
            final linea = archivo.lineas[i].trim();
            if (!linea.startsWith('import ') && !linea.startsWith('export ')) continue;
            for (final prohibido in _prohibidos) {
              if (linea.contains(prohibido)) {
                violaciones.add('${archivo.path}:${i + 1}: $linea');
              }
            }
          }
        }
        expect(
          violaciones,
          isEmpty,
          reason: 'imports prohibidos en dominio:\n${violaciones.join('\n')}',
        );
      });
    }
  });
}
