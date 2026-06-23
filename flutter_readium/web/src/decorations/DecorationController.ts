/**
 * DecorationController — manages decoration groups and styles.
 *
 * Holds the `applyDecorations` / `setDecorationStyle` logic and the
 * subgroup / style state used by the reader facade.
 */

import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { Decoration, DecorationLayout, DecorationWidth } from "@readium/navigator-html-injectables";
import { Locator } from "@readium/shared";
import {
  UNDERLINE_GROUP_SUFFIX,
  SPOTLIGHT_GROUP_SUFFIX,
  sendDecorate,
  navIframeWindows,
  registerPendingDecorationGroup,
  setSpotlightGroupOnIframes,
  clearSpotlightState,
} from "./decorationFrameUtils";
import { dartColorToCss } from "../utils/colors";

export class DecorationController {
  // Maps group name → set of decoration IDs currently applied.
  private readonly _decorationsByGroup: Map<string, Set<string>> = new Map();

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
  applyDecorations(nav: EpubNavigator | WebPubNavigator, group: string, decorationsJson: string): void {
    const underlineGroup = group + UNDERLINE_GROUP_SUFFIX;
    const spotlightGroup = group + SPOTLIGHT_GROUP_SUFFIX;

    // Clear all subgroups for replacement semantics.
    for (const grp of [group, underlineGroup, spotlightGroup]) {
      sendDecorate(nav, grp, "clear", undefined);
      this._decorationsByGroup.set(grp, new Set());
    }

    const decorationsRaw: Array<{
      id: string;
      locator: object;
      style: { style: string; tint: string };
    }> = JSON.parse(decorationsJson);

    // Convert tints from Dart's AARRGGBB to CSS RRGGBBAA at the entry point so
    // all downstream paths (highlight fill, underline CSS) see CSS colors.
    for (const item of decorationsRaw) {
      item.style.tint = dartColorToCss(item.style.tint);
    }

    const iframes = navIframeWindows(nav);

    // Look ahead to collect the first tint per subgroup for FIFO pairing.
    const firstTintByGroup = new Map<string, { isUnderline: boolean; tint: string }>();
    for (const raw of decorationsRaw) {
      const grp = this._subgroupFor(group, raw.style.style);
      if (!firstTintByGroup.has(grp)) {
        firstTintByGroup.set(grp, { isUnderline: raw.style.style === "underline", tint: raw.style.tint });
      }
    }
    for (const [grp, meta] of firstTintByGroup) {
      registerPendingDecorationGroup(iframes, grp, meta.isUnderline, meta.tint);
    }

    for (const raw of decorationsRaw) {
      const usesBoundsLayout = raw.style.style === "underline";
      const targetGroup = this._subgroupFor(group, raw.style.style);

      const decoration: Decoration = {
        id: raw.id,
        locator: Locator.deserialize(raw.locator)!,
        style: {
          tint: raw.style.tint,
          width: DecorationWidth.Wrap,
          // Underline decorations use bounds layout to avoid clipping the underline at the edges of the text.
          ...(usesBoundsLayout ? { layout: DecorationLayout.Bounds } : {}),
          // Keep plugin-selected decoration tints faithful on web instead of
          // letting Readium adjust them to satisfy its contrast heuristic.
          enforceContrast: false,
        },
      };
      sendDecorate(nav, targetGroup, "add", decoration);
      this._decorationsByGroup.get(targetGroup)!.add(raw.id);
    }

    // Spotlight is driven by decoration presence: activate when the spotlight
    // subgroup is non-empty, deactivate when empty.
    const hasSpotlight = (this._decorationsByGroup.get(spotlightGroup)?.size ?? 0) > 0;
    setSpotlightGroupOnIframes(iframes, spotlightGroup, hasSpotlight);
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

  /** Clear all stored decoration group state (call on closePublication). */
  reset(): void {
    this._decorationsByGroup.clear();
    clearSpotlightState();
  }

  private _subgroupFor(group: string, style: string): string {
    switch (style) {
      case "underline": return group + UNDERLINE_GROUP_SUFFIX;
      case "spotlight": return group + SPOTLIGHT_GROUP_SUFFIX;
      default:          return group; // "highlight" and anything unknown
    }
  }
}
