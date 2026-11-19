/**
 * DecorationController — manages decoration groups and styles.
 *
 * Holds the `applyDecorations` / `setDecorationStyle` logic and the
 * subgroup / style state used by the reader facade.
 */

import {
  Decoration,
  DecorationLayout,
  DecorationStyleType,
  DecorationWidth,
  EpubNavigator,
  WebPubNavigator,
} from "@readium/navigator";
import { Locator } from "@readium/shared";
import {
  SPOTLIGHT_GROUP_SUFFIX,
  navIframeWindows,
  setSpotlightGroupOnIframes,
  clearSpotlightState,
} from "./decorationFrameUtils";
import { dartColorToCss } from "../utils/colors";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import { createLogger } from "../utils/ReadiumPluginLogger";

const log = createLogger("DecorationController");

/** Wire shape of `MarginMarker.toJson()` on the Dart side. */
interface MarginMarker {
  label?: string;
  icon?: string;
  side?: string;
}

/** SVG path data (24x24 viewBox) by `MarginMarkerIcon` name. Keep in sync with Dart, iOS and Android. */
const MARGIN_MARKER_ICON_PATHS = new Map<string, string>([
  ["bookmark", "M6 2h12a1 1 0 0 1 1 1v19l-7-4-7 4V3a1 1 0 0 1 1-1z"],
  ["note", "M4 3h16a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H9l-5 4v-4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zM7 7v2h10V7zm0 4v2h7v-2z"],
  ["star", "M12 2l2.9 6.9 7.1.6-5.4 4.7 1.6 7-6.2-3.8-6.2 3.8 1.6-7L2 9.5l7.1-.6z"],
]);

function marginMarkerIconSvg(icon: string): string | undefined {
  const path = MARGIN_MARKER_ICON_PATHS.get(icon);
  return path === undefined
    ? undefined
    : `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="1.3em" height="1.3em" fill="currentColor" fill-rule="evenodd" style="display: block;"><path d="${path}"/></svg>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/**
 * Builds the margin marker element, or `null` when there is nothing to show. Keep the markup identical
 * to the iOS and Android templates; the design is in docs/plans/margin-marker-decorations.md.
 */
function marginMarkerHtml(marker: MarginMarker | undefined, tint: string | undefined): string | null {
  const content = marker?.label
    ? escapeHtml(marker.label)
    : marker?.icon !== undefined
      ? marginMarkerIconSvg(marker.icon)
      : undefined;
  if (!content) return null;

  const end = marker?.side === "end";
  let css =
    `float: ${end ? "right" : "left"} !important; float: ${end ? "inline-end" : "inline-start"} !important;` +
    " margin: 0 max(4px, 1.5%) !important; font-size: 0.75em !important; line-height: 1.4 !important;";
  // Labels are muted like printed margin page numbers; icons keep the full colour.
  if (marker?.label) css += " opacity: 0.8 !important;";
  if (tint) css += ` color: ${escapeHtml(tint)} !important;`;
  return `<div><span data-activable="1" style="${css}">${content}</span></div>`;
}

export interface ApplyDecorationsOptions {
  /**
   * Report taps on these decorations through `onDecorationInteraction`.
   * Only for groups the app applied itself; TTS / media-overlay highlights are not tappable.
   */
  tappable?: boolean;
}

export class DecorationController {
  constructor(private readonly _bridge: Pick<ReadiumBridge, "emitDecorationInteraction">) {}

  // Upstream (sub)groups with an observer on `_observedNav`.
  // Upstream's destroy() drops its own observers, so a new navigator starts clean.
  private _observedNav: EpubNavigator | WebPubNavigator | undefined;
  private readonly _observedGroups = new Set<string>();

  // Stored decoration styles for TTS/media-overlay use.
  // Defaults match iOS/Android: yellow highlight for utterance, black underline for range.
  // Stored in Dart #AARRGGBB format so dartColorToCss() converts them correctly when
  // they flow through applyDecorations(). Overridden by setDecorationStyle() from Dart.
  private _utteranceStyle: object | null = { style: "highlight", tint: "#ffffff00" };
  private _rangeStyle: object | null = { style: "underline", tint: "#ff000000" };

  get utteranceStyle(): object | null {
    return this._utteranceStyle;
  }

  get rangeStyle(): object | null {
    return this._rangeStyle;
  }

  /**
   * Apply a set of decorations to the visual navigator.
   * Replaces any previously applied decorations in the same group.
   */
  applyDecorations(
    nav: EpubNavigator | WebPubNavigator,
    group: string,
    decorationsJson: string,
    options: ApplyDecorationsOptions = {}
  ): void {
    const spotlightGroup = group + SPOTLIGHT_GROUP_SUFFIX;

    const decorationsRaw: Array<{
      id: string;
      locator: object;
      style: { style: string; tint?: string; marker?: MarginMarker };
    }> = JSON.parse(decorationsJson);

    // Every subgroup gets a list, even an empty one, so that a subgroup the new
    // list no longer uses is cleared (replacement semantics).
    const bySubgroup = new Map<string, Decoration[]>([
      [group, []],
      [spotlightGroup, []],
    ]);

    for (const raw of decorationsRaw) {
      if (raw.style.style === "marginMarker") {
        const tint = raw.style.tint ? dartColorToCss(raw.style.tint) : undefined;
        const html = marginMarkerHtml(raw.style.marker, tint);
        if (html === null) {
          log.warn(`applyDecorations: skipping marginMarker ${raw.id} without a label or known icon`);
          continue;
        }
        bySubgroup.get(group)!.push({
          id: raw.id,
          locator: Locator.deserialize(raw.locator)!,
          style: {
            type: DecorationStyleType.Template,
            layout: DecorationLayout.Bounds,
            width: DecorationWidth.Page,
            element: () => html,
          },
          // Upstream ignores a Template's element when diffing, so the payload goes into extras
          // to make a changed label, icon, side or tint re-render under the same id.
          extras: { marker: raw.style.marker, tint },
        });
        continue;
      }

      const isSpotlight = raw.style.style === "spotlight";
      // Convert tints from Dart's AARRGGBB to CSS RRGGBBAA at the entry point so
      // upstream's Decorator and the spotlight CSS see CSS colors.
      const tint = raw.style.tint ? dartColorToCss(raw.style.tint) : undefined;

      bySubgroup.get(isSpotlight ? spotlightGroup : group)!.push({
        id: raw.id,
        locator: Locator.deserialize(raw.locator)!,
        style: {
          type: raw.style.style === "underline"
            ? DecorationStyleType.Underline
            : DecorationStyleType.Highlight,
          tint,
          width: DecorationWidth.Wrap,
          // Keep plugin-selected decoration tints faithful on web instead of
          // letting Readium adjust them to satisfy its contrast heuristic.
          enforceContrast: false,
        },
      });
    }

    for (const [subgroup, decorations] of bySubgroup) {
      nav.applyDecorations(decorations, subgroup);
      if (options.tappable) this._observe(nav, subgroup, group);
    }

    // Spotlight is driven by decoration presence: activate when the spotlight
    // subgroup is non-empty, deactivate when empty.
    setSpotlightGroupOnIframes(
      navIframeWindows(nav),
      spotlightGroup,
      bySubgroup.get(spotlightGroup)!.length > 0
    );
  }

  /**
   * Update TTS utterance and range decoration styles.
   * Applied immediately to the provided TTS engine if one is active.
   *
   * @param utteranceStyleJson  JSON-encoded ReaderDecorationStyle or null.
   * @param rangeStyleJson      JSON-encoded ReaderDecorationStyle or null.
   * @param onStylesUpdated     Optional callback invoked after storing the new styles.
   */
  setDecorationStyle(
    utteranceStyleJson: string | null,
    rangeStyleJson: string | null,
    onStylesUpdated?: (utterance: object | null, range: object | null) => void
  ): void {
    this._utteranceStyle = utteranceStyleJson ? JSON.parse(utteranceStyleJson) : null;
    this._rangeStyle = rangeStyleJson ? JSON.parse(rangeStyleJson) : null;
    onStylesUpdated?.(this._utteranceStyle, this._rangeStyle);
  }

  /** Release the closed navigator and the spotlight mirror (call on closePublication). */
  reset(): void {
    this._observedNav = undefined;
    clearSpotlightState();
  }

  /**
   * Makes `subgroup` tappable, once per navigator. Reports `parentGroup` (the name
   * the app used), never the internal spotlight subgroup name.
   */
  private _observe(
    nav: EpubNavigator | WebPubNavigator,
    subgroup: string,
    parentGroup: string
  ): void {
    if (this._observedNav !== nav) {
      this._observedNav = nav;
      this._observedGroups.clear();
    }
    if (this._observedGroups.has(subgroup)) return;

    nav.registerDecorationObserver(subgroup, {
      onDecorationActivated: (activation) => {
        this._bridge.emitDecorationInteraction({
          decorationId: activation.decoration.id,
          group: parentGroup,
          type: "tap",
          // serialize() keeps otherLocations Map entries that a plain stringify drops.
          locator: activation.decoration.locator.serialize(),
        });
        return true;
      },
    });
    this._observedGroups.add(subgroup);
  }
}
