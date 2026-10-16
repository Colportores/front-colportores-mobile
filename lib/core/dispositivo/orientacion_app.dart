import 'package:flutter/services.dart';

/// Orientación de la app: **solo vertical** (decisión de Cristian del 07/10, #301). Todos los
/// diseños son verticales y el horizontal no se diseña ni se prueba.
///
/// La regla vive en tres lugares que dicen lo mismo, para que Android e iOS hagan igual:
/// `android:screenOrientation="portrait"` en `AndroidManifest.xml`, `UISupportedInterfaceOrientations`
/// (y su variante `~ipad`) en `Info.plist`, y [fijarVertical] al arrancar. Android 16 ignora la
/// orientación fija en pantallas de 600 dp o más (tablets); los teléfonos la respetan.
abstract final class OrientacionApp {
  /// Lo único que la app acepta: el teléfono derecho, con la parte de arriba hacia arriba.
  static const List<DeviceOrientation> permitidas = [DeviceOrientation.portraitUp];

  /// Pide al sistema que no gire la app. Se llama una vez, al arrancar (`main.dart`).
  static Future<void> fijarVertical() => SystemChrome.setPreferredOrientations(permitidas);
}
