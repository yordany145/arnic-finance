import Flutter
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

    // Los controles/widgets dejan la ruta a abrir en el App Group (ver ios/ArnicQuick).
    // Dart la recoge al arrancar y al volver a primer plano.
    let channel = FlutterMethodChannel(
      name: "com.arnic.finance/quick",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "consumePendingRoute" else { return result(FlutterMethodNotImplemented) }
      let defaults = UserDefaults(suiteName: "group.com.arnic.finance")
      let route = defaults?.string(forKey: "pending_route")
      defaults?.removeObject(forKey: "pending_route")
      result(route)
    }
  }
}
