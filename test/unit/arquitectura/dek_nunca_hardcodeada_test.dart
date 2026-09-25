// HU-AUTH-009 / issue #28 — la DEK sale siempre del CSPRNG del sistema (`Random.secure()` en
// `CustodiaClaveDb.generarDek`) y nunca puede quedar fija en el código.
//
// `custodia_clave_db_test.dart` ya prueba el comportamiento ("cuando genera una DEK ... es
// distinta cada vez"); este test complementa con un chequeo estático sobre el código fuente: nada
// en lib/ (fuera de las fakes, que sí usan bytes fijos a propósito para tests y la demo sin
// backend, documentado como "No es código de producción") puede tener un arreglo de 32 bytes
// fijo ni una cadena larga en base64/hex asignada a algo con pinta de clave — es exactamente el
// patrón que tendría una DEK hardcodeada (y el mismo que usan las fakes a propósito).
//
// Misma lectura resiliente que dominio_puro_test.dart (issue #83): un recorrido de `dir.list`.
import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/lectura_resiliente_arbol.dart';

/// `List.filled(32, ...)` / `Uint8List.filled(32, ...)`: 32 bytes (256 bits, el tamaño de la DEK,
/// `ClaveDb.bytesEsperados`) todos armados con el mismo valor. En producción no hay ninguna razón
/// legítima para esto; es justo lo que usan las fakes para fabricar una DEK fija de prueba.
final _bytesFijos = RegExp(r'\.filled\(\s*32\s*,');

/// Una cadena literal larga (base64 o hex) asignada a algo con "dek" o "clave" en el nombre: el
/// largo de una DEK de 256 bits en esas codificaciones (44 caracteres con relleno en base64, 64 en
/// hex) — 40 de piso para no depender del relleno exacto.
final _stringSospechosa = RegExp(
  r'''(dek|clave)\w*\s*=\s*['"][A-Za-z0-9+/=]{40,}['"]''',
  caseSensitive: false,
);

bool _produccionFueraDeFakes(File archivo) =>
    esDartNoGenerado(archivo) && !archivo.path.replaceAll(r'\', '/').contains('/fakes/');

void main() {
  test('la DEK nunca está hardcodeada en lib/ (fuera de las fakes de test/demo)', () async {
    final archivos = await leerArbolDartResiliente(
      Directory('lib'),
      incluir: _produccionFueraDeFakes,
    );
    expect(archivos, isNotEmpty);

    final hallazgos = <String>[];
    for (final archivo in archivos) {
      for (var i = 0; i < archivo.lineas.length; i++) {
        final linea = archivo.lineas[i];
        if (_bytesFijos.hasMatch(linea) || _stringSospechosa.hasMatch(linea)) {
          hallazgos.add('${archivo.path}:${i + 1}: ${linea.trim()}');
        }
      }
    }

    expect(
      hallazgos,
      isEmpty,
      reason:
          'posible DEK hardcodeada (HU-AUTH-009: siempre tiene que salir del CSPRNG):\n'
          '${hallazgos.join('\n')}',
    );
  });
}
