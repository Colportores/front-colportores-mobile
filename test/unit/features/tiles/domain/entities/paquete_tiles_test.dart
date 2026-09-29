// Test de dominio: Dart puro. Cubre paquete_tiles, estado_descarga y cobertura_tiles.
import 'package:colportores_mobile/features/tiles/domain/entities/cobertura_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

void main() {
  const ambito = AmbitoTrabajo(zonaId: 'z-1', ciudadId: 'c-1', departamentoId: 'd-1');
  final bytes = bytesDePrueba(10);

  PaqueteTiles construir(NivelCobertura nivel, String? ambitoId, {String? checksum}) {
    final id = '${nivel.name}-$ambitoId';
    return paqueteDe(bytes, id: id, nivel: nivel, ambitoId: ambitoId, checksum: checksum);
  }

  PaqueteDescargado descargado(PaqueteTiles paquete) {
    return PaqueteDescargado(paquete: paquete, ruta: '/tiles/${paquete.id}.pmtiles');
  }

  group('PaqueteTiles.cubre', () {
    test('dado un paquete de cada nivel con el id del ámbito, cubre ese ámbito', () {
      expect(construir(NivelCobertura.zona, 'z-1').cubre(ambito), isTrue);
      expect(construir(NivelCobertura.ciudad, 'c-1').cubre(ambito), isTrue);
      expect(construir(NivelCobertura.departamento, 'd-1').cubre(ambito), isTrue);
      expect(construir(NivelCobertura.uruguay, null).cubre(ambito), isTrue);
    });

    test('dado otro lugar o un ámbito sin ese nivel, no lo cubre', () {
      expect(construir(NivelCobertura.zona, 'z-2').cubre(ambito), isFalse);
      expect(construir(NivelCobertura.ciudad, 'c-1').cubre(const AmbitoTrabajo()), isFalse);
      expect(construir(NivelCobertura.departamento, null).cubre(ambito), isFalse);
    });
  });

  test('megabytesDe redondea para arriba con 1 MB = 1 000 000 bytes', () {
    expect(megabytesDe(0), 0);
    expect(megabytesDe(-5), 0);
    expect(megabytesDe(1), 1);
    expect(megabytesDe(87 * 1000 * 1000), 87);
    expect(megabytesDe(87 * 1000 * 1000 + 1), 88);
    expect(construir(NivelCobertura.zona, 'z-1').megabytes, 1);
  });

  group('elegirPaqueteOffline', () {
    test('dado varios paquetes que cubren el lugar, elige el de nivel más chico', () {
      final uruguay = descargado(construir(NivelCobertura.uruguay, null));
      final ciudad = descargado(construir(NivelCobertura.ciudad, 'c-1'));
      final otraZona = descargado(construir(NivelCobertura.zona, 'z-9'));

      expect(elegirPaqueteOffline([uruguay, otraZona, ciudad], ambito), ciudad);
      expect(elegirPaqueteOffline([uruguay], ambito), uruguay);
    });

    test('dado que ninguno cubre el lugar, devuelve null', () {
      final otraZona = descargado(construir(NivelCobertura.zona, 'z-9'));

      expect(elegirPaqueteOffline([otraZona], ambito), isNull);
      expect(elegirPaqueteOffline(const [], ambito), isNull);
    });
  });

  group('EstadoDescarga', () {
    test('DescargaEnCurso.progreso va de 0 a 1 y no se pasa', () {
      expect(const DescargaEnCurso('p', recibidos: 250, total: 1000).progreso, 0.25);
      expect(const DescargaEnCurso('p', recibidos: 5, total: 0).progreso, 0);
      expect(const DescargaEnCurso('p', recibidos: 2000, total: 1000).progreso, 1);
    });

    test('DescargaPausada sigue sola salvo que la haya pausado el colportor', () {
      DescargaPausada pausa(MotivoPausa motivo) {
        return DescargaPausada('p', motivo: motivo, recibidos: 1, total: 2);
      }

      expect(pausa(MotivoPausa.usuario).sigueSola, isFalse);
      expect(pausa(MotivoPausa.sinWifi).sigueSola, isTrue);
      expect(pausa(MotivoPausa.sinConexion).sigueSola, isTrue);
    });

    test('DescargaCompletada toma el id del paquete descargado', () {
      final completo = descargado(construir(NivelCobertura.zona, 'z-1'));

      expect(DescargaCompletada(completo).paqueteId, 'zona-z-1');
      expect(DescargaCompletada(completo), DescargaCompletada(completo));
    });
  });

  test('OpcionCobertura.hayActualizacion compara el checksum del catálogo con el descargado', () {
    final actual = construir(NivelCobertura.zona, 'z-1');
    final nuevo = construir(NivelCobertura.zona, 'z-1', checksum: 'v2');
    final bajado = descargado(actual);
    bool hay(PaqueteTiles? delCatalogo, PaqueteDescargado? enTelefono) {
      const nivel = NivelCobertura.zona;
      final opcion = OpcionCobertura(nivel: nivel, paquete: delCatalogo, descargado: enTelefono);
      return opcion.hayActualizacion;
    }

    expect(hay(nuevo, bajado), isTrue);
    expect(hay(actual, bajado), isFalse);
    expect(hay(null, bajado), isFalse);
    expect(hay(nuevo, null), isFalse);
  });
}
