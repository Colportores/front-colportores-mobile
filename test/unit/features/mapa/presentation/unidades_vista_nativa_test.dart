// El factor de dp a unidades de la vista nativa del mapa (revisión del #294): los toques van en
// píxeles en Android y en puntos en iOS, pero la etiqueta «cerca tuyo» que se registra en el estilo
// se pinta con la densidad de la pantalla en las dos (con 1 en iOS se veía a 1/2 o 1/3).
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/unidades_vista_nativa.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const densidades = [1.0, 2.0, 2.625, 3.0];

  group('los toques', () {
    test('en Android son píxeles nativos: la densidad de la pantalla', () {
      for (final densidad in densidades) {
        expect(
          UnidadesVistaNativa.paraToques(plataforma: TargetPlatform.android, densidad: densidad),
          densidad,
        );
      }
    });

    test('en iOS son puntos: 1, sea cual sea la densidad', () {
      for (final densidad in densidades) {
        expect(
          UnidadesVistaNativa.paraToques(plataforma: TargetPlatform.iOS, densidad: densidad),
          1,
        );
      }
    });
  });

  group('las imágenes que se registran en el estilo', () {
    test('se pintan con la densidad de la pantalla', () {
      for (final densidad in densidades) {
        expect(UnidadesVistaNativa.paraImagenes(densidad: densidad), densidad);
      }
    });

    test(
      'en iOS no es 1 (el plugin las muestra con `UIScreen.scale`): la etiqueta no se achica',
      () {
        final toques = UnidadesVistaNativa.paraToques(plataforma: TargetPlatform.iOS, densidad: 3);
        final imagenes = UnidadesVistaNativa.paraImagenes(densidad: 3);

        expect(toques, 1);
        expect(imagenes, 3);
        expect(imagenes, isNot(toques));
      },
    );
  });
}
