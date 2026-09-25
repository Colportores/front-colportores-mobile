import Flutter
import LocalAuthentication
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registrarCanalSeguridadDispositivo(engineBridge.pluginRegistry)
  }

  /// Canal `colportores/seguridad_dispositivo` (ADR-006, HU-AUTH-009): lo que la app pregunta del
  /// equipo antes de crear la DB local. Del lado de Dart, `SeguridadDispositivoCanal`.
  ///
  /// - `bloqueoPantalla`: si hay código, Touch ID o Face ID (`deviceOwnerAuthentication`). Solo
  ///   pregunta si se puede evaluar: no le pide nada al usuario.
  /// - `nivelAlmacen`: siempre `"hardware"`. El Keychain de iOS está respaldado por hardware; el
  ///   Supuesto S10 (Keystore por software) es solo de Android.
  private func registrarCanalSeguridadDispositivo(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SeguridadDispositivo") else { return }
    let canal = FlutterMethodChannel(
      name: "colportores/seguridad_dispositivo",
      binaryMessenger: registrar.messenger()
    )
    canal.setMethodCallHandler { call, result in
      switch call.method {
      case "bloqueoPantalla":
        var error: NSError?
        result(LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error))
      case "nivelAlmacen":
        result("hardware")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
