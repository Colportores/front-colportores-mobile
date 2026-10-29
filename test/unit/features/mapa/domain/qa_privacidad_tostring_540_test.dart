// QA de #540 (PR #557), criterio de aceptación «Ningún `toString` de una entidad con dirección o nombre imprime
// esos datos» (convenciones §7.5, sin PII en logs). El PR apagó `stringify` en `UnionPendiente`, `FallaUnion` y
// `UnionesPendientesState`, pero el resto de las entidades del mapa que llevan calle, número o coordenadas en
// `props` lo dejan en el valor por defecto de `Equatable` (encendido con los `assert` activos, o sea en debug).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/modificar_ubicacion_falsos.dart' show ubicacionGuardada;

void main() {
  // Decisión §2 (P1, #557): `EquatableConfig.stringify = false` global, en `main.dart` y en
  // `test/flutter_test_config.dart`. Cubre `Ubicacion`, `MarcadorMapa`, `HouseStatus`, `DireccionDelPunto`…
  test('el toString de una ubicación no vuelca la calle, el número ni las coordenadas', () {
    final texto = ubicacionGuardada().toString();
    expect(texto, isNot(contains('Italia')));
    expect(texto, isNot(contains('1234')));
  });

  test('el toString de la dirección del punto no vuelca la calle ni el número', () {
    const direccion = DireccionDelPunto(calle: 'Av. Italia', numero: '1250');
    expect(direccion.toString(), isNot(contains('Italia')));
    expect(direccion.toString(), isNot(contains('1250')));
  });

  // La fila generada por Drift no es un `Equatable`: `EquatableConfig.stringify = false` no la alcanza y su
  // `toString()` vuelca calle, número y coordenadas (`app_database.g.dart`, `UbicacionFila`). Hoy nadie la
  // interpola en un log (por eso es menor), pero un `'$fila'` o una excepción que la incluya la filtraría.
  test(
    'el toString de la fila de la base (UbicacionFila) no vuelca calle, número ni coordenadas',
    () {
      final fila = UbicacionFila(
        id: 'ubi-1',
        tipo: 'CASA',
        calle: 'Av. Italia',
        numero: '1234',
        lat: -34.8851,
        lon: -56.1672,
        ciudadId: 'mvd',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        syncVersion: 1,
      );
      final texto = fila.toString();
      expect(texto, isNot(contains('Italia')));
      expect(texto, isNot(contains('1234')));
      expect(texto, isNot(contains('34.8851')));
    },
    skip:
        'QA #540: el toString de UbicacionFila (Drift, generado) vuelca calle, número y coordenadas',
  );
}
