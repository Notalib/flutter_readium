import Flutter

class EventStreamHandler: NSObject, FlutterStreamHandler {

  private let TAG: String
  private let streamName: String
  private var channel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  public func sendEvent(_ event: Any?) {
    print(TAG, "sendEvent")
    eventSink?(event)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    print(TAG, "onListen: \(streamName)")
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    print(TAG, "onCancel: \(streamName)")
    eventSink = nil
    return nil
  }

  func dispose() {
    print(TAG, "dispose")
    // End stream and clear the event-sink to prevent memory leaks.
    eventSink?(FlutterEndOfEventStream)
    eventSink = nil
    channel.setStreamHandler(nil)
  }

  init(withName streamName: String, messenger: FlutterBinaryMessenger) {
    self.streamName = streamName
    TAG = "EventStreamHandler[\(streamName)]"
    channel = FlutterEventChannel(name: "dk.nota.flutter_readium/\(streamName)", binaryMessenger: messenger)
    super.init()

    channel.setStreamHandler(self)
  }
}
