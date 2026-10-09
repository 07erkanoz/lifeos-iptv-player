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
        // Configure movie playback and AirPlay. Dart pauses local playback
        // when backgrounded; this does not imply background video support.
        let args = call.arguments as? [String: Any]
        let active = args?["active"] as? Bool ?? false
        do {
          try self?.setBackgroundAudioActive(active)
          result(nil)
        } catch {
          result(FlutterError(code: "audio_session_failed", message: "Unable to configure audio playback.", details: nil))
        }

      case "enterPipMode":
        // The current media_kit renderer is a texture/libmpv surface.
        // PiP requires a separate iOS integration; Dart hides its button.
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
    let audioEvents = FlutterEventChannel(name: "com.lifeostv.lifeostv/audio_events", binaryMessenger: messenger)
    audioEvents.setStreamHandler(AudioEventStreamHandler())
  }

  private func setBackgroundAudioActive(_ active: Bool) throws {
    let session = AVAudioSession.sharedInstance()
    if active {
      try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
      try session.setActive(true)
    } else {
      try session.setActive(false, options: [.notifyOthersOnDeactivation])
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


private final class AudioEventStreamHandler: NSObject, FlutterStreamHandler {
  private var observers: [NSObjectProtocol] = []

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    removeObservers()
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
      guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
      if type == .began {
        events(["kind": "began"])
      } else {
        let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        events(["kind": "ended", "shouldResume": options.contains(.shouldResume)])
      }
    })
    observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { note in
      if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
         reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
        events(["kind": "unplugged"])
      }
    })
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeObservers()
    return nil
  }
  private func removeObservers() {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
  }
  deinit { removeObservers() }
}
