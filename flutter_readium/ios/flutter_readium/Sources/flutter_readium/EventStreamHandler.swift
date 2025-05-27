import Flutter

class EventStreamHandler: NSObject, FlutterStreamHandler {

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

  var eventSink: FlutterEventSink?
  var streamName: String
  let TAG: String

  init(streamName: String) {
    self.streamName = streamName
    self.TAG = "EventStreamHandler[\(streamName)]"
  }
}
