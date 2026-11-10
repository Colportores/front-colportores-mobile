// Los textos de «Mapas offline» para los mapas grandes (#287): pesos en GB y «cuánto falta».
import 'package:colportores_mobile/features/tiles/presentation/textos_mapas_offline.dart';
import 'package:test/test.dart';

void main() {
  group('sinLugar', () {
    test('sin «falta» es el texto del canvas', () {
      expect(
        TextosMapasOffline.sinLugar('Montevideo', '86 MB', '40 MB', haySalida: false),
        'No hay lugar: Montevideo ocupa 86 MB y te quedan 40 MB. Liberá espacio en el teléfono.',
      );
    });

    test('con «falta» lo suma, en plural y en singular', () {
      expect(
        TextosMapasOffline.sinLugar(
          'Todo Uruguay',
          '1,2 GB',
          '400 MB',
          haySalida: true,
          falta: '800 MB',
        ),
        'No hay lugar: Todo Uruguay ocupa 1,2 GB y te quedan 400 MB. Te faltan 800 MB. '
        'Elegí un mapa más chico o liberá espacio.',
      );
      expect(
        TextosMapasOffline.sinLugar(
          'San José',
          '250 MB',
          '249 MB',
          haySalida: false,
          falta: '1 MB',
        ),
        contains('Te falta 1 MB.'),
      );
      expect(
        TextosMapasOffline.sinLugar(
          'Todo Uruguay',
          '1,2 GB',
          '1,1 GB',
          haySalida: false,
          falta: '1,2 GB',
        ),
        contains('Te faltan 1,2 GB.'),
      );
    });
  });

  group('pesos grandes', () {
    test('lo que se libera pasa a GB desde los 1000 MB, redondeado para abajo', () {
      expect(TextosMapasOffline.megasLiberados(72), '72 MB');
      expect(TextosMapasOffline.megasLiberados(999), '999 MB');
      expect(TextosMapasOffline.megasLiberados(1000), '1,0 GB');
      expect(TextosMapasOffline.megasLiberados(1199), '1,1 GB');
      expect(TextosMapasOffline.megasLiberados(1200), '1,2 GB');
    });

    test('«mapa borrado» y «achicar» usan ese peso', () {
      expect(TextosMapasOffline.mapaBorrado(86), 'Mapa borrado. Liberaste 86 MB.');
      expect(TextosMapasOffline.mapaBorrado(1200), 'Mapa borrado. Liberaste 1,2 GB.');
      expect(TextosMapasOffline.mapaBorrado(0), 'Mapa borrado.');
      expect(
        TextosMapasOffline.achicarTexto(
          mayor: 'Todo Uruguay',
          elegido: 'Montevideo',
          liberanMegabytes: 1114,
        ),
        startsWith('Borramos el mapa de Todo Uruguay y liberás 1,1 GB. '),
      );
    });

    test('el avance sigue en «36 de 86 MB» y pasa a «412 MB de 1,2 GB» en un mapa de GB', () {
      expect(TextosMapasOffline.avanceDe(36 * 1000 * 1000, 86 * 1000 * 1000), '36 de 86 MB');
      expect(
        TextosMapasOffline.avanceDe(412 * 1000 * 1000, 1200 * 1000 * 1000),
        '412 MB de 1,2 GB',
      );
      expect(
        TextosMapasOffline.avanceDe(1100 * 1000 * 1000, 1200 * 1000 * 1000),
        '1,1 GB de 1,2 GB',
      );
    });
  });
}
