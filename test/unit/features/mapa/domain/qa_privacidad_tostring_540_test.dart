// QA de #540 (PR #557), criterio de aceptación «Ningún `toString` de una entidad con dirección o nombre imprime
// esos datos» (convenciones §7.5, sin PII en logs). El PR apagó `stringify` en `UnionPendiente`, `FallaUnion` y
// `UnionesPendientesState`, pero el resto de las entidades del mapa que llevan calle, número o coordenadas en
// `props` lo dejan en el valor por defecto de `Equatable` (encendido con los `assert` activos, o sea en debug).
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
}
