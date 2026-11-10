// Config común de toda la suite (la corre `flutter test` antes de cada archivo de prueba).
//
// Apaga `EquatableConfig.stringify`, igual que `main.dart`: en debug arranca en `true` y el `toString()`
// de cualquier `Equatable` imprimiría sus `props` (calle, número, coordenadas, nombres). Convenciones
// §7.5 y #540. Los tests que quieren el peor caso lo vuelven a encender y lo restauran
// (`sin_pii_en_tostring_test.dart`).
import 'dart:async';

import 'package:equatable/equatable.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  EquatableConfig.stringify = false;
  await testMain();
}
