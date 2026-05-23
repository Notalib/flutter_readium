import { ReadiumReaderStatus } from "./enums";

declare global {
  interface Window {
    /**
     * Inform the Flutter app of the current reader status.
     * Registered by the Dart side via `@JS() external set updateReaderStatus`.
     */
    updateReaderStatus?: (status: ReadiumReaderStatus) => void;

    /**
     * Update the current text locator in the Flutter app.
     * @param locatorJson JSON-stringified Locator
     */
    updateTextLocator?: (locatorJson: string) => void;

    /**
     * Update time-based player state (audiobook / media overlay).
     * @param stateJson JSON-stringified ReadiumTimebasedState
     */
    updateTimebasedPlayerState?: (stateJson: string) => void;

    /**
     * Callback for text selection events.
     * @param selectionJson JSON-stringified TextSelectionEvent
     */
    onTextSelectedCallback?: (selectionJson: string) => void;
  }
}

