import 'package:flutter/services.dart';

/// Orientación de la app: **solo vertical** (decisión de Cristian del 07/10, #301). Todos los
/// diseños son verticales y el horizontal no se diseña ni se prueba.
///
/// La regla vive en tres lugares que dicen lo mismo, para que Android e iOS hagan igual:
/// `android:screenOrientation="portrait"` en `AndroidManifest.xml`, `UISupportedInterfaceOrientations`
/// en `Info.plist`, y [fijarVertical] al arrancar. Android 16 ignora la orientación fija en
/// pantallas de 600 dp o más (tablets); los teléfonos la respetan. iOS es solo iPhone (decisión de
/// Cristian del 21/10, #385): `TARGETED_DEVICE_FAMILY = 1`; en un iPad se instala y abre como app
/// de iPhone, vertical, así que no hay variante `~ipad`.
abstract final class OrientacionApp {
  /// Lo único que la app acepta: el teléfono derecho, con la parte de arriba hacia arriba.
  static const List<DeviceOrientation> permitidas = [DeviceOrientation.portraitUp];

  /// Pide al sistema que no gire la app. Se llama una vez, al arrancar (`main.dart`).
  static Future<void> fijarVertical() => SystemChrome.setPreferredOrientations(permitidas);
}
