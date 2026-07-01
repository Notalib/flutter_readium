import { FrameClickEvent } from "@readium/navigator-html-injectables";
import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { ReadiumPublication } from "./ReadiumExtensions";
import { navIframeWindows } from "../decorations/decorationFrameUtils";
import { createLogger } from "./ReadiumPluginLogger";

const log = createLogger("ImageTap");

/**
 * Tries to detect whether a FrameClickEvent hit an <img> element inside the
 * navigator content frame. If so, builds and returns a JSON-serialised
 * ImageTapEvent payload (matching the Dart `ImageTapEvent.fromJson` contract).
 * Returns null if no image was hit.
 *
 * The publication-relative `href` is derived by matching the absolute `img.src`
 * URL's pathname against the publication manifest links via suffix matching — a
 * richer match than `findLinkByHref` (which only compares relative hrefs).
 */
export function tryBuildImageTapPayload(
  e: FrameClickEvent,
  nav: EpubNavigator | WebPubNavigator,
  publication: ReadiumPublication
): string | null {
  try {
    if (publication.conformsToDivina) return null;

    // Find the iframe Window whose src matches the click's target frame.
    const iframes = navIframeWindows(nav);
    let targetWnd =
      iframes.find((w) => {
        try {
          return (
            w.location?.href === e.targetFrameSrc ||
            w.document?.URL === e.targetFrameSrc
          );
        } catch {
          return false;
        }
      }) ?? null;

    if (!targetWnd && iframes.length === 1) {
      // Single-spine fallback: only one iframe is ever active.
      log.debug("Frame not matched by src; using sole iframe as fallback");
      targetWnd = iframes[0];
    }

    if (!targetWnd) {
      log.debug("No matching iframe found for targetFrameSrc:", e.targetFrameSrc);
      return null;
    }

    // Resolve the tapped element. Prefer the upstream-provided cssSelector — it
    // references the exact clicked element computed *inside* the content frame.
    // The (e.x, e.y) coordinates are NOT usable with elementFromPoint: upstream
    // Peripherals multiplies them by devicePixelRatio, so on any HiDPI/Retina
    // display (dpr > 1) they overshoot and hit the wrong element or nothing.
    // elementFromPoint is kept only as a dpr-corrected last resort.
    let el: Element | null = null;
    if (e.cssSelector) {
      try {
        el = targetWnd.document.querySelector(e.cssSelector);
      } catch (selErr) {
        log.debug("querySelector failed for cssSelector:", e.cssSelector, selErr);
      }
    }
    if (!el) {
      const dpr = targetWnd.devicePixelRatio || 1;
      el = targetWnd.document.elementFromPoint(e.x / dpr, e.y / dpr);
    }
    if (!el) {
      log.debug("Could not resolve tapped element (cssSelector + elementFromPoint)");
      return null;
    }

    // Walk up the DOM to find an <img> at or near the tap point.
    const imgEl = el.closest("img") as HTMLImageElement | null;
    if (!imgEl) return null;
    if (isNotaComicPageImage(imgEl)) return null;

    // Resolved absolute src and natural dimensions.
    const srcUrl = imgEl.src ?? "";
    const naturalWidth = imgEl.naturalWidth > 0 ? imgEl.naturalWidth : undefined;
    const naturalHeight = imgEl.naturalHeight > 0 ? imgEl.naturalHeight : undefined;

    // Bounding rect in the iframe's coordinate space.
    const domRect = imgEl.getBoundingClientRect();
    const rect = {
      x: domRect.x,
      y: domRect.y,
      width: domRect.width,
      height: domRect.height,
    };

    // Derive publication-relative href from the absolute img.src URL.
    // Suffix-matches the src pathname against all manifest links — richer than
    // findLinkByHref which only handles relative hrefs.
    let href = "";
    if (srcUrl) {
      try {
        const srcPath = new URL(srcUrl).pathname;
        const matched = publication.allLinks.find((l) => {
          try {
            return new URL(l.href).pathname === srcPath || srcPath.endsWith(l.href);
          } catch {
            return srcPath.endsWith(l.href) || l.href.endsWith(srcPath);
          }
        });
        if (!matched) {
          log.debug("No manifest link matched for img.src pathname:", srcPath);
        }
        href = matched?.href ?? srcPath;
      } catch (urlErr) {
        log.warn("Failed to parse img.src as URL:", srcUrl, urlErr);
        href = imgEl.getAttribute("src") ?? "";
      }
    }

    const alt = imgEl.getAttribute("alt") || undefined;
    const payload = {
      href,
      ...(alt !== undefined && { alt }),
      rect,
      ...(naturalWidth !== undefined && { pixelWidth: naturalWidth }),
      ...(naturalHeight !== undefined && { pixelHeight: naturalHeight }),
      ...(srcUrl && { srcUrl }),
    };

    log.debug("Image tap detected: href=", href, "srcUrl=", srcUrl);
    return JSON.stringify(payload);
  } catch (err) {
    log.warn("tryBuildImageTapPayload threw unexpectedly:", err);
    return null;
  }
}

function isNotaComicPageImage(imgEl: HTMLImageElement): boolean {
  const figure = imgEl.closest("figure");
  return (
    (imgEl.classList?.contains("page") === true && !!figure?.querySelector(".area")) ||
    imgEl.closest(".nota-comicbook-page-container") !== null
  );
}
