// El atrás del sistema llega siempre a Flutter (#679): con el atrás predictivo de Android 16, el
// atrás desde «Nueva ubicación» con un campo enfocado sacaba de la app. El manifest no se puede
// probar en un teléfono desde Docker: el test lo lee, para que nadie lo vuelva a prender sin darse
// cuenta (como `orientacion_app_test.dart`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dado el manifest de Android, la actividad deja el atrás a Flutter (sin atrás predictivo)',
    () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final actividad = RegExp(
        r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>',
      ).firstMatch(manifest);

      expect(actividad, isNotNull);
      expect(actividad!.group(0), contains('android:enableOnBackInvokedCallback="false"'));
    },
  );
}
