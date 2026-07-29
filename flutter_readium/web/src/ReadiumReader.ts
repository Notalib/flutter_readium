import "./style.css";

import { AudioNavigator, EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { getTime, Link, Locator, Publication } from "@readium/shared";

// Bridge
import { ReadiumBridge } from "./bridge/ReadiumBridge";
// Publication
import { PublicationManager } from "./publication/PublicationManager";
// Decorations
import { DecorationController } from "./decorations/DecorationController";
// Model
import { ReadiumReaderStatus } from "./model/ReadiumReaderStatus";
// Utils
import { createLogger, LogLevel, setLogLevel } from "./utils/ReadiumPluginLogger";
import { ReadiumPublication, findLinkByHref } from "./utils/ReadiumExtensions";
// Navigators
import { FlutterEpubNavigator } from "./navigators/FlutterEpubNavigator";
import { FlutterWebPubNavigator } from "./navigators/FlutterWebPubNavigator";
import { FlutterDivinaNavigator } from "./navigators/FlutterDivinaNavigator";
import { FlutterAudioNavigator, setAudioEmissionsEnabled, seekAudioAndResume } from "./navigators/FlutterAudioNavigator";
import { AudioRecoveryPolicy, setCurrentAudioRecoveryPolicy } from "./navigators/AudioStreamErrorPolicy";
import { FlutterTTSNavigator } from "./navigators/FlutterTTSNavigator";
import { initializeMediaOverlayNavigator, initializeGuidedNavigationNavigator } from "./navigators/FlutterMediaOverlayNavigator";
// Preferences
import { setEpubPreferencesFromString, pluginPrefsFromJson } from "./preferences/FlutterEpubPreferences";
import { ttsPreferencesFromJson } from "./preferences/FlutterTTSPreferences";
import { applyAudioPreferences } from "./preferences/FlutterAudioPreferences";
// Sync narration
import {
  ComicRegion,
  SyncNarrationItem,
  detectSyncNarration,
  findItemByAudioTime,
  textLocatorForItem,
  textLocatorToAudioLocator,
} from "./mediaoverlay/syncNarration";
import { detectGuidedNavigation } from "./mediaoverlay/guidedNavigation";
// Decoration overrides (for comic/visual sync)
import { navIframeWindows } from "./decorations/decorationFrameUtils";
// Iframe injection utilities
import { injectMOBreakCSSIntoWindow } from "./utils/iframeInjection";
// Errors
import { ReadiumWebError, ReadiumWebErrorCode, ResourceReadErrorReason } from "./errors/ReadiumWebError";

const log = createLogger("Reader");

/**
 * The subset of the upstream `VisualNavigator` surface that ReadiumReader drives.
 * Structurally satisfied by the EPUB, WebPub and DiViNa navigators alike, so the
 * reader can treat whichever is active uniformly for navigation. EPUB-only
 * concerns (preferences, decorations) stay on the concrete `_nav` field instead.
 */
interface VisualNavigatorLike {
  readonly publication: Publication;
  readonly currentLocator: Locator;
  goRight(animated: boolean, cb: (ok: boolean) => void): void;
  goLeft(animated: boolean, cb: (ok: boolean) => void): void;
  goForward(animated: boolean, cb: (ok: boolean) => void): void;
  goBackward(animated: boolean, cb: (ok: boolean) => void): void;
  go(locator: Locator, animated: boolean, cb: (ok: boolean) => void): void;
  goLink(link: Link, animated: boolean, cb: (ok: boolean) => void): void;
  destroy(): Promise<void>;
}

class _ReadiumReader {
  public constructor() {
    log.info("ReadiumReader instance created");
  }

  /**
   * Sets the log verbosity for the web bundle.
   * Maps to the Dart LogLevel enum indices: 0=none, 1=error, 2=warn, 3=info, 4=debug.
   */
  public setLogLevel(level: number): void {
    const mapped: LogLevel = level >= 0 && level <= 4 ? level : LogLevel.info;
    setLogLevel(mapped);
    log.info("Log level set to", LogLevel[mapped]);
  }

  /**
   * Configures the automatic audio-stream error recovery loop (retry attempts,
   * backoff, stall detection). Applies to the next-opened publication and to
   * any in-flight recovery loop — not to an already-running attempt sequence.
   */
  public setAudioRecoveryPolicy(policyJson: string): void {
    const policy = AudioRecoveryPolicy.fromJson(JSON.parse(policyJson));
    setCurrentAudioRecoveryPolicy(policy);
    log.info("Audio recovery policy set", policy);
  }

  private _publication: ReadiumPublication | undefined;
  private _nav: EpubNavigator | WebPubNavigator | undefined;
  /**
   * Render-only navigator for the DiViNa / CBZ profile (image comics). Kept
   * separate from `_nav` because it is not an EPUB/WebPub navigator and does not
   * support preferences or decorations. Navigation routes through `_visualNav`.
   */
  private _comicNav: FlutterDivinaNavigator | undefined;
  private _audioNav: AudioNavigator | undefined;
  /** Last audiobook locator selected while audio is stopped/destructed. */
  private _stoppedAudioLocator: Locator | undefined;
  /** Last audio preferences JSON used to create an audio navigator. */
  private _activeAudioPreferencesJson = "{}";
  private _ttsEngine: FlutterTTSNavigator | undefined;
  /** Position list for EPUB publications (used by goToProgression). */
  private _positions: Locator[] = [];
  /** True when the current EPUB publication has embedded Sync Narration JSON. */
  private _hasSyncNarration = false;
  private _hasGuidedNavigation = false;
  /** Parsed sync-narration items for the current MediaOverlay publication. Empty for plain audiobooks. */
  private _syncItems: SyncNarrationItem[] = [];
  /**
   * Unified runtime narration-sync flag. When true (default), audio-driven
   * visual sync is active: MediaOverlay cues scroll the EPUB navigator, and TTS
   * utterances do the same. When false (manual mode), sync cues are deferred and
   * the view stays where the user left it.
   *
   * This is the single source of truth for both the MO and TTS sync paths,
   * replacing the old separate `_disableSynchronization` boolean. It is:
   *   - Seeded from `EPUBPreferences.disableSynchronization` transitions
   *     (only when the preference value actually changes).
   *   - Flipped to false when the user explicitly navigates during active
   *     narration (goRight / goLeft / goForward / goBackward / goTo).
   *   - Flipped by explicit `setNarrationSyncEnabled()` calls from Dart.
   *
   * The DiViNa/comic auto-pan flag is separate; `setNarrationSyncEnabled` also
   * forwards to `_comicNav.setAutoPan()` so the comic path remains the authority
   * for panel-level state.
   */
  private _narrationSyncEnabled = true;
  /** Mirrors `EPUBPreferences.preventMOColumnBreaks`. Defaults to `true`. */
  private _preventMOColumnBreaks = true;
  /** Last visual sync locator deferred while synchronization was disabled. */
  private _lastDeferredSyncLocator: Locator | null = null;
  /** Segment duration paired with `_lastDeferredSyncLocator` when available. */
  private _lastDeferredSyncDurationMs: number | undefined;

  // Deduplication key for Media Overlay decoration: "<href><fragment>".
  // Avoids redundant applyDecorations calls when the poll fires during the same cue.
  private _lastMediaOverlayLocatorKey: string | null = null;

  // Set to true once we've confirmed that any iframe in the current publication
  // is a comic-book page. Used to skip nav.go() for all subsequent cues.
  private _isComicBook = false;

  // Collaborators
  private readonly _bridge = new ReadiumBridge();
  private readonly _pubManager = new PublicationManager();
  private readonly _decorations = new DecorationController();

  /** The active visual navigator (EPUB, WebPub or DiViNa), for navigation calls. */
  private get _visualNav(): VisualNavigatorLike | undefined {
    return this._nav ?? this._comicNav;
  }

  public get isNavigatorReady(): boolean {
    return !!this._visualNav;
  }

  public async getPublication(publicationURL: string) {
    log.info("getPublication", publicationURL);
    try {
      const { publication, manifestJson } = await this._pubManager.fetchAndCache(publicationURL);
      this._publication = publication;
      log.info("Publication fetched:", publication.metadata.identifier ?? "unidentified");
      return manifestJson;
    } catch (error) {
      log.error("Failed to get publication:", error);
      const errorMessage = error instanceof Error ? error.message : String(error);
      this._bridge.emitError("Failed to get publication: " + errorMessage);
      throw error;
    }
  }

  public goRight() {
    log.debug("goRight");
    this._enterManualModeIfNarrating("goRight");
    this._visualNav?.goRight(true, () => {});
  }

  public goLeft() {
    log.debug("goLeft");
    this._enterManualModeIfNarrating("goLeft");
    this._visualNav?.goLeft(true, () => {});
  }

  /**
   * Progression-aware navigation. `goForward` / `goBackward` are RTL-aware on
   * the upstream navigator (unlike `goRight` / `goLeft`, which are purely
   * visual). The Dart-side `goForward`/`goBackward` API maps to these.
   */
  public goForward() {
    log.debug("goForward");
    this._enterManualModeIfNarrating("goForward");
    this._visualNav?.goForward(true, () => {});
  }

  public goBackward() {
    log.debug("goBackward");
    this._enterManualModeIfNarrating("goBackward");
    this._visualNav?.goBackward(true, () => {});
  }

  public async goTo(locatorJson: string): Promise<void> {
    log.info("goTo", locatorJson);

    const locator = Locator.deserialize(JSON.parse(locatorJson));
    if (!locator) {
      log.error("goTo: failed to parse locator JSON");
      throw new ReadiumWebError("Failed to parse locator JSON", ReadiumWebErrorCode.invalidArgument);
    }

    log.info(
      "goTo: routing decision",
      `tts=${!!this._ttsEngine}`,
      `audioNav=${!!this._audioNav}`,
      `syncItems=${this._syncItems.length}`,
      `hasSyncNarration=${this._hasSyncNarration}`
    );

    // TTS-narrated EPUB: restart narration at the new text locator so the spoken
    // position follows ToC / bookmark navigation. The engine's onstart re-syncs
    // the visual navigator to the same locator once the new utterance begins.
    if (this._ttsEngine) {
      log.info("goTo: TTS — restarting narration at", locator.href, locator.locations?.fragments);
      await this._ttsEngine.play(locator);
      return;
    }

    // MediaOverlay EPUB with audio enabled: map text locator → audio locator,
    // seek audio nav, and also scroll the visual navigator to the text position.
    // Mirrors FlutterMediaOverlayNavigator.seek(toLocator:) on iOS/Android.
    if (this._audioNav && this._syncItems.length > 0) {
      const audioLocator = textLocatorToAudioLocator(this._syncItems, locator);
      if (audioLocator) {
        const wasPlaying = this._audioNav.isPlaying;
        log.info(
          "goTo: MediaOverlay — seeking audio to",
          audioLocator.href,
          audioLocator.locations?.fragments,
          `(wasPlaying=${wasPlaying})`
        );
        await this._seekAudioAndResume(audioLocator, wasPlaying);
      } else {
        log.warn("goTo: MediaOverlay — no SyncNarrationItem found for", locator.href, "; falling through to visual navigation");
      }
      // Always update the visual navigator so the page scrolls to the bookmarked paragraph.
      const visualPub = this._visualNav?.publication;
      const visualLinks = [
        ...(visualPub?.readingOrder?.items ?? []),
        ...(visualPub?.resources?.items ?? []),
      ];
      const visualLink = findLinkByHref(visualLinks, locator.href);
      if (visualLink) {
        this._visualNav?.goLink(visualLink, true, (ok) => {
          if (!ok) log.warn("goTo: MediaOverlay — visual navigation failed for", locator.href);
        });
      }
      return;
    }

    // Pure audiobook (no sync narration): build an audio locator from the
    // incoming locator, preserving any t= time fragment it already carries.
    if (this._audioNav || this._publication?.conformsToAudiobook) {
      const allLinks = [
        ...(this._publication?.readingOrder?.items ?? []),
        ...(this._publication?.resources?.items ?? []),
      ];
      const link = findLinkByHref(allLinks, locator.href);
      if (!link) {
        log.error("goTo: audio link not found:", locator.href);
        throw new ReadiumWebError("Audio link not found " + locator.href, ReadiumWebErrorCode.invalidArgument, {
          href: locator.href,
        });
      }
      // Preserve t= fragment from the incoming locator when present.
      const audioLocator = new Locator({
        href: link.href,
        type: link.type ?? "audio/mpeg",
        locations: locator.locations,
      });
      if (!this._audioNav) {
        log.info("goTo: stopped audiobook — storing pending audio locator", audioLocator.href, audioLocator.locations?.fragments);
        this._stoppedAudioLocator = audioLocator;
        window.updateTimebasedPlayerState?.(
          JSON.stringify({
            state: "none",
            currentOffset: null,
            currentDuration: null,
            currentLocator: audioLocator.serialize(),
          })
        );
        return;
      }
      const wasPlaying = this._audioNav.isPlaying;
      await this._seekAudioAndResume(audioLocator, wasPlaying);
      return;
    }

    // EPUB / WebPub / DiViNa with no audio active: visual-only navigation.
    const pub = this._visualNav?.publication;
    const allLinks = [
      ...(pub?.readingOrder?.items ?? []),
      ...(pub?.resources?.items ?? []),
    ];
    const link = findLinkByHref(allLinks, locator.href);
    if (!link) {
      log.error("goTo: link not found:", locator.href);
      throw new ReadiumWebError("Link not found " + locator.href, ReadiumWebErrorCode.invalidArgument, {
        href: locator.href,
      });
    }
    this._visualNav?.goLink(link, true, (ok) => {
      if (!ok) {
        log.error("goTo: failed to navigate to link:", locator.href);
        throw new ReadiumWebError(
          "Failed to navigate to link " + locator.href,
          ReadiumWebErrorCode.resourceReadError,
          { reason: ResourceReadErrorReason.navigation, href: locator.href }
        );
      }
    });
  }

  public async openPublication(
    publicationURL: string,
    pubId: string,
    initialPositionJson: string | undefined,
    preferencesJson: string | undefined
  ) {
    log.info("openPublication", { pubId, hasInitialPosition: !!initialPositionJson });
    this._bridge.emitReaderStatus(ReadiumReaderStatus.loading);

    let initialPosition: Locator | undefined;

    if (initialPositionJson) {
      initialPosition = Locator.deserialize(JSON.parse(initialPositionJson));
    }

    let preferencesJsonString =
      !preferencesJson || preferencesJson === "null" ? "{}" : preferencesJson;

    // Reset per-publication state so stale values don't bleed across openPublication calls.
    this._hasSyncNarration = false;
    this._hasGuidedNavigation = false;
    this._syncItems = [];
    this._positions = [];
    this._stoppedAudioLocator = undefined;
    this._activeAudioPreferencesJson = "{}";
    this._lastDeferredSyncLocator = null;
    this._lastDeferredSyncDurationMs = undefined;
    this._narrationSyncEnabled = true;

    try {
      // TODO: match native
      this._publication = await this._pubManager.getOrFetch(pubId, publicationURL);

      if (this._publication.conformsToAudiobook) {
        log.info("Publication conforms to Audiobook profile");
        this._activeAudioPreferencesJson = preferencesJsonString;
        // AudioNavigator doesn't need a DOM container — it drives <audio> elements directly.
        await FlutterAudioNavigator.create(
          this._publication,
          initialPosition,
          preferencesJsonString,
          (nav) => {
            this._audioNav = nav;
            this._bridge.emitReaderStatus(ReadiumReaderStatus.ready);
          },
          undefined,
          undefined,
          undefined,
          this._bridge
        );
      } else {
        // EPUB and WebPub navigators render into a DOM container.
        const container: HTMLElement | null =
          document.body.querySelector("#container");
        if (!container) {
          log.error("Container element #container not found in DOM");
          this._bridge.emitReaderStatus(ReadiumReaderStatus.error);
          // No navigator can be built without a render target, so this blocks
          // opening the publication just like a missing-navigator guard.
          throw new ReadiumWebError("Container element not found", ReadiumWebErrorCode.noPublication);
        }
        if (this._publication.conformsToEpub) {
          log.info("Publication conforms to EPUB profile");
          // Detect sync narration before opening the navigator (async fetch-free check).
          this._hasSyncNarration = detectSyncNarration(this._publication);
          if (this._hasSyncNarration) log.info("Sync Narration detected");
          this._hasGuidedNavigation = detectGuidedNavigation(this._publication);
          if (this._hasGuidedNavigation) log.info("Guided Navigation detected");
          await FlutterEpubNavigator.create(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              this._bridge.emitReaderStatus(ReadiumReaderStatus.ready);
            },
            (positions) => { this._positions = positions; },
            (json) => { this._bridge.emitImageTapped(json); },
            (wnd) => {
              // Re-inject MO column-break CSS into freshly-loaded frames when MO is active.
              // Use direct DOM manipulation — window.flutterReadium is deferred by rAF
              // inside the helper script and may not exist yet at frameLoaded time.
              if (this._audioNav && this._preventMOColumnBreaks) {
                injectMOBreakCSSIntoWindow(wnd);
              }
            }
          );
        } else if (this._publication.conformsToDivina) {
          log.info("Publication conforms to DiViNa profile (comic)");
          this._hasGuidedNavigation = detectGuidedNavigation(this._publication);
          if (this._hasGuidedNavigation) log.info("DiViNa: Guided Navigation detected");
          // ts-toolkit has no DiViNa/image navigator; render images ourselves.
          await FlutterDivinaNavigator.create(
            container,
            this._publication,
            publicationURL,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._comicNav = nav;
              this._bridge.emitReaderStatus(ReadiumReaderStatus.ready);
            },
            (positions) => { this._positions = positions; }
          );
        } else {
          log.info("Publication conforms to WebPub profile");
          await FlutterWebPubNavigator.create(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              this._bridge.emitReaderStatus(ReadiumReaderStatus.ready);
            }
          );
        }
      }
    } catch (error) {
      log.error("Failed to open publication:", error);
      this.closePublication(error);
      throw error;
    }
  }

  public setEPUBPreferences(newPreferencesString: string) {
    if (!this._nav) {
      log.error("setEPUBPreferences: navigator is not initialized");
      throw new ReadiumWebError("Navigator is not initialized", ReadiumWebErrorCode.noPublication);
    }
    log.debug("setEPUBPreferences");
    // Track the plugin-side `disableSynchronization` preference separately from
    // the visual navigator's preferences (it is not part of the EpubNavigator
    // preference surface). Route changes through _setNarrationSyncEnabled so the
    // unified flag, TTS engine, and deferred-replay logic stay consistent.
    // Only act on an actual value transition to avoid spurious re-sync flips.
    try {
      const parsed = JSON.parse(newPreferencesString) as { disableSynchronization?: boolean };
      const prefSyncEnabled = parsed.disableSynchronization !== true;
      if (prefSyncEnabled !== this._narrationSyncEnabled) {
        this._setNarrationSyncEnabled(prefSyncEnabled, "EPUBPreferences.disableSynchronization");
      }
      // Prevent MO column breaks is a custom preference, not part of upstream navigator.
      const { preventMOColumnBreaks } = pluginPrefsFromJson(parsed);
      if (preventMOColumnBreaks !== this._preventMOColumnBreaks && this._audioNav) {
        if (preventMOColumnBreaks) {
          this._injectMOBreakCSSOnIframes();
        } else {
          this._removeMOBreakCSSOnIframes();
        }
      }
      this._preventMOColumnBreaks = preventMOColumnBreaks;
    } catch (_) {
      // Ignore parse errors — setEpubPreferencesFromString will surface them.
    }
    setEpubPreferencesFromString(newPreferencesString, this._nav);
  }

  /**
   * Enable/disable the unified narration-sync flag from the Dart side.
   *
   * When `enabled`:
   *   - Clears manual mode and resumes audio→visual synchronization.
   *   - Replays any deferred sync locator (MO or TTS) so the view catches up to
   *     the current cue.
   *   - For comics (DiViNa), also re-enables auto-pan and re-frames the current panel.
   *   - Emits `window.updateNarrationSync(true)`.
   *
   * When `disabled`:
   *   - Enters manual mode; subsequent MO/TTS sync cues are deferred.
   *   - Emits `window.updateNarrationSync(false)`.
   *
   * The DiViNa `setAutoPan` call is always forwarded so the comic panel state
   * remains authoritative in `FlutterDivinaNavigator`.
   */
  public setNarrationSyncEnabled(enabled: boolean): void {
    log.debug("setNarrationSyncEnabled", enabled);
    this._setNarrationSyncEnabled(enabled, "setNarrationSyncEnabled");
    // Forward to DiViNa auto-pan unconditionally so the comic navigator stays
    // the authority for panel-level state. The general _narrationSyncEnabled
    // flag governs MO/TTS page sync; the comic path manages its own manual override.
    this._comicNav?.setAutoPan(enabled);
    if (enabled) {
      const synced = this._resyncDivinaToCurrentAudioCue();
      log.debug(`setNarrationSyncEnabled: DiViNa re-sync ${synced ? "applied" : "had no active cue"}`);
    }
  }

  /**
   * Internal implementation of the narration-sync flag transition. Shared by
   * `setNarrationSyncEnabled` (explicit Dart call) and `setEPUBPreferences`
   * (preference transition) and `_enterManualModeIfNarrating` (user navigation).
   *
   * Does NOT forward to `_comicNav.setAutoPan` — the public `setNarrationSyncEnabled`
   * handles that so the comic navigator remains the authority for panel state.
   */
  private _setNarrationSyncEnabled(enabled: boolean, reason: string): void {
    const wasEnabled = this._narrationSyncEnabled;
    this._narrationSyncEnabled = enabled;
    log.debug(`_setNarrationSyncEnabled(${enabled}) via ${reason}`);

    // Keep TTS engine in sync with the unified flag.
    this._ttsEngine?.setSyncEnabled(enabled);

    if (!wasEnabled && enabled) {
      // Transitioning into sync: replay any deferred locator.
      if (this._lastDeferredSyncLocator) {
        const deferredLocator = this._lastDeferredSyncLocator;
        const deferredDurationMs = this._lastDeferredSyncDurationMs;
        this._lastDeferredSyncLocator = null;
        this._lastDeferredSyncDurationMs = undefined;
        // Clear dedup key so replaying the same cue still performs a visual sync.
        this._lastMediaOverlayLocatorKey = null;
        this._syncVisualToMediaOverlayLocator(deferredLocator, `MediaOverlay (resume sync via ${reason})`, deferredDurationMs);
      }
      window.updateNarrationSync?.(true);
    } else if (wasEnabled && !enabled) {
      window.updateNarrationSync?.(false);
    }
    // No emission when the value is unchanged (idempotent calls are silent).
  }

  /**
   * Enters manual mode (sync disabled) when narration is actively playing.
   * Called by the explicit navigation methods (goRight/goLeft/goForward/goBackward).
   *
   * Gesture-driven page turns inside the EPUB iframe are intentionally NOT
   * detected here — that requires cross-platform JS injection into the iframe
   * and is deferred to a later wave (matching the native limitation described in
   * the platform-interface spec).
   */
  private _enterManualModeIfNarrating(source: string): void {
    const narrationActive = !!this._audioNav || !!this._ttsEngine;
    if (!narrationActive || !this._narrationSyncEnabled) return;
    log.debug(`Manual navigation during narration (${source}): entering manual mode`);
    this._setNarrationSyncEnabled(false, source);
  }

  /**
   * Replace the entire decoration group with the provided list.
   *
   * Decorations are routed to one of three upstream subgroups based on style:
   *   - `highlight` → `<group>` (filled rectangle behind text)
   *   - `underline` → `<group>__underline` (border-bottom via injected CSS)
   *   - `spotlight` → `<group>__spotlight` (filled rectangle + body-dim CSS)
   *
   * All three subgroups are cleared on each call for replacement semantics. Spotlight
   * CSS is activated/deactivated automatically based on whether the spotlight subgroup
   * is non-empty after routing.
   *
   * @param group  Unique group identifier (opaque string passed from Dart).
   * @param decorationsJson  JSON-encoded array of ReaderDecoration objects:
   *   [{ id, locator: <Locator JSON>, style: { style: "highlight"|"underline"|"spotlight", tint: "#AARRGGBB" } }]
   *   Tints are in Dart's AARRGGBB format and are converted to CSS RRGGBBAA internally.
   */
  public applyDecorations(group: string, decorationsJson: string): void {
    if (!this._nav) {
      console.warn("applyDecorations: navigator not ready, skipping");
      return;
    }
    this._decorations.applyDecorations(this._nav, group, decorationsJson);
  }

  /**
   * Set the decoration styles used to highlight TTS utterances and word-level
   * ranges. Applied immediately to an active TTS engine; stored for use when
   * the next TTS or Media Overlay session starts.
   *
   * @param utteranceStyleJson  JSON-encoded ReaderDecorationStyle or null.
   * @param rangeStyleJson      JSON-encoded ReaderDecorationStyle or null.
   */
  public setDecorationStyle(
    utteranceStyleJson: string | null,
    rangeStyleJson: string | null
  ): void {
    this._decorations.setDecorationStyle(
      utteranceStyleJson,
      rangeStyleJson,
      (utterance, range) => this._ttsEngine?.updateDecorationStyles(utterance, range)
    );
  }

  public closePublication(error?: any) {
    log.info("closePublication", error ? `(error: ${error})` : "");

    // Suppress any post-close stragglers, then stop+destroy audio/TTS. An
    // autoplay-blocked play() keeps retrying and the position poll keeps firing;
    // destroy() alone does not reliably halt a trailing event, so without the
    // emissions gate a stale textLocator/state could leak into the next opened
    // publication (and the visual Media Overlay sync would run against a
    // torn-down frame).
    setAudioEmissionsEnabled(false);
    FlutterAudioNavigator.resetRecovery();
    this._ttsEngine?.destroy();
    this._ttsEngine = undefined;
    this._audioNav?.stop();
    this._audioNav?.destroy();
    this._audioNav = undefined;
    this._stoppedAudioLocator = undefined;

    this._hasSyncNarration = false;
    this._hasGuidedNavigation = false;
    this._syncItems = [];
    this._positions = [];
    this._publication = undefined;
    this._lastMediaOverlayLocatorKey = null;
    this._lastDeferredSyncLocator = null;
    this._lastDeferredSyncDurationMs = undefined;
    this._narrationSyncEnabled = true;
    this._isComicBook = false;
    this._decorations.reset();

    // Detach the visual navigator reference synchronously so any late
    // media-overlay sync callback (which guards on `this._nav`) becomes a no-op
    // even while the async destroy() below is still settling.
    const nav: VisualNavigatorLike | undefined = this._nav ?? this._comicNav;
    this._nav = undefined;
    this._comicNav = undefined;

    const container = document.getElementById("container");
    if (container) {
      container.innerHTML = ""; // Clear the container
    }
    // Emit status synchronously so Dart receives it before any async navigator cleanup.
    // Do NOT delete the window callbacks here — the Dart side re-registers them before each
    // openPublication call, and deleting them asynchronously races with the new registration.
    this._bridge.emitReaderStatus(error ? ReadiumReaderStatus.error : ReadiumReaderStatus.closed);

    const navDestroy = nav?.destroy();
    if (navDestroy) {
      navDestroy
        .catch((err) => {
          log.error("Error destroying navigator:", err);
        })
        .finally(() => {
          const c = document.getElementById("container");
          if (c) c.innerHTML = "";
        });
    }
  }

  /**
   * Seeks the AudioNavigator to `audioLocator` and (optionally) resumes playback,
   * restarting upstream position polling. Thin wrapper over the shared
   * {@link seekAudioAndResume} helper that no-ops when no navigator is active.
   */
  private _seekAudioAndResume(
    audioLocator: Locator,
    resumePlaying: boolean
  ): Promise<void> {
    const nav = this._audioNav;
    if (!nav) return Promise.resolve();
    return seekAudioAndResume(nav, audioLocator, resumePlaying);
  }

  public play(locatorJson?: string): void {
    log.debug("play", locatorJson ? "(with locator)" : "");
    if (this._ttsEngine) {
      const locator = locatorJson
        ? Locator.deserialize(JSON.parse(locatorJson)) ?? undefined
        : undefined;
      this._ttsEngine.play(locator);
      return;
    }
    if (!this._audioNav) return;

    // Retrying after a terminal streaming failure: the failed navigator was
    // already stopped by the recovery controller and is never reusable (no
    // re-prepare API), so clear the latch and rebuild fresh at the last
    // locator — mirrors iOS/Android's play()-after-failure contract.
    if (FlutterAudioNavigator.isTerminallyFailed()) {
      log.info("play: retrying after terminal audio streaming failure");
      FlutterAudioNavigator.retryAfterFailure();
      const resumeLocator = locatorJson
        ? Locator.deserialize(JSON.parse(locatorJson)) ?? this._audioNav.currentLocator
        : this._audioNav.currentLocator;
      void FlutterAudioNavigator.create(
        this._publication as ReadiumPublication,
        resumeLocator,
        this._activeAudioPreferencesJson,
        (nav) => {
          this._audioNav = nav;
          nav.play();
        },
        undefined,
        undefined,
        undefined,
        this._bridge
      );
      return;
    }

    if (locatorJson) {
      let locator = Locator.deserialize(JSON.parse(locatorJson));
      if (locator) {
        // MediaOverlay: map text locator → audio locator before seeking.
        if (this._syncItems.length > 0) {
          locator = textLocatorToAudioLocator(this._syncItems, locator) ?? locator;
        }
        this._seekAudioAndResume(locator, true);
        return;
      }
    }
    this._audioNav.play();
  }

  public pause(): void {
    log.debug("pause");
    if (this._ttsEngine) { this._ttsEngine.pause(); return; }
    this._audioNav?.pause();
  }

  public resume(): void {
    log.debug("resume");
    if (this._ttsEngine) { this._ttsEngine.resume(); return; }
    this._audioNav?.play();
  }

  public stop(): void {
    log.debug("stop");
    if (this._ttsEngine) {
      const ttsEngine = this._ttsEngine;
      this._ttsEngine = undefined;
      ttsEngine.stop();
      ttsEngine.destroy();
      return;
    }
    const audioNav = this._audioNav;
    if (!audioNav) return;

    // Keep the plugin-level stop contract aligned with native: stop tears down
    // the active timebased navigator. Clients must call audioEnable() again.
    setAudioEmissionsEnabled(false);
    FlutterAudioNavigator.resetRecovery();
    this._stoppedAudioLocator = audioNav.currentLocator;
    log.info(
      "stop: destroying audio navigator",
      this._hasSyncNarration || this._hasGuidedNavigation
        ? "(Media Overlay / Guided Navigation)"
        : "(plain audiobook)"
    );
    this._audioNav = undefined;
    audioNav.stop();
    audioNav.destroy();
    window.updateTimebasedPlayerState?.(
      JSON.stringify({
        state: "none",
        currentOffset: null,
        currentDuration: null,
        currentLocator: null,
      })
    );

    // Clear Media Overlay / Guided Navigation state when narration stops.
    if (this._hasSyncNarration || this._hasGuidedNavigation) {
      this._syncItems = [];
      this._lastMediaOverlayLocatorKey = null;
      if (this._nav) {
        this.applyDecorations("media_overlay_utterance", "[]");
        this._removeMOBreakCSSOnIframes();
      }
    }
  }

  /** Inject MO column-break CSS into all loaded EPUB iframes directly via the DOM. */
  private _injectMOBreakCSSOnIframes(): void {
    if (!this._nav) return;
    for (const wnd of navIframeWindows(this._nav)) {
      injectMOBreakCSSIntoWindow(wnd);
    }
  }

  /** Remove MO column-break CSS from all loaded EPUB iframes directly via the DOM. */
  private _removeMOBreakCSSOnIframes(): void {
    if (!this._nav) return;
    for (const wnd of navIframeWindows(this._nav)) {
      wnd.document.getElementById("flutter-readium-mo-breaks")?.remove();
    }
  }

  public next(): void {
    log.debug("next");
    if (this._ttsEngine) { this._ttsEngine.next(); return; }
    this._audioNav?.goForward(false, () => {});
  }

  public previous(): void {
    log.debug("previous");
    if (this._ttsEngine) { this._ttsEngine.previous(); return; }
    this._audioNav?.goBackward(false, () => {});
  }

  /** Relative seek by seconds. Applies to AudioNavigator (audiobook / Media Overlay). */
  public seekBy(seconds: number): void {
    log.debug("seekBy", seconds);
    this._audioNav?.jump(seconds);
  }

  /**
   * Navigate to an absolute progression (0.0–1.0) within the current publication.
   * - AudioNavigator (audiobook / Media Overlay): seeks to progression × duration.
   * - EpubNavigator: finds the closest position locator and navigates to it.
   */
  public goToProgression(progression: number): boolean {
    log.debug("goToProgression", progression);
    if (progression < 0 || progression > 1) {
      log.warn("goToProgression: progression out of range [0, 1]:", progression);
      return false;
    }

    if (this._audioNav) {
      const duration = this._audioNav.duration;
      if (duration <= 0) {
        log.warn("goToProgression: audio duration not available");
        return false;
      }
      this._audioNav.seek(progression * duration);
      return true;
    }

    if (this._visualNav && this._positions.length > 0) {
      const index = Math.min(
        Math.floor(progression * this._positions.length),
        this._positions.length - 1
      );
      const locator = this._positions[index];
      this._visualNav.go(locator, true, (ok) => {
        if (!ok) {
          log.warn("goToProgression: navigation failed for position", index);
        }
      });
      return true;
    }

    log.warn("goToProgression: no active navigator or positions available");
    return false;
  }

  // ---------------------------------------------------------------------------
  // TTS API
  // ---------------------------------------------------------------------------

  /**
   * Initialises (or re-initialises) the TTS engine and starts playback.
   * Requires an EPUB or WebPub visual navigator to already be active.
   */
  public async ttsEnable(prefsJson: string, fromLocatorJson?: string): Promise<void> {
    log.info("ttsEnable");
    if (!this._nav || !this._publication) {
      log.warn("ttsEnable: no visual navigator active");
      return;
    }
    // Destroy any previous TTS session.
    this._ttsEngine?.destroy();
    const prefs = ttsPreferencesFromJson(JSON.parse(prefsJson));
    this._ttsEngine = new FlutterTTSNavigator(
      this._nav,
      this._publication,
      prefs,
      this._narrationSyncEnabled,
      this._decorations.utteranceStyle,
      this._decorations.rangeStyle,
      (group, decorationsJson) => this.applyDecorations(group, decorationsJson)
    );
    const fromLocator = fromLocatorJson
      ? Locator.deserialize(JSON.parse(fromLocatorJson)) ?? undefined
      : undefined;
    await this._ttsEngine.play(fromLocator);
  }

  /** Returns a JSON string containing available browser TTS voices. */
  public async ttsGetAvailableVoices(): Promise<string> {
    return FlutterTTSNavigator.getAvailableVoices();
  }

  /**
   * Sets the active TTS voice.
   * @param identifier  Voice URI (from ttsGetAvailableVoices).
   * @param lang        Optional BCP-47 language code for per-language mapping.
   */
  public ttsSetVoice(identifier: string, lang?: string): void {
    this._ttsEngine?.setVoice(identifier, lang);
  }

  /** Applies updated TTS preferences (rate, pitch, voice). */
  public ttsSetPreferences(prefsJson: string): void {
    if (!this._ttsEngine) return;
    const prefs = ttsPreferencesFromJson(JSON.parse(prefsJson));
    this._ttsEngine.applyPreferences(prefs);
  }

  // ---------------------------------------------------------------------------
  // Audio / Media Overlay API
  // ---------------------------------------------------------------------------

  /**
   * Calls `window.gotoComicFrame(fragmentId, durationMs)` on the given iframe
   * window, retrying via requestAnimationFrame until `window.comicBookPage` is
   * available (it is initialised asynchronously inside a setTimeout + rAF in the
   * helper bundle).
   */
  private _callGotoComicFrame(
    wnd: Window,
    fragmentId: string,
    durationMs: number,
    retriesLeft = 20
  ): void {
    type ComicWindow = Window & {
      comicBookPage?: unknown;
      gotoComicFrame?: (id: string, duration: number) => void;
    };
    const cw = wnd as ComicWindow;
    if (cw.comicBookPage) {
      log.debug(
        `[comic] gotoComicFrame("${fragmentId}", ${durationMs}ms)`
      );
      cw.gotoComicFrame?.(fragmentId, durationMs);
      return;
    }
    if (retriesLeft <= 0) {
      log.warn(
        `[comic] comicBookPage never became available; giving up for fragment "${fragmentId}"`
      );
      return;
    }
    log.debug(
      `[comic] comicBookPage not ready yet, retrying (${retriesLeft} left)…`
    );
    wnd.requestAnimationFrame(() =>
      this._callGotoComicFrame(wnd, fragmentId, durationMs, retriesLeft - 1)
    );
  }

  /**
   * Synchronises the DiViNa image navigator to the active Guided Navigation cue:
   * turns to the cue's page (only when it changes) and pans/zooms to the cue's
   * panel region (`xywh`, every cue). The pan is gated inside the navigator
   * (auto-pan toggle + manual-override). A cue with no region re-frames the
   * whole page.
   */
  private _syncDivinaToMediaOverlayLocator(textLocator: Locator): void {
    const nav = this._comicNav;
    if (!nav) return;
    // Turn the page only when the href changes (cues on one page share it).
    if (textLocator.href !== this._lastMediaOverlayLocatorKey) {
      this._lastMediaOverlayLocatorKey = textLocator.href;
      log.debug(`GuidedNavigation(DiViNa): sync to page "${textLocator.href}"`);
      nav.go(textLocator, false, (ok) => {
        if (!ok) {
          log.warn(`GuidedNavigation(DiViNa): failed to navigate to "${textLocator.href}"`);
        }
      });
    }
    // Pan to the panel on every cue (region rides on the locator's otherLocations).
    const region = (textLocator.locations?.otherLocations?.get("comicRegion") ??
      null) as ComicRegion | null;
    nav.panToRegion(region);
  }

  /**
   * Re-sync the DiViNa view to the currently active audio cue (page + panel).
    * Used by the explicit re-sync action; normal playback should rely on fresh
    * AudioNavigator cue emissions so listener/polling failures remain visible.
   */
  private _resyncDivinaToCurrentAudioCue(): boolean {
    if (!this._comicNav || !this._audioNav || this._syncItems.length === 0) return false;
    const audioLocator = this._audioNav.currentLocator;
    const resolvedTime = getTime(audioLocator.locations) ?? this._audioNav.currentTime;
    const item = findItemByAudioTime(this._syncItems, audioLocator.href, resolvedTime);
    if (!item) return false;
    // Force page sync even when the cue key equals the last emitted one.
    this._lastMediaOverlayLocatorKey = null;
    this._syncDivinaToMediaOverlayLocator(textLocatorForItem(item));
    return true;
  }

  /**
   * Synchronises the visual EPUB navigator to the active Media Overlay / Guided
   * Navigation cue.
   */
  private _syncVisualToMediaOverlayLocator(
    textLocator: Locator,
    sourceLabel: string,
    durationMs: number | undefined
  ): void {
    const nav = this._nav;
    if (!nav) return;
    // Skip redundant work when the same cue is still active.
    const key =
      textLocator.href + (textLocator.locations?.fragments?.[0] ?? "");
    if (key === this._lastMediaOverlayLocatorKey) return;
    this._lastMediaOverlayLocatorKey = key;

    const fragmentId = textLocator.locations?.fragments?.[0] ?? "";
    log.debug(
      `${sourceLabel}: sync locator href="${textLocator.href}" fragment="${fragmentId}" durationMs=${durationMs ?? "undefined"}`
    );

    // --- Comic-book path ---
    if (!this._isComicBook) {
      const iframes = navIframeWindows(nav);
      for (const wnd of iframes) {
        const isComic = (
          wnd as Window & { isNotaComicBook?: () => boolean }
        ).isNotaComicBook;
        if (typeof isComic === "function" && isComic()) {
          log.info(`${sourceLabel}: comic-book publication detected; skipping nav.go() for all cues`);
          this._isComicBook = true;
          break;
        }
      }
    }

    if (this._isComicBook) {
      const iframes = navIframeWindows(nav);

      const targetWnd = iframes.find((w) => {
        try {
          return (
            w.location?.href?.includes(textLocator.href) ||
            w.document?.URL?.includes(textLocator.href)
          );
        } catch {
          return false;
        }
      });

      const frameDuration = durationMs ?? 3000;

      const doGotoFrame = (wnd: Window) =>
        this._callGotoComicFrame(wnd, fragmentId, frameDuration);

      if (!targetWnd) {
        log.debug(
          `${sourceLabel}: [comic] cross-resource nav to "${textLocator.href}", calling nav.go() then gotoComicFrame`
        );
        nav.go(textLocator, false, (ok) => {
          if (!ok) {
            log.warn(
              `${sourceLabel}: [comic] nav.go() failed for ${textLocator.href}`
            );
            return;
          }
          const newIframes = navIframeWindows(nav);
          const newWnd =
            newIframes.find((w) => {
              try {
                return (
                  w.location?.href?.includes(textLocator.href) ||
                  w.document?.URL?.includes(textLocator.href)
                );
              } catch {
                return false;
              }
            }) ?? newIframes[0];
          if (newWnd) doGotoFrame(newWnd);
          else
            log.warn(
              `${sourceLabel}: [comic] no iframe found after nav.go() for "${textLocator.href}"`
            );
        });
      } else {
        log.debug(
          `${sourceLabel}: [comic] same-resource frame, calling gotoComicFrame directly`
        );
        doGotoFrame(targetWnd);
      }
      return;
    }

    // --- Normal (non-comic) path ---
    const applyUtteranceDecoration = () => {
      if (!this._decorations.utteranceStyle || !this._nav) return;
      try {
        const decoration = [
          {
            id: textLocator.href,
            locator: textLocator.serialize(),
            style: this._decorations.utteranceStyle,
          },
        ];
        this.applyDecorations(
          "media_overlay_utterance",
          JSON.stringify(decoration)
        );
      } catch (e) {
        log.warn(`${sourceLabel}: failed to apply decoration:`, e);
      }
    };

    // Track the most recent cue unconditionally so a Re-sync
    // (setNarrationSyncEnabled(true)) can snap to the CURRENT cue immediately, even
    // when triggered mid-cue. Previously this was cleared on the enabled path, so a
    // mid-cue Re-sync had no locator to replay and only corrected on the next cue.
    this._lastDeferredSyncLocator = textLocator;
    this._lastDeferredSyncDurationMs = durationMs;

    if (!this._narrationSyncEnabled) {
      applyUtteranceDecoration();
      return;
    }

    nav.go(textLocator, false, (ok) => {
      if (!ok) {
        log.warn(
          `${sourceLabel}: visual navigation failed for ${textLocator.href}`
        );
      }
      applyUtteranceDecoration();
    });
  }

  /**
   * Resolves a publication resource identified by its publication-relative
   * href (e.g. `images/cover.png`) to its absolute served URL.
   */
  public async getResourceUrl(href: string): Promise<string> {
    const pub = this._publication;
    if (!pub) {
      throw new ReadiumWebError("getResourceUrl: no publication is open", ReadiumWebErrorCode.noPublication);
    }
    const link = findLinkByHref(pub.allLinks, href);
    if (!link) {
      // A syntactically valid href with no matching manifest entry is a runtime
      // not-found condition, not caller misuse - mirrors iOS/Android, which both
      // classify the equivalent case as ResourceReadError(reason: "notFound").
      throw new ReadiumWebError(
        `getResourceUrl: no resource found for href: ${href}`,
        ReadiumWebErrorCode.resourceReadError,
        { reason: ResourceReadErrorReason.notFound, href }
      );
    }
    const url = link.toURL(pub.baseURL);
    if (!url) {
      throw new ReadiumWebError(
        `getResourceUrl: could not resolve URL for href: ${href}`,
        ReadiumWebErrorCode.resourceReadError,
        { reason: ResourceReadErrorReason.urlResolution, href }
      );
    }
    return url;
  }

  /**
   * Enables audio playback.
   *  - Pure audiobook: AudioNavigator already initialized in openPublication — just play.
   *  - Media Overlay EPUB: lazy-initialize MediaOverlayNavigator, then play.
   */
  public async audioEnable(prefsJson: string, fromLocatorJson?: string): Promise<void> {
    log.info("audioEnable");
    const preferencesJsonString =
      !prefsJson || prefsJson === "null" ? "{}" : prefsJson;
    this._activeAudioPreferencesJson = preferencesJsonString;
    const resolvedFromLocator: Locator | undefined = fromLocatorJson
      ? Locator.deserialize(JSON.parse(fromLocatorJson)) ?? undefined
      : this._visualNav?.currentLocator;

    if (this._audioNav) {
      if (resolvedFromLocator) {
        let locator = resolvedFromLocator;
        if (this._syncItems.length > 0) {
          locator = textLocatorToAudioLocator(this._syncItems, locator) ?? locator;
        }
        this._seekAudioAndResume(locator, true);
        return;
      }
      // Use the safe restart path so polling resumes even when we're already at
      // the current cue/position (upstream same-position seek quirk).
      this._seekAudioAndResume(this._audioNav.currentLocator, true);
      return;
    }

    if (this._hasGuidedNavigation && this._publication) {
      const fromLocator = resolvedFromLocator;
      this._lastMediaOverlayLocatorKey = null;
      if (this._comicNav) {
        // DiViNa: page-level sync only — no iframe, no decoration.
        await initializeGuidedNavigationNavigator(
          this._publication,
          fromLocator,
          preferencesJsonString,
          (nav, items) => { this._audioNav = nav; this._syncItems = items; },
          (textLocator, _durationMs) => this._syncDivinaToMediaOverlayLocator(textLocator)
        );
      } else {
        // EPUB: full sync with visual decoration.
        await initializeGuidedNavigationNavigator(
          this._publication,
          fromLocator,
          preferencesJsonString,
          (nav, items) => { this._audioNav = nav; this._syncItems = items; },
          (textLocator, durationMs) => this._syncVisualToMediaOverlayLocator(textLocator, "GuidedNavigation", durationMs)
        );
      }
      const nav = this._audioNav as AudioNavigator | undefined;
      if (nav) {
        const mappedStart = fromLocator
          ? textLocatorToAudioLocator(this._syncItems, fromLocator)
          : undefined;
        await this._seekAudioAndResume(mappedStart ?? nav.currentLocator, true);
        if (!this._comicNav && this._preventMOColumnBreaks) this._injectMOBreakCSSOnIframes();
      }
      return;
    }

    if (this._hasSyncNarration && this._publication) {
      const fromLocator = resolvedFromLocator;
      this._lastMediaOverlayLocatorKey = null;
      await initializeMediaOverlayNavigator(
        this._publication,
        fromLocator,
        prefsJson,
        (nav, items) => { this._audioNav = nav; this._syncItems = items; },
        (textLocator, durationMs) => this._syncVisualToMediaOverlayLocator(textLocator, "MediaOverlay", durationMs)
      );
      const nav = this._audioNav as AudioNavigator | undefined;
      if (nav) {
        const mappedStart = fromLocator
          ? textLocatorToAudioLocator(this._syncItems, fromLocator)
          : undefined;
        await this._seekAudioAndResume(mappedStart ?? nav.currentLocator, true);
        if (this._preventMOColumnBreaks) this._injectMOBreakCSSOnIframes();
      }
      return;
    }

    if (this._publication?.conformsToAudiobook) {
      const fromLocator = resolvedFromLocator ?? this._stoppedAudioLocator;
      log.info("audioEnable: recreating plain audiobook navigator");
      await FlutterAudioNavigator.create(
        this._publication,
        fromLocator,
        preferencesJsonString,
        (nav) => { this._audioNav = nav; },
        undefined,
        undefined,
        undefined,
        this._bridge
      );
      const nav = this._audioNav as AudioNavigator | undefined;
      if (nav) {
        this._stoppedAudioLocator = undefined;
        await this._seekAudioAndResume(fromLocator ?? nav.currentLocator, true);
      }
      return;
    }

    log.warn("audioEnable: no audiobook or Media Overlay content detected");
  }

  public setAudioPreferences(preferencesJson: string): void {
    log.debug("setAudioPreferences");
    if (!this._audioNav) return;
    const preferencesJsonString =
      !preferencesJson || preferencesJson === "null" ? "{}" : preferencesJson;
    this._activeAudioPreferencesJson = preferencesJsonString;
    applyAudioPreferences(this._audioNav, preferencesJsonString);
  }
}

declare global {
  namespace globalThis {
    var ReadiumReader: typeof _ReadiumReader;
  }
}

globalThis.ReadiumReader = _ReadiumReader;

// Test-only export. Lets unit tests construct the reader and assert teardown
// behaviour (e.g. closePublication stops/destroys navigators) without going
// through the global the webview bootstrap relies on.
export const __testing__ = { ReadiumReader: _ReadiumReader };
