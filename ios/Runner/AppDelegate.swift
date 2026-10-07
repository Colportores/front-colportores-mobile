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
    registrarCanalAlmacenamientoTiles(engineBridge.pluginRegistry)
  }

  /// Canal `colportores/almacenamiento_tiles` (HU-SYNC-010, #189): lo que la descarga de los mapas
  /// offline pregunta del almacenamiento. Del lado de Dart, `AlmacenamientoTilesCanal`. Los dos
  /// métodos reciben `{ruta}`.
  ///
  /// - `bytesLibres`: `volumeAvailableCapacityForImportantUsage`, lo que iOS le puede dar a la app
  ///   (incluye lo que el sistema libera solo, como cachés), no el libre crudo del volumen.
  /// - `excluirDeBackup`: marca la carpeta con `isExcludedFromBackup`: los mapas se vuelven a bajar y
  ///   no tienen por qué ir a iCloud.
  private func registrarCanalAlmacenamientoTiles(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "AlmacenamientoTiles") else { return }
    let canal = FlutterMethodChannel(
      name: "colportores/almacenamiento_tiles",
      binaryMessenger: registrar.messenger()
    )
    canal.setMethodCallHandler { call, result in
      guard let argumentos = call.arguments as? [String: Any],
        let ruta = argumentos["ruta"] as? String
      else {
        result(FlutterError(code: "ALMACENAMIENTO_TILES", message: "falta la ruta", details: nil))
        return
      }
      var url = URL(fileURLWithPath: ruta)
      switch call.method {
      case "bytesLibres":
        do {
          let valores = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          if let libres = valores.volumeAvailableCapacityForImportantUsage {
            result(NSNumber(value: libres))
          } else {
            result(FlutterError(code: "ALMACENAMIENTO_TILES", message: "sin dato", details: nil))
          }
        } catch {
          result(FlutterError(code: "ALMACENAMIENTO_TILES", message: "bytesLibres", details: nil))
        }
      case "excluirDeBackup":
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        do {
          try url.setResourceValues(valores)
          result(true)
        } catch {
          result(FlutterError(code: "ALMACENAMIENTO_TILES", message: "excluirDeBackup", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
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
