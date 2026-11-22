// Issue #565 (seguimiento del QA de #557) — las filas de Drift (`*Fila`) no se interpolan en un texto
// ni se pasan a un log.
//
// Una fila generada por Drift NO es un `Equatable`: `EquatableConfig.stringify = false` no la alcanza
// y su `toString()` generado vuelca TODAS las columnas (calle, número, latitud y longitud de
// `UbicacionFila`; nombre, apellido y teléfono de `PersonaFila`; las notas de `NotaFila`…).
// convenciones-desarrollo.md §7.5: sin PII en logs, solo IDs. Un `'$fila'`, un `'${fila}'`, un
// `fila.toString()` o un `log.info(fila)` filtraría la dirección o la persona.
//
// Chequeo estático sobre `lib/` y `packages/*/lib/`, con la misma lectura resiliente que
// `dominio_puro_test.dart`. Dos reglas:
//  1. ninguna variable tipada como una fila de Drift se interpola, se convierte con `toString()` ni se
//     pasa como único dato a un log o a un `print`;
//  2. ningún `toString()` escrito a mano de `lib/` ni de `packages/` nombra campos de dirección o de
//     coordenadas.
// Qué NO alcanza (límite conocido de un barrido estático): una fila sin tipo declarado (el parámetro
// de una lambda, un `final x = await select…`) no se detecta. Para esos casos el repositorio ya
// convierte la fila a una entidad con `stringify` apagado antes de salir de la capa de datos.
import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/lectura_resiliente_arbol.dart';

String _normal(String ruta) => ruta.replaceAll(r'\', '/');

bool _esComentario(String linea) => linea.trimLeft().startsWith('//');

/// Las carpetas de código de producción: `lib/` y el `lib/` de cada paquete local.
List<Directory> _carpetasDeCodigo() {
  final carpetas = <Directory>[Directory('lib')];
  final paquetes = Directory('packages');
  if (paquetes.existsSync()) {
    for (final paquete in paquetes.listSync().whereType<Directory>()) {
      final lib = Directory('${paquete.path}/lib');
      if (lib.existsSync()) carpetas.add(lib);
    }
  }
  return carpetas;
}

Future<List<ArchivoDartLeido>> _archivosDeCodigo() async {
  final todos = <ArchivoDartLeido>[];
  for (final carpeta in _carpetasDeCodigo()) {
    todos.addAll(await leerArbolDartResiliente(carpeta));
  }
  return todos;
}

final _dataClassName = RegExp(r'''@DataClassName\(\s*['"](\w+)['"]''');

/// Los nombres de las clases de fila que declaran las tablas de Drift (`@DataClassName('XFila')`).
Set<String> nombresDeFilas(Iterable<ArchivoDartLeido> archivos) => {
  for (final archivo in archivos)
    for (final linea in archivo.lineas)
      for (final m in _dataClassName.allMatches(linea)) m.group(1)!,
};

/// Los nombres de las variables, parámetros y campos que [linea] declara con el tipo de una fila:
/// `UbicacionFila fila`, `UbicacionFila? previa`, `List<PersonaFila> personas`, `final NotaFila nota`.
Set<String> variablesDeFila(String linea, Set<String> filas) {
  if (filas.isEmpty) return const {};
  final tipos = filas.join('|');
  final declaracion = RegExp('\\b(?:$tipos)\\b[?>\\s]*\\s(\\w+)');
  return {for (final m in declaracion.allMatches(linea)) m.group(1)!};
}

/// Los usos prohibidos de [variables] en [linea]: interpolación (`$v`, `${v}`), `v.toString()` y la
/// variable como argumento de un log o de un `print`.
List<String> usosProhibidos(String linea, Set<String> variables) {
  final usos = <String>[];
  for (final v in variables) {
    final nombre = RegExp.escape(v);
    final patrones = <String, RegExp>{
      // `'$fila'` y también `'$fila.id'` (el clásico: interpola la fila entera y deja ".id" como texto).
      r'interpolación $variable': RegExp('\\\$$nombre(?![\\w])'),
      r'interpolación ${variable}': RegExp('\\\$\\{\\s*$nombre\\s*[!?]?\\s*\\}'),
      'toString()': RegExp('\\b$nombre[!?]?\\.toString\\(\\)'),
      'argumento de un log o print': RegExp(
        '\\b(?:print|debugPrint|\\w*[lL]og\\w*(?:\\.\\w+)?|logger(?:\\.\\w+)?)\\(\\s*$nombre\\s*[,)]',
      ),
    };
    patrones.forEach((motivo, patron) {
      if (patron.hasMatch(linea)) usos.add('$motivo de `$v`');
    });
  }
  return usos;
}

/// Los campos de dirección o de coordenadas que no pueden aparecer en un `toString()` escrito a mano.
final _camposDeDireccion = RegExp(
  r'\b(?:calle|numero|número|lat|lon|lng|latitud|longitud|direccion|dirección|coordenadas?)\b',
  caseSensitive: false,
);

/// Los `toString()` a mano que nombran un campo de dirección o de coordenadas. Mira la declaración y
/// su cuerpo: hasta el `;` de una flecha, o hasta que se cierra el bloque.
List<String> toStringConDireccion(List<String> lineas) {
  final fallas = <String>[];
  for (var i = 0; i < lineas.length; i++) {
    if (_esComentario(lineas[i]) ||
        !lineas[i].contains(RegExp(r'String\s+get\s+toString|String\s+toString\s*\('))) {
      continue;
    }
    var llaves = 0;
    var abrio = false;
    for (var j = i; j < lineas.length && j < i + 40; j++) {
      final linea = lineas[j];
      if (!_esComentario(linea) &&
          _camposDeDireccion.hasMatch(j == i ? linea.split('toString').last : linea)) {
        fallas.add('${i + 1}: ${lineas[i].trim()}');
        break;
      }
      llaves += '{'.allMatches(linea).length - '}'.allMatches(linea).length;
      if (linea.contains('{')) abrio = true;
      if (linea.contains('=>') && linea.trimRight().endsWith(';')) break;
      if (abrio && llaves <= 0) break;
    }
  }
  return fallas;
}

void main() {
  group('Arquitectura — las filas de Drift no se interpolan (#565)', () {
    late List<ArchivoDartLeido> archivos;
    late Set<String> filas;

    setUpAll(() async {
      archivos = await _archivosDeCodigo();
      filas = nombresDeFilas(archivos);
    });

    test('el barrido encuentra las filas de las tablas (si no, el chequeo no mira nada)', () {
      expect(archivos, isNotEmpty);
      expect(
        filas,
        containsAll(<String>['UbicacionFila', 'PersonaFila', 'NotaFila', 'SyncQueueFila']),
      );
    });

    test('ninguna fila de Drift se interpola, se pasa a `toString()` ni se vuelca en un log', () {
      final fuera = <String>[];
      for (final archivo in archivos) {
        // Variables de fila declaradas en el archivo (las `*Fila` de las tablas son públicas).
        final variables = <String>{
          for (final linea in archivo.lineas)
            if (!_esComentario(linea)) ...variablesDeFila(linea, filas),
        };
        if (variables.isEmpty) continue;
        for (var i = 0; i < archivo.lineas.length; i++) {
          final linea = archivo.lineas[i];
          if (_esComentario(linea)) continue;
          for (final uso in usosProhibidos(linea, variables)) {
            fuera.add('${_normal(archivo.path)}:${i + 1}: $uso — ${linea.trim()}');
          }
        }
      }

      expect(
        fuera,
        isEmpty,
        reason:
            'el `toString()` de una fila de Drift vuelca todas sus columnas (calle, número, '
            'coordenadas, nombre, teléfono). Loguear o interpolar solo el id (convenciones §7.5):\n'
            '${fuera.join('\n')}',
      );
    });

    test('ningún `toString()` escrito a mano nombra campos de dirección o coordenadas', () {
      final fuera = <String>[];
      for (final archivo in archivos) {
        for (final falla in toStringConDireccion(archivo.lineas)) {
          fuera.add('${_normal(archivo.path)}:$falla');
        }
      }

      expect(
        fuera,
        isEmpty,
        reason:
            'un `toString()` con calle, número o coordenadas los filtra a cualquier log o '
            'excepción que lo interpole (convenciones §7.5):\n${fuera.join('\n')}',
      );
    });
  });

  // Que el chequeo muerda: sobre código sintético con el defecto, tiene que marcarlo; y sobre el uso
  // correcto (solo el id), no.
  group(
    'Arquitectura — el detector de filas interpoladas detecta lo que tiene que detectar (#565)',
    () {
      const filas = {'UbicacionFila', 'PersonaFila'};

      Set<String> declaradas(String linea) => variablesDeFila(linea, filas);

      test(
        'reconoce las variables tipadas como fila (con `?`, genéricos, `final` y parámetros)',
        () {
          expect(declaradas('final UbicacionFila fila = await _leer();'), {'fila'});
          expect(declaradas('UbicacionFila? previa;'), {'previa'});
          expect(declaradas('final List<PersonaFila> personas = [];'), {'personas'});
          expect(declaradas('void f(UbicacionFila a, PersonaFila b) {}'), {'a', 'b'});
          expect(declaradas('final x = UbicacionFila(id: 1);'), isEmpty);
          expect(declaradas('final Persona persona = Persona();'), isEmpty);
        },
      );

      test('marca la interpolación, el `toString()` y el log con la fila', () {
        const v = {'fila'};
        expect(usosProhibidos("print('fila: \$fila');", v), isNotEmpty);
        expect(usosProhibidos("throw StateError('no existe \${fila}');", v), isNotEmpty);
        expect(usosProhibidos("final t = 'x \$fila.id';", v), isNotEmpty);
        expect(usosProhibidos('final t = fila.toString();', v), isNotEmpty);
        expect(usosProhibidos('final t = fila!.toString();', v), isNotEmpty);
        expect(usosProhibidos('_log.info(fila);', v), isNotEmpty);
        expect(usosProhibidos('debugPrint(fila);', v), isNotEmpty);
      });

      test('no marca el uso correcto: el id, un campo suelto o el nombre parecido', () {
        const v = {'fila'};
        expect(usosProhibidos("log('fila \${fila.id}');", v), isEmpty);
        expect(usosProhibidos("log('fila \${fila.id}', {'id': fila.id});", v), isEmpty);
        expect(usosProhibidos("final t = 'x \$filaVieja';", v), isEmpty);
        expect(usosProhibidos('final p = Persona(id: fila.id);', v), isEmpty);
        expect(usosProhibidos('mapear(fila);', v), isEmpty);
        expect(usosProhibidos('// print(fila)', {'otra'}), isEmpty);
      });

      test(
        'marca un `toString()` con dirección o coordenadas y deja pasar el que solo nombra el id',
        () {
          expect(
            toStringConDireccion([
              'class A {',
              '  @override',
              "  String toString() => 'A(\$calle \$numero)';",
              '}',
            ]),
            hasLength(1),
          );
          expect(
            toStringConDireccion([
              '  @override',
              '  String toString() {',
              '    return "A(\${lat}, \${lon})";',
              '  }',
            ]),
            hasLength(1),
          );
          expect(
            toStringConDireccion([
              "  String toString() => 'A(\$id)';",
              "  String toString() => 'B(oculta)';",
            ]),
            isEmpty,
          );
        },
      );
    },
  );
}
