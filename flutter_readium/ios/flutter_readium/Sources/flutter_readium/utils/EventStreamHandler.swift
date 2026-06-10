import Flutter

/// Buffering contract (keep platforms aligned):
///
/// On iOS the `FlutterEventChannel` `onListen` handshake is asynchronous and
/// can complete *after* the EPUB platform-view has already fired its first
/// `locationDidChange`, silently dropping that event. Android and Web are
/// immune by construction — Android emits the first locator only after
/// `onPageLoaded` (long after the Dart handshake) and dispatches via a
/// coroutine, and Web uses in-process `StreamController`s with no handshake.
/// `bufferLatestEvent` brings iOS into line with that guarantee.
///
/// Rule of thumb for whether a channel should buffer:
///   - Buffer **state-like** streams, where the latest value is meaningful to a
///     late subscriber (`text-locator`, `reader-status`).
///   - Do NOT buffer **event-like / sentinel** streams, where replaying the last
///     value to a new subscriber is wrong (`timebased-state` emits a `.none`
///     sentinel on `closePublication()`; `error` is a one-shot notification).
/// Buffered streams must be cleared on `closePublication()` so a stale value
/// from a closed publication is never replayed to the next one.
class EventStreamHandler: NSObject, FlutterStreamHandler {

  private let streamName: String
  private var channel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  // When true, the most recent event is held in `bufferedEvent` whenever
  // the Dart subscriber is not yet attached (eventSink == nil). The buffer
  // is flushed immediately on onListen so the subscriber never misses the
  // first event despite the async channel-handshake timing. See the
  // class-level buffering contract above for which streams should opt in.
  private let bufferLatestEvent: Bool
  // Any?? distinguishes "nothing buffered" (nil) from "nil was buffered" (.some(.none)).
  private var bufferedEvent: Any?? = nil

  public func sendEvent(_ event: Any?) {
    if let sink = eventSink {
      sink(event)
    } else if bufferLatestEvent {
      bufferedEvent = .some(event)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Log.readium.debug("StreamHandler.onListen: \(self.streamName)")
    eventSink = events
    // Flush any event that arrived before Dart had a chance to subscribe.
    if let event = bufferedEvent {
      events(event)
      bufferedEvent = nil
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Log.readium.debug("StreamHandler.onCancel: \(self.streamName)")
    eventSink = nil
    return nil
  }

  /// Discards any buffered event without delivering it.
  ///
  /// Call this on `closePublication()` so that the last event from a closed
  /// publication is never replayed to the subscriber of the next publication.
  func clearBuffer() {
    bufferedEvent = nil
  }

  func dispose() {
    Log.readium.debug("StreamHandler.dispose: \(self.streamName)")
    // End stream and clear the event-sink to prevent memory leaks.
    eventSink?(FlutterEndOfEventStream)
    eventSink = nil
    bufferedEvent = nil
    channel.setStreamHandler(nil)
  }

  init(withName streamName: String, messenger: FlutterBinaryMessenger, bufferLatestEvent: Bool = false) {
    self.streamName = streamName
    self.bufferLatestEvent = bufferLatestEvent
    channel = FlutterEventChannel(name: "dk.nota.flutter_readium/\(streamName)", binaryMessenger: messenger)
    super.init()

    channel.setStreamHandler(self)
  }
}
