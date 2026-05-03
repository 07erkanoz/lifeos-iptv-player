import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Reserved for a future AVPictureInPictureController integration. Today
  /// the channel is registered (so Dart can `listen()` without a crash) but
  /// no events are emitted on iOS yet.
  private var pipEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      registerPlatformChannels(with: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerPlatformChannels(with: engineBridge.binaryMessenger)
  }

  // MARK: - Platform channels

  private func registerPlatformChannels(with messenger: FlutterBinaryMessenger) {
    let platformChannel = FlutterMethodChannel(
      name: "com.lifeostv.lifeostv/platform",
      binaryMessenger: messenger
    )
    platformChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "isTV":
        // iOS has no TV form factor; tvOS would be a separate target.
        result(false)

      case "getGpuRenderer":
        // gpu_detector.dart maps any string containing "apple" to GpuVendor.apple.
        result("Apple GPU (Metal)")

      case "getHardware":
        result(UIDevice.current.model)

      case "setPlayerActive":
        // Toggle the AVAudioSession so audio keeps playing when the user
        // backgrounds the app. Pairs with UIBackgroundModes=audio in Info.plist.
        let args = call.arguments as? [String: Any]
        let active = args?["active"] as? Bool ?? false
        self?.setBackgroundAudioActive(active)
        result(nil)

      case "enterPipMode":
        // Real PiP needs to attach AVPictureInPictureController to the
        // AVPlayerLayer that media_kit_video uses internally — that work is
        // out of scope for this patch. Acknowledge so the Dart side does not
        // see MissingPluginException.
        result(false)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let pipEventChannel = FlutterEventChannel(
      name: "com.lifeostv.lifeostv/pip_events",
      binaryMessenger: messenger
    )
    pipEventChannel.setStreamHandler(PipEventStreamHandler { [weak self] sink in
      self?.pipEventSink = sink
    })
  }

  private func setBackgroundAudioActive(_ active: Bool) {
    let session = AVAudioSession.sharedInstance()
    do {
      if active {
        try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
        try session.setActive(true)
      } else {
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
      }
    } catch {
      NSLog("[LifeOsTV] AVAudioSession toggle failed: \(error.localizedDescription)")
    }
  }
}

// MARK: - PipEventStreamHandler

private final class PipEventStreamHandler: NSObject, FlutterStreamHandler {
  private let setSink: (FlutterEventSink?) -> Void

  init(setSink: @escaping (FlutterEventSink?) -> Void) {
    self.setSink = setSink
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    setSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    setSink(nil)
    return nil
  }
}
