/**
 * DecorationController — manages decoration groups and styles.
 *
 * Holds the `applyDecorations` / `setDecorationStyle` logic and the
 * subgroup / style state used by the reader facade.
 */

import {
  Decoration,
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
      style: { style: string; tint: string };
    }> = JSON.parse(decorationsJson);

    // Every subgroup gets a list, even an empty one, so that a subgroup the new
    // list no longer uses is cleared (replacement semantics).
    const bySubgroup = new Map<string, Decoration[]>([
      [group, []],
      [spotlightGroup, []],
    ]);

    for (const raw of decorationsRaw) {
      const isSpotlight = raw.style.style === "spotlight";
      // Convert tints from Dart's AARRGGBB to CSS RRGGBBAA at the entry point so
      // upstream's Decorator and the spotlight CSS see CSS colors.
      const tint = dartColorToCss(raw.style.tint);

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
      onDecorationActivated: (event) => {
        this._bridge.emitDecorationInteraction({
          decorationId: event.decoration.id,
          group: parentGroup,
          type: "tap",
          // serialize() keeps otherLocations Map entries that a plain stringify drops.
          locator: event.decoration.locator.serialize(),
        });
        return true;
      },
    });
    this._observedGroups.add(subgroup);
  }
}
