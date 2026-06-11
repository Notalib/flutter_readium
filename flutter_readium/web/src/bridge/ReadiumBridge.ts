/**
 * ReadiumBridge — the single module allowed to call window.* emit callbacks.
 *
 * All outbound events from the plugin to Flutter are routed through the typed
 * methods below so every emission site is traceable. Navigators and the facade
 * receive the bridge (or specific emit callbacks) by injection rather than
 * reaching window directly.
 *
 * JSON shapes mirror the Dart js_interop declarations in
 * lib/src/js_publication_channel.dart — never change them.
 */

import { Locator } from "@readium/shared";
import { ReadiumReaderStatus } from "../model/ReadiumReaderStatus";

export class ReadiumBridge {
  /** Emit the current reader status to Flutter. */
  emitReaderStatus(status: ReadiumReaderStatus): void {
    window.updateReaderStatus?.(status);
  }

  /**
   * Emit a text locator to Flutter (bookmark / position save).
   * Always uses `locator.serialize()` so `otherLocations` Map entries survive.
   */
  emitTextLocator(locator: Locator): void {
    window.updateTextLocator?.(JSON.stringify(locator.serialize()));
  }

  /**
   * Emit a timebased player state JSON payload to Flutter.
   * The payload is already serialized by the caller (AudioNavigator / TTS).
   */
  emitTimebasedState(stateJson: string): void {
    window.updateTimebasedPlayerState?.(stateJson);
  }

  /**
   * Emit a text-selection event to Flutter.
   * @param selectionJson JSON-stringified TextSelectionEvent
   */
  emitTextSelected(selectionJson: string): void {
    window.onTextSelectedCallback?.(selectionJson);
  }

  /**
   * Emit a non-fatal error to Flutter.
   * @param message Human-readable error description.
   * @param code    Optional machine-readable error code.
   */
  emitError(message: string, code?: string): void {
    window.onErrorCallback?.(JSON.stringify({ message, ...(code ? { code } : {}) }));
  }

  /**
   * Emit an image-tap event to Flutter.
   * @param json JSON-stringified ImageTapEvent payload
   */
  emitImageTapped(json: string): void {
    window.onImageTappedCallback?.(json);
  }
}
