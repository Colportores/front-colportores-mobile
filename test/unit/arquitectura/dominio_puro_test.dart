// Conformidad con ADR-009: el dominio es Dart puro.
//
// Escanea los imports de lib/features/*/domain/** y lib/core/{error,usecases}: si alguno trae
// Flutter, Riverpod, Drift o Supabase, el test falla. La regla deja de depender del review.
import 'dart:io';

import 'package:test/test.dart';

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

Iterable<File> _dartsEn(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));

Iterable<Directory> _directoriosDeDominio() sync* {
  final features = Directory('lib/features');
  if (features.existsSync()) {
    for (final feature in features.listSync().whereType<Directory>()) {
      final domain = Directory('${feature.path}/domain');
      if (domain.existsSync()) yield domain;
    }
  }
  for (final core in ['lib/core/error', 'lib/core/usecases']) {
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
      test('${dir.path} no importa Flutter, Riverpod, Drift, Supabase ni HTTP', () {
        final violaciones = <String>[];
        for (final archivo in _dartsEn(dir)) {
          final lineas = archivo.readAsLinesSync();
          for (var i = 0; i < lineas.length; i++) {
            final linea = lineas[i].trim();
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
