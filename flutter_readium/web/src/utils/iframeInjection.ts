import type { IInjectableRule } from "@readium/navigator";

/**
 * Dataset flag set on an iframe's documentElement once our helper scripts have
 * been injected, so repeated `frameLoaded` calls for the same frame are no-ops.
 */
const HELPER_INJECTED_FLAG = "flutterReadiumHelperInjected";

/**
 * URLs of the prebuilt helper bundle. These are the same files that native
 * (iOS / Android) injects into the EPUB webview, so injecting them here gives
 * the web iframe the same capabilities (comic pan/zoom overlay, flutterReadium
 * tools, responsive tables, etc.).
 */
let helperJsUrl = "assets/packages/flutter_readium/assets/helpers/flutterReadiumTools.js";
let helperCssUrl = "assets/packages/flutter_readium/assets/helpers/flutterReadiumTools.css";

/** Dart passes the served URLs, which carry a content hash under `--web-content-hash`. */
export function setHelperAssetUrls(jsUrl: string, cssUrl: string): void {
  helperJsUrl = jsUrl;
  helperCssUrl = cssUrl;
}

// Cache the fetched text so subsequent iframes (on the same page or after a
// chapter navigation) don't hit the network again.
let _cachedHelperJs: string | null = null;
let _cachedHelperCss: string | null = null;

async function _fetchHelperAssets(): Promise<{ js: string; css: string } | null> {
  try {
    if (_cachedHelperJs === null) {
      const res = await fetch(helperJsUrl);
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${helperJsUrl}`);
      _cachedHelperJs = await res.text();
    }
    if (_cachedHelperCss === null) {
      const res = await fetch(helperCssUrl);
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${helperCssUrl}`);
      _cachedHelperCss = await res.text();
    }
    return { js: _cachedHelperJs, css: _cachedHelperCss };
  } catch (err) {
    console.warn("[FlutterReadium] Failed to fetch helper assets:", err);
    return null;
  }
}

/**
 * Inject the MO column-break style tag directly into an iframe window's DOM.
 * Idempotent — does nothing if the tag is already present.
 */
export function injectMOBreakCSSIntoWindow(wnd: Window): void {
  const doc = wnd.document;
  if (doc.getElementById("flutter-readium-mo-breaks")) return;
  const style = doc.createElement("style");
  style.id = "flutter-readium-mo-breaks";
  style.textContent = "p { break-inside: avoid !important }";
  doc.head.appendChild(style);
}

/**
 * Readium reads `document.scrollingElement` without a null check, and Safari returns null in a
 * quirks-mode frame. Prepended so it runs in every frame before Readium's modules attach.
 */
const SCROLLING_ELEMENT_GUARD = `(function () {
  try {
    var nativeGet = Object.getOwnPropertyDescriptor(Document.prototype, "scrollingElement").get;
    Object.defineProperty(document, "scrollingElement", {
      configurable: true,
      get: function () {
        return nativeGet.call(document) || document.body || document.documentElement;
      },
    });
  } catch (_) {}
})();`;

export function scrollingElementGuardRule(): IInjectableRule {
  return {
    resources: [/.*/],
    prepend: [{
      id: "flutter-readium-scrolling-element-guard",
      as: "script",
      target: "head",
      blob: new Blob([SCROLLING_ELEMENT_GUARD], { type: "text/javascript" }),
    }],
  };
}

/**
 * Injects the Flutter Readium helper bundle (JS + CSS) and a bootstrap script
 * into a freshly-loaded EPUB iframe, mirroring what native iOS / Android do via
 * `WKUserScript` / `TransformingResource`.
 *
 * Injected in the same order as native:
 *   1. Bootstrap inline script: `isAndroid`, `isIos` flags + `window.readiumTocIDs`
 *   2. Helper CSS (as an inline `<style>`)
 *   3. Helper JS bundle (as an inline `<script>`)
 *
 * Idempotent: skipped when the iframe's `documentElement.dataset` already has
 * the `flutterReadiumHelperInjected` flag.
 *
 * @param wnd      The iframe's `contentWindow`.
 * @param tocIds   Flattened list of fragment ids from the publication's TOC.
 *                 Mirrors `window.readiumTocIDs` injected by native.
 */
export async function injectFlutterReadiumHelperScripts(
  wnd: Window,
  tocIds: string[]
): Promise<void> {
  const doc = wnd.document;

  if (doc.documentElement.dataset[HELPER_INJECTED_FLAG] === "true") return;
  doc.documentElement.dataset[HELPER_INJECTED_FLAG] = "true";

  const assets = await _fetchHelperAssets();
  if (!assets) return;

  // 1. Bootstrap: OS flags + TOC ids. The scrollingElement guard is not here:
  // see `scrollingElementGuardRule`.
  const bootstrap = doc.createElement("script");
  bootstrap.textContent = [
    "const isAndroid = false;",
    "const isIos = false;",
    `window.readiumTocIDs = ${JSON.stringify(tocIds)};`,
  ].join("\n");
  doc.head.appendChild(bootstrap);

  // 2. CSS
  const style = doc.createElement("style");
  style.textContent = assets.css;
  doc.head.appendChild(style);

  // 3. JS bundle
  const script = doc.createElement("script");
  script.textContent = assets.js;
  doc.head.appendChild(script);
}
