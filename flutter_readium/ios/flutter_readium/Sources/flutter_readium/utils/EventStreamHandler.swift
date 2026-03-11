import Flutter

class EventStreamHandler: NSObject, FlutterStreamHandler {

  private let streamName: String
  private var channel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  public func sendEvent(_ event: Any?) {
    eventSink?(event)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Log.readium.debug("StreamHandler.onListen: \(self.streamName)")
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Log.readium.debug("StreamHandler.onCancel: \(self.streamName)")
    eventSink = nil
    return nil
  }

  func dispose() {
    Log.readium.debug("StreamHandler.dispose: \(self.streamName)")
    // End stream and clear the event-sink to prevent memory leaks.
    eventSink?(FlutterEndOfEventStream)
    eventSink = nil
    channel.setStreamHandler(nil)
  }

  init(withName streamName: String, messenger: FlutterBinaryMessenger) {
    self.streamName = streamName
    channel = FlutterEventChannel(name: "dk.nota.flutter_readium/\(streamName)", binaryMessenger: messenger)
    super.init()

    channel.setStreamHandler(self)
  }
}
