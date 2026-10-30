// HU-VIS-006 (#152): dónde se propone cobrar según el estado de la ubicación alternativa (HU-UBI-013).
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/destino_de_cobranza.dart';
import 'package:colportores_mobile/features/agenda/presentation/textos_cobranza_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:flutter_test/flutter_test.dart';

Ubicacion _ubicacion({String? calle = 'Av. Italia', String? numero = '2810'}) => Ubicacion(
  id: 'ub-b',
  tipo: TipoUbicacion.negocio,
  calle: calle,
  numero: numero,
  lat: -34.9,
  lon: -56.16,
  ciudadId: 'mvd',
  auditoria: Auditoria(createdAt: DateTime.utc(2026, 10, 1), updatedAt: DateTime.utc(2026, 10, 1)),
);

void main() {
  group('DestinoDeCobranza.de', () {
    test('dada una alternativa activa, entonces la sugiere con su dirección para el aviso', () {
      final d = DestinoDeCobranza.de(UbicacionAlternativaVigente(_ubicacion()));

      expect(d, isA<CobranzaEnLaAlternativa>());
      expect(d.ubicacionAltId, 'ub-b');
      expect(d.direccionDelAviso, 'Av. Italia 2810');
      expect(d.advierteQueNoSirve, isFalse);
    });

    test('dada una alternativa sin número ni calle, entonces el aviso lleva lo que haya', () {
      expect(
        DestinoDeCobranza.de(
          UbicacionAlternativaVigente(_ubicacion(numero: null)),
        ).direccionDelAviso,
        'Av. Italia',
      );
      expect(
        DestinoDeCobranza.de(
          UbicacionAlternativaVigente(_ubicacion(calle: null, numero: null)),
        ).direccionDelAviso,
        isEmpty,
      );
    });

    test('dada una persona sin alternativa, entonces se cobra en la ubicación del espacio', () {
      final d = DestinoDeCobranza.de(const SinUbicacionAlternativa());

      expect(d, const CobranzaEnLaUbicacionDelEspacio());
      expect(d.ubicacionAltId, isNull);
      expect(d.direccionDelAviso, isEmpty);
      expect(d.advierteQueNoSirve, isFalse);
    });

    test('dada una alternativa dada de baja o ausente del teléfono, entonces no se sugiere y se '
        'advierte', () {
      for (final estado in const <EstadoUbicacionAlternativa>[
        UbicacionAlternativaDeBaja('ub-b'),
        UbicacionAlternativaFaltante('ub-b'),
      ]) {
        final d = DestinoDeCobranza.de(estado);

        expect(d, const CobranzaConAlternativaNoUsable('ub-b'));
        expect(d.ubicacionAltId, isNull);
        expect(d.advierteQueNoSirve, isTrue);
      }
    });
  });

  group('TextosCobranzaAlternativa', () {
    test('confirma el destino como pide la HU', () {
      expect(
        TextosCobranzaAlternativa.destino(ubicacion: 'Ubicación B', persona: 'María'),
        'Ubicación B (alternativa de María)',
      );
    });

    test('el aviso de la alternativa dada de baja es el de la HU, tal cual', () {
      expect(
        TextosCobranzaAlternativa.alternativaInactiva,
        'La ubicación alternativa ya no está activa. Elegí otra o actualizá.',
      );
    });
  });
}
