// Qué sugiere HU-VIS según el estado de la ubicación alternativa (HU-UBI-013) y los textos de la HU.
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/motivo_rechazo_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_ubicacion_alternativa.dart';
import 'package:test/test.dart';

void main() {
  final ubicacion = Ubicacion(
    id: 'ub-2',
    tipo: TipoUbicacion.negocio,
    calle: 'Av. Italia',
    numero: '2810',
    lat: -34.89,
    lon: -56.16,
    ciudadId: 'mvd',
    auditoria: Auditoria(
      createdAt: DateTime.utc(2026, 10, 22),
      updatedAt: DateTime.utc(2026, 10, 22),
    ),
  );

  test('dada una alternativa vigente, HU-VIS la sugiere y no hay nada que actualizar', () {
    final estado = UbicacionAlternativaVigente(ubicacion);

    expect(estado.sugerida, ubicacion);
    expect(estado.requiereActualizar, isFalse);
  });

  test(
    'dada una persona sin alternativa, no hay nada que sugerir ni que actualizar: se cobra en la '
    'ubicación del espacio',
    () {
      expect(const SinUbicacionAlternativa().sugerida, isNull);
      expect(const SinUbicacionAlternativa().requiereActualizar, isFalse);
    },
  );

  test('dada una alternativa dada de baja o que falta, no se sugiere y hay que actualizarla', () {
    for (final estado in const <EstadoUbicacionAlternativa>[
      UbicacionAlternativaDeBaja('ub-2'),
      UbicacionAlternativaFaltante('ub-2'),
    ]) {
      expect(estado.sugerida, isNull);
      expect(estado.requiereActualizar, isTrue);
    }
  });

  test('dados dos estados con el mismo contenido, son iguales', () {
    expect(const UbicacionAlternativaDeBaja('a'), const UbicacionAlternativaDeBaja('a'));
    expect(const UbicacionAlternativaDeBaja('a'), isNot(const UbicacionAlternativaFaltante('a')));
    expect(UbicacionAlternativaVigente(ubicacion), UbicacionAlternativaVigente(ubicacion));
  });

  test('dado cada motivo de rechazo, el mensaje dice qué pasa y qué hacer y cae en un campo '
      'conocido', () {
    for (final motivo in MotivoRechazoUbicacionAlternativa.values) {
      expect(motivo.mensaje, isNotEmpty, reason: motivo.name);
      expect(['persona', 'espacio', 'ubicacionAlternativa'], contains(motivo.campo));
    }
  });

  test('dados los textos de la HU, son los literales de los escenarios', () {
    expect(TextosUbicacionAlternativa.establecer, 'Establecer ubicación alternativa de cobranza');
    expect(TextosUbicacionAlternativa.quitar, 'Quitar ubicación alternativa');
    expect(TextosUbicacionAlternativa.bannerDeBaja, 'Ubicación alternativa dada de baja');
    expect(
      TextosUbicacionAlternativa.sinOtrasUbicaciones,
      'Registrá otra ubicación para usarla como alternativa',
    );
    expect(
      TextosUbicacionAlternativa.avisoDeBaja,
      'Ubicación alternativa dada de baja — actualizar antes de agendar cobranza',
    );
  });
}
