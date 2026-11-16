import AVFoundation
import Flutter

/// Streams the current audio output route (speaker, AirPlay, ...) to Dart.
///
/// Every `onListen` gets the current route first, including the re-listen after a Dart hot
/// restart. The route is device state, so it is never cleared when a publication closes.
final class AudioRouteObserver: NSObject, FlutterStreamHandler {
  private let channel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterEventChannel(name: "dk.nota.flutter_readium/audio-route", binaryMessenger: messenger)
    super.init()
    channel.setStreamHandler(self)
  }

  deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    // The notification is posted on an arbitrary thread; the event sink must be used on main.
    observer = observer ?? NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.sendCurrentRoute()
    }
    sendCurrentRoute()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func sendCurrentRoute() {
    guard let sink = eventSink,
      let output = AVAudioSession.sharedInstance().currentRoute.outputs.first
    else { return }
    sink(["type": Self.routeType(output.portType), "name": output.portName])
  }

  private static func routeType(_ port: AVAudioSession.Port) -> String {
    switch port {
    case .builtInSpeaker, .builtInReceiver: return "builtIn"
    case .headphones, .lineOut, .usbAudio: return "wired"
    case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return "bluetooth"
    case .airPlay: return "airPlay"
    case .carAudio: return "carPlay"
    default: return "other"
    }
  }
}
