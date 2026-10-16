// Test propio del helper compartido `lectura_resiliente_arbol.dart` (issue #83): simula la
// carrera entre listar el árbol y leer cada archivo inyectando el lector, en vez de depender de
// una carrera real del filesystem (no sería determinístico).
import 'dart:io';

import 'package:test/test.dart';

import 'lectura_resiliente_arbol.dart';

void main() {
  group('leerArbolDartResiliente', () {
    late Directory dirTemp;

    setUp(() {
      dirTemp = Directory.systemTemp.createTempSync('lectura_resiliente_arbol_test_');
    });

    tearDown(() {
      if (dirTemp.existsSync()) dirTemp.deleteSync(recursive: true);
    });

    test(
      'dado un árbol sin carreras, cuando se lee, devuelve el contenido de cada .dart no generado',
      () async {
        File('${dirTemp.path}/a.dart').writeAsStringSync('import "package:test/test.dart";\n');
        File('${dirTemp.path}/a.g.dart').writeAsStringSync('// generado, se ignora\n');
        File('${dirTemp.path}/nota.txt').writeAsStringSync('no es dart\n');

        final leidos = await leerArbolDartResiliente(dirTemp, esperaReintento: Duration.zero);

        expect(leidos, hasLength(1));
        expect(leidos.single.path, endsWith('a.dart'));
        expect(leidos.single.lineas, ['import "package:test/test.dart";']);
      },
    );

    test(
      'dado que un archivo desaparece entre el listado y la lectura, cuando se relee, se ignora sin fallar el test',
      () async {
        final archivo = File('${dirTemp.path}/desaparece.dart')..writeAsStringSync('// código\n');
        var intentos = 0;

        final leidos = await leerArbolDartResiliente(
          dirTemp,
          esperaReintento: Duration.zero,
          leer: (f) {
            intentos++;
            if (f.path == archivo.path) {
              archivo.deleteSync(); // simula la carrera: se borró entre listar y leer
              throw FileSystemException('boom', f.path);
            }
            return f.readAsLinesSync();
          },
        );

        expect(leidos, isEmpty);
        expect(intentos, 1, reason: 'no debe reintentar la lectura de un archivo que ya no existe');
      },
    );

    test(
      'dado que la primera lectura falla pero el archivo sigue existiendo, cuando se reintenta, devuelve su contenido',
      () async {
        File('${dirTemp.path}/parpadea.dart').writeAsStringSync('// código real\n');
        var intentos = 0;

        final leidos = await leerArbolDartResiliente(
          dirTemp,
          esperaReintento: Duration.zero,
          leer: (f) {
            intentos++;
            if (intentos == 1) throw FileSystemException('lock transitorio', f.path);
            return f.readAsLinesSync();
          },
        );

        expect(leidos.single.lineas, ['// código real']);
        expect(intentos, 2);
      },
    );

    test(
      'dado que el archivo existe y la lectura sigue fallando en el reintento, cuando se lee, el test falla',
      () async {
        File('${dirTemp.path}/roto.dart').writeAsStringSync('// código\n');

        await expectLater(
          leerArbolDartResiliente(
            dirTemp,
            esperaReintento: Duration.zero,
            leer: (f) => throw FileSystemException('siempre falla', f.path),
          ),
          throwsA(isA<TestFailure>()),
        );
      },
    );

    test(
      'dado un directorio sin archivos .dart, cuando se lee, devuelve una lista vacía',
      () async {
        final leidos = await leerArbolDartResiliente(dirTemp, esperaReintento: Duration.zero);
        expect(leidos, isEmpty);
      },
    );
  });
}
