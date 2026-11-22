// Issue #717 — la interfaz no se superpone con la barra de navegación de Android.
//
// Toda hoja inferior modal se abre por `mostrarHojaInferior` (`core/presentation/hoja_inferior.dart`),
// que deja su contenido sobre la barra de navegación del sistema. `showModalBottomSheet` crudo con
// `useSafeArea: true` solo cuida el borde de arriba y, en Android 15 o más (la app se dibuja de borde
// a borde), el pie de la hoja quedaba tapado. Este chequeo estático falla si alguien vuelve a abrir
// una hoja con `showModalBottomSheet` o `showBottomSheet` fuera de ese helper.
import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/lectura_resiliente_arbol.dart';

const _helper = 'core/presentation/hoja_inferior.dart';

String _normal(String ruta) => ruta.replaceAll(r'\', '/');

bool _esComentario(String linea) => linea.trimLeft().startsWith('//');

void main() {
  group('Arquitectura — hojas inferiores sobre la barra de navegación (#717)', () {
    test(
      'nadie abre una hoja con `showModalBottomSheet` o `showBottomSheet` fuera del helper',
      () async {
        final archivos = await leerArbolDartResiliente(Directory('lib'));
        expect(archivos, isNotEmpty);
        final patron = RegExp(r'\b(showModalBottomSheet|showBottomSheet)\b');
        final fuera = <String>[];
        for (final archivo in archivos) {
          if (_normal(archivo.path).endsWith('lib/$_helper')) continue;
          for (var i = 0; i < archivo.lineas.length; i++) {
            final linea = archivo.lineas[i];
            if (!_esComentario(linea) && patron.hasMatch(linea)) {
              fuera.add('${_normal(archivo.path)}:${i + 1}: ${linea.trim()}');
            }
          }
        }

        expect(
          fuera,
          isEmpty,
          reason:
              'las hojas inferiores se abren con `mostrarHojaInferior` para quedar sobre la barra de '
              'navegación del sistema (#717):\n${fuera.join('\n')}',
        );
      },
    );
  });
}
