import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let mapsKey = resolveMapsApiKey()
    if !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func resolveMapsApiKey() -> String {
    if let key = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String, !key.isEmpty {
      return key
    }
    if let key = ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"], !key.isEmpty {
      return key
    }
    let encoded = "QUl6YVN5Q0lGZHdqLTZYRlB0N25OTlRDNUx6ejNwUTNYUDlYMDlj"
    if let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: .utf8) {
      return decoded
    }
    return ""
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
