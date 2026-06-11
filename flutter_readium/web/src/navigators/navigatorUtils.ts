/**
 * Shared helpers used by both FlutterEpubNavigator and FlutterWebPubNavigator.
 */

import { BasicTextSelection } from "@readium/navigator-html-injectables";
import { Locator } from "@readium/shared";
import { createLogger } from "../utils/ReadiumPluginLogger";

const log = createLogger("NavUtils");

/**
 * Scrolls all visible Readium iframe content windows by 100px in the given
 * direction. Called by the Peripherals `moveTo` handler for keyboard up/down.
 */
export function scrollVisibleIframes(direction: "up" | "down"): void {
  const delta = direction === "up" ? -100 : 100;
  document.querySelectorAll(".readium-navigator-iframe").forEach((iframe) => {
    if (
      iframe instanceof HTMLIFrameElement &&
      iframe.style.visibility !== "hidden"
    ) {
      iframe.contentWindow?.scrollBy(0, delta);
    }
  });
}

/**
 * Handles an external-protocol locator href by prompting the user before
 * opening it in a new tab. For unrecognised hrefs (internal links that fell
 * through), logs a warning.
 */
export function handleExternalLocator(href: string): void {
  if (
    href.startsWith("http://") ||
    href.startsWith("https://") ||
    href.startsWith("mailto:") ||
    href.startsWith("tel:")
  ) {
    if (confirm(`Open "${href}" ?`)) window.open(href, "_blank");
  } else {
    log.warn("Unhandled locator href:", href);
  }
}

/**
 * Builds the JSON payload emitted to `window.onTextSelectedCallback` when the
 * user selects text in the navigator iframe.
 */
export function buildTextSelectionPayload(
  currentLocator: Locator,
  selection: BasicTextSelection
): string {
  const locatorJson = {
    ...currentLocator.serialize(),
    text: { highlight: selection.text },
  };
  return JSON.stringify({ locator: locatorJson, selectedText: selection.text });
}
