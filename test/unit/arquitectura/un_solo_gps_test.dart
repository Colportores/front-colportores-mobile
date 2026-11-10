// HU-UBI-003 / issue #651 — un solo GPS del colportor.
//
// Decisión de Cristian (04/11): el permiso de ubicación se pide solo desde el mapa principal y
// ninguna otra vista llama a `posicionActual()`. Todo pasa por `ubicacionColportorProvider`, el
// único que lee el GPS y el único que abre el diálogo del permiso («Activar GPS»). El resto de las
// vistas (Lista, alta, Modificar, Precios) leen su estado.
//
// Chequeo estático sobre `lib/`, con la misma lectura resiliente que `dominio_puro_test.dart`.
import 'dart:io';

import 'package:test/test.dart';

import '../../helpers/lectura_resiliente_arbol.dart';

const _providerUnico = 'features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
const _adaptador = 'features/mapa/data/services/proveedor_gps_plataforma.dart';
const _casoDeUso = 'features/mapa/domain/usecases/capturar_posicion_gps_use_case.dart';
const _cableado = 'features/mapa/presentation/providers/alta_ubicacion_providers.dart';

String _normal(String ruta) => ruta.replaceAll(r'\', '/');

bool _esDe(String ruta, String archivo) => _normal(ruta).endsWith('lib/$archivo');

bool _esComentario(String linea) => linea.trimLeft().startsWith('//');

/// Las líneas de código (no comentarios) de `lib/` que cumplen [patron], fuera de [permitidos].
Future<List<String>> _usosFuera(RegExp patron, List<String> permitidos) async {
  final archivos = await leerArbolDartResiliente(Directory('lib'));
  expect(archivos, isNotEmpty);
  final fuera = <String>[];
  for (final archivo in archivos) {
    if (permitidos.any((p) => _esDe(archivo.path, p))) continue;
    for (var i = 0; i < archivo.lineas.length; i++) {
      final linea = archivo.lineas[i];
      if (!_esComentario(linea) && patron.hasMatch(linea)) {
        fuera.add('${_normal(archivo.path)}:${i + 1}: ${linea.trim()}');
      }
    }
  }
  return fuera;
}

void main() {
  group('Arquitectura — un solo GPS del colportor (#651)', () {
    test(
      'nadie llama a `posicionActual()` salvo el caso de uso que usa el provider único',
      () async {
        final fuera = await _usosFuera(RegExp(r'\.posicionActual\('), [_casoDeUso]);

        expect(
          fuera,
          isEmpty,
          reason:
              'solo el GPS único del colportor lee el teléfono (decisión de Cristian, 04/11):\n'
              '${fuera.join('\n')}',
        );
      },
    );

    test('solo el provider único usa el caso de uso que lee el GPS', () async {
      final fuera = await _usosFuera(RegExp(r'capturarPosicionGpsUseCaseProvider'), [
        _providerUnico,
        _cableado,
      ]);

      expect(
        fuera,
        isEmpty,
        reason:
            'las vistas leen `ubicacionColportorProvider`, no piden el GPS:\n${fuera.join('\n')}',
      );
    });

    test('solo el provider único abre el permiso o los ajustes («Activar GPS»)', () async {
      final fuera = await _usosFuera(RegExp(r'activadorGpsProvider|ProveedorGpsPlataforma\b'), [
        _providerUnico,
        _cableado,
        _adaptador,
      ]);

      expect(
        fuera,
        isEmpty,
        reason: 'el diálogo del permiso sale de un solo lugar:\n${fuera.join('\n')}',
      );
    });

    test('solo el provider único abre el stream del seguimiento (#670)', () async {
      final fuera = await _usosFuera(RegExp(r'seguidorGpsProvider|\.seguir\(\)'), [
        _providerUnico,
        _cableado,
        _adaptador,
        'features/mapa/data/services/plataforma_gps_geolocator.dart',
      ]);

      expect(
        fuera,
        isEmpty,
        reason: 'el seguimiento de la ubicación lo maneja el GPS único:\n${fuera.join('\n')}',
      );
    });

    test('ninguna vista toca el puerto ni el plugin del GPS', () async {
      final fuera = await _usosFuera(
        RegExp(r'proveedorGpsProvider|proveedorGpsPlataformaProvider|plataformaGpsProvider'),
        [_cableado],
      );

      expect(fuera, isEmpty, reason: 'el puerto del GPS se cablea una vez:\n${fuera.join('\n')}');
    });
  });
}
