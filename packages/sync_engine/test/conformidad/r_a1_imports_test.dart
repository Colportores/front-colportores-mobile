// Suite de conformidad (§8) — regla R-A1 del Apéndice A.
//
//   "Ningún import de Flutter ni de plugins fuera de lib/src/adapters/.
//    Se verifica con un test de la suite de conformidad que escanea los imports
//    de core/ — no depende de la disciplina de review."
//
// Un import de Flutter en el núcleo no rompe nada el día que se escribe: se
// paga después, cuando la suite deja de correr en la VM y pasa a necesitar un
// dispositivo. Para entonces ya nadie sabe cuál fue el import que la arruinó.

import 'dart:io';

import 'package:test/test.dart';

/// Los plugins del Apéndice A. Cada uno tiene su adaptador; ninguno se importa
/// desde ningún otro lado.
const _plugins = {
  // No es un plugin, pero la regla vale igual: el núcleo no sabe que existe
  // HTTP. Si `http` aparece fuera de adapters/, algo se coló a través de
  // SyncTransport.
  'http',
  'archive',
  'crypto',
  'connectivity_plus',
  'workmanager',
  'flutter_secure_storage',
  'cryptography_flutter',
  'googleapis',
  'google_sign_in',
};

final _import = RegExp('''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''');

void main() {
  test('R-A1: solo lib/src/adapters/ importa Flutter o un plugin', () {
    final violaciones = <String>[];

    for (final archivo in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (archivo.path.contains('lib/src/adapters/')) continue;

      var linea = 0;
      for (final texto in archivo.readAsLinesSync()) {
        linea++;
        final uri = _import.firstMatch(texto)?.group(1);
        if (uri == null) continue;

        final paquete =
            uri.startsWith('package:') ? uri.split('/').first.substring(8) : '';
        if (paquete == 'flutter' || _plugins.contains(paquete)) {
          violaciones.add('${archivo.path}:$linea → $uri');
        }
      }
    }

    expect(violaciones, isEmpty,
        reason: 'el núcleo tiene que correr en la VM de Dart, sin dispositivo '
            '(§5.9). Lo de plataforma va detrás de un puerto (R-A2).');
  });

  test('R-A2: cada puerto de ports.dart tiene un fake en lib/src/testing/', () {
    final puertos = RegExp(r'abstract interface class (\w+)')
        .allMatches(File('lib/src/core/ports.dart').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();

    final fakes = Directory('lib/src/testing')
        .listSync()
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join('\n');

    final sinFake = puertos.where((p) => !fakes.contains('implements $p'));
    expect(sinFake, isEmpty,
        reason: 'sin fake, ese puerto obliga a un dispositivo para testear '
            'cualquier cosa que lo use');
  });
}
