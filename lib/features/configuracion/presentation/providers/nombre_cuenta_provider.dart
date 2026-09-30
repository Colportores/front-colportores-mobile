import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Nombre de la cuenta para mostrar en Configuración («Lucía Silva»). `null` mientras no haya
/// fuente: la sesión solo trae el correo. Lo completa #243 (datos de la cuenta); hasta entonces
/// Configuración muestra solo el correo.
final nombreCuentaProvider = Provider<String?>((ref) => null);
