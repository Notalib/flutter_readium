import "./style.css";

import { AudioNavigator, AudioPreferences, EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { Locator, Resource } from "@readium/shared";
import { Link } from "@readium/shared";
import { Layout, Width, Decoration } from "@readium/navigator-html-injectables";

// Helpers and extensions
import { createLogger, LogLevel, setLogLevel } from "./logger";
import {
  fetchManifest,
  setPreferencesFromString,
  sendDecorate,
  navIframeWindows,
  registerPendingDecorationGroup,
  setSpotlightGroupOnIframes,
  UNDERLINE_GROUP_SUFFIX,
  SPOTLIGHT_GROUP_SUFFIX,
  RULER_GROUP_SUFFIX,
  dartColorToCss,
} from "./helpers";
import { ReadiumReaderStatus } from "./enums";
import { ReadiumPublication } from "./extensions/ReadiumPublication";
import { initializeEpubNavigatorAndPeripherals } from "./Epub/epubNavigator";
import { setEpubPreferencesFromString } from "./Epub/epubPreferences";
import { initializeWebPubNavigatorAndPeripherals } from "./WebPub/webpubNavigator";
import { initializeAudioNavigator, seekAudioAndResume, setAudioEmissionsEnabled } from "./Audio/audioNavigator";
import { SyncNarrationItem, detectSyncNarration, textLocatorToAudioLocator } from "./Audio/syncNarration";
import { detectGuidedNavigation } from "./Audio/guidedNavigation";
import { initializeMediaOverlayNavigator, initializeGuidedNavigationNavigator } from "./Audio/mediaOverlayNavigator";
import { WebTTSEngine } from "./TTS/ttsNavigator";
import { ttsPreferencesFromJson } from "./TTS/ttsPreferences";

const log = createLogger("Reader");

/** Finds a link by href, falling back to pathname comparison for relative vs. absolute mismatches. */
function findLinkByHref(
  items: Link[] | undefined,
  href: string
): Link | undefined {
  if (!items || items.length === 0) return undefined;
  const exact = items.find((l) => l.href === href);
  if (exact) return exact;
  try {
    const hrefPath = new URL(href, "http://localhost").pathname;
    return items.find((l) => {
      try {
        return new URL(l.href, "http://localhost").pathname === hrefPath;
      } catch {
        return false;
      }
    });
  } catch {
    return undefined;
  }
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

  private _publication: ReadiumPublication | undefined;
  private _nav: EpubNavigator | WebPubNavigator | undefined;
  private _audioNav: AudioNavigator | undefined;
  private _ttsEngine: WebTTSEngine | undefined;
  /** Position list for EPUB publications (used by goToProgression). */
  private _positions: Locator[] = [];
  /** True when the current EPUB publication has embedded Sync Narration JSON. */
  private _hasSyncNarration = false;
  private _hasGuidedNavigation = false;
  /** Parsed sync-narration items for the current MediaOverlay publication. Empty for plain audiobooks. */
  private _syncItems: SyncNarrationItem[] = [];
  /**
   * Latest value of `EPUBPreferences.disableSynchronization` from the Dart side.
   * Held here because it is plugin-side state, not part of the navigator's
   * preference surface. Passed to the TTS engine on enable and on every change.
   */
  private _disableSynchronization = false;

  // Maps group name → set of decoration IDs currently applied, used for group-replacement semantics.
  private _decorationsByGroup: Map<string, Set<string>> = new Map();

  // Stored decoration styles for TTS/media-overlay use.
  // Defaults match iOS/Android: yellow highlight for utterance, black underline for range.
  // Stored in Dart #AARRGGBB format so dartColorToCss() converts them correctly when
  // they flow through applyDecorations(). Overridden by setDecorationStyle() from Dart.
  private _utteranceStyle: object | null = { style: "highlight", tint: "#ffffff00" };  // Dart AARRGGBB: A=ff R=ff G=ff B=00 → opaque yellow
  private _rangeStyle: object | null = { style: "underline", tint: "#ff000000" };      // Dart AARRGGBB: A=ff R=00 G=00 B=00 → opaque black

  // Deduplication key for Media Overlay decoration: "<href><fragment>".
  // Avoids redundant applyDecorations calls when the poll fires during the same cue.
  private _lastMediaOverlayLocatorKey: string | null = null;

  // Set to true once we've confirmed that any iframe in the current publication
  // is a comic-book page. Used to skip nav.go() for all subsequent cues.
  private _isComicBook = false;

  public get isNavigatorReady(): boolean {
    return !!this._nav;
  }

  private static _publications: Map<string, ReadiumPublication> = new Map<
    string,
    ReadiumPublication
  >();

  public async getPublication(publicationURL: string) {
    log.info("getPublication", publicationURL);
    try {
      const { manifest, fetcher } = await fetchManifest(publicationURL);
      this._publication = new ReadiumPublication({ manifest, fetcher });

      let pubId = this._publication.metadata.identifier ?? "unidentified";
      _ReadiumReader._publications.set(pubId, this._publication);

      log.info("Publication fetched:", pubId);
      return JSON.stringify(manifest.serialize());
    } catch (error) {
      log.error("Failed to get publication:", error);
      // Surface the failure on the onErrorEvent stream. Most open failures (bad
      // URL, unreachable host, non-JSON response) happen here in the manifest
      // fetch, before openPublication runs — so without this, onErrorEvent would
      // never see the most common error case.
      const errorMessage = error instanceof Error ? error.message : String(error);
      window.onErrorCallback?.(JSON.stringify({ message: "Failed to get publication: " + errorMessage }));
      throw new Error("Error getting publication: " + error);
    }
  }

  public goRight() {
    log.debug("goRight");
    this._nav?.goRight(true, () => {});
  }

  public goLeft() {
    log.debug("goLeft");
    this._nav?.goLeft(true, () => {});
  }

  /**
   * Progression-aware navigation. `goForward` / `goBackward` are RTL-aware on
   * the upstream navigator (unlike `goRight` / `goLeft`, which are purely
   * visual). The Dart-side `goForward`/`goBackward` API maps to these.
   */
  public goForward() {
    log.debug("goForward");
    this._nav?.goForward(true, () => {});
  }

  public goBackward() {
    log.debug("goBackward");
    this._nav?.goBackward(true, () => {});
  }

  public async goTo(locatorJson: string): Promise<void> {
    log.info("goTo", locatorJson);

    const locator = Locator.deserialize(JSON.parse(locatorJson));
    if (!locator) {
      log.error("goTo: failed to parse locator JSON");
      throw new Error("Failed to parse locator JSON");
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
      const visualPub = this._nav?.publication;
      const visualLinks = [
        ...(visualPub?.readingOrder?.items ?? []),
        ...(visualPub?.resources?.items ?? []),
      ];
      const visualLink = findLinkByHref(visualLinks, locator.href);
      if (visualLink) {
        this._nav?.goLink(visualLink, true, (ok) => {
          if (!ok) log.warn("goTo: MediaOverlay — visual navigation failed for", locator.href);
        });
      }
      return;
    }

    // Pure audiobook (no sync narration): build an audio locator from the
    // incoming locator, preserving any t= time fragment it already carries.
    if (this._audioNav) {
      const pub = this._publication;
      const allLinks = [
        ...(pub?.readingOrder?.items ?? []),
        ...(pub?.resources?.items ?? []),
      ];
      const link = findLinkByHref(allLinks, locator.href);
      if (!link) {
        log.error("goTo: audio link not found:", locator.href);
        throw new Error("Audio link not found " + locator.href);
      }
      // Preserve t= fragment from the incoming locator when present.
      const audioLocator = new Locator({
        href: link.href,
        type: link.type ?? "audio/mpeg",
        locations: locator.locations,
      });
      const wasPlaying = this._audioNav.isPlaying;
      await this._seekAudioAndResume(audioLocator, wasPlaying);
      return;
    }

    // EPUB / WebPub with no audio active: visual-only navigation.
    const pub = this._nav?.publication;
    const allLinks = [
      ...(pub?.readingOrder?.items ?? []),
      ...(pub?.resources?.items ?? []),
    ];
    const link = findLinkByHref(allLinks, locator.href);
    if (!link) {
      log.error("goTo: link not found:", locator.href);
      throw new Error("Link not found " + locator.href);
    }
    this._nav?.goLink(link, true, (ok) => {
      if (!ok) {
        log.error("goTo: failed to navigate to link:", locator.href);
        throw new Error("Failed to navigate to link " + locator.href);
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
    window.updateReaderStatus?.(ReadiumReaderStatus.loading);

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

    try {
      // TODO: match native
      this._publication = _ReadiumReader._publications.get(pubId);
      if (!this._publication) {
        const { manifest, fetcher } = await fetchManifest(publicationURL);
        this._publication = new ReadiumPublication({ manifest, fetcher });
        _ReadiumReader._publications.set(pubId, this._publication);
      }

      if (this._publication.conformsToAudiobook) {
        log.info("Publication conforms to Audiobook profile");
        // AudioNavigator doesn't need a DOM container — it drives <audio> elements directly.
        await initializeAudioNavigator(
          this._publication,
          initialPosition,
          preferencesJsonString,
          (nav) => {
            this._audioNav = nav;
            window.updateReaderStatus?.(ReadiumReaderStatus.ready);
          }
        );
      } else {
        // EPUB and WebPub navigators render into a DOM container.
        const container: HTMLElement | null =
          document.body.querySelector("#container");
        if (!container) {
          log.error("Container element #container not found in DOM");
          window.updateReaderStatus?.(ReadiumReaderStatus.error);
          throw new Error("Container element not found");
        }
        if (this._publication.conformsToEpub) {
          log.info("Publication conforms to EPUB profile");
          // Detect sync narration before opening the navigator (async fetch-free check).
          this._hasSyncNarration = detectSyncNarration(this._publication);
          if (this._hasSyncNarration) log.info("Sync Narration detected");
          this._hasGuidedNavigation = detectGuidedNavigation(this._publication);
          if (this._hasGuidedNavigation) log.info("Guided Navigation detected");
          await initializeEpubNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              window.updateReaderStatus?.(ReadiumReaderStatus.ready);
            },
            (positions) => { this._positions = positions; }
          );
        } else {
          log.info("Publication conforms to WebPub profile");
          await initializeWebPubNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              window.updateReaderStatus?.(ReadiumReaderStatus.ready);
            }
          );
        }
      }
    } catch (error) {
      log.error("Failed to open publication:", error);
      const errorMessage = error instanceof Error ? error.message : String(error);
      window.onErrorCallback?.(JSON.stringify({ message: "Failed to open publication: " + errorMessage }));
      this.closePublication(error);
      throw new Error("Error opening publication: " + error);
    }
  }

  public setEPUBPreferences(newPreferencesString: string) {
    if (!this._nav) {
      log.error("setEPUBPreferences: navigator is not initialized");
      throw new Error("Navigator is not initialized");
    }
    log.debug("setEPUBPreferences");
    // Track the plugin-side `disableSynchronization` flag separately from the
    // navigator's preferences (the web navigator doesn't expose this toggle).
    try {
      const parsed = JSON.parse(newPreferencesString) as { disableSynchronization?: boolean };
      this._disableSynchronization = parsed.disableSynchronization === true;
      // TODO: Also notify MediaOverlayNavigator or generalize the callback?
      this._ttsEngine?.setSyncEnabled(!this._disableSynchronization);
    } catch (_) {
      // Ignore parse errors — setEpubPreferencesFromString will surface them.
    }
    setEpubPreferencesFromString(newPreferencesString, this._nav);
  }

  /**
   * Replace the entire decoration group with the provided list.
   *
   * Decorations are routed to one of four upstream subgroups based on style:
   *   - `highlight` → `<group>` (filled rectangle behind text)
   *   - `underline` → `<group>__underline` (border-bottom via injected CSS)
   *   - `spotlight` → `<group>__spotlight` (filled rectangle + body-dim CSS)
   *   - `ruler`     → `<group>__ruler` (full-viewport-width stripe per text line)
   *
   * All four subgroups are cleared on each call for replacement semantics. Spotlight
   * CSS is activated/deactivated automatically based on whether the spotlight subgroup
   * is non-empty after routing.
   *
   * @param group  Unique group identifier (opaque string passed from Dart).
   * @param decorationsJson  JSON-encoded array of ReaderDecoration objects:
   *   [{ id, locator: <Locator JSON>, style: { style: "highlight"|"underline"|"spotlight"|"ruler", tint: "#AARRGGBB" } }]
   *   Tints are in Dart's AARRGGBB format and are converted to CSS RRGGBBAA internally.
   */
  public applyDecorations(group: string, decorationsJson: string): void {
    if (!this._nav) {
      console.warn("applyDecorations: navigator not ready, skipping");
      return;
    }

    const underlineGroup = group + UNDERLINE_GROUP_SUFFIX;
    const spotlightGroup = group + SPOTLIGHT_GROUP_SUFFIX;
    const rulerGroup = group + RULER_GROUP_SUFFIX;

    // Clear all subgroups for replacement semantics.
    for (const grp of [group, underlineGroup, spotlightGroup, rulerGroup]) {
      sendDecorate(this._nav, grp, "clear", undefined);
      this._decorationsByGroup.set(grp, new Set());
    }

    const decorationsRaw: Array<{
      id: string;
      locator: object;
      style: { style: string; tint: string };
    }> = JSON.parse(decorationsJson);

    // Convert tints from Dart's AARRGGBB to CSS RRGGBBAA at the entry point so
    // all downstream paths (highlight fill, underline CSS, spotlight) see CSS colors.
    for (const item of decorationsRaw) {
      item.style.tint = dartColorToCss(item.style.tint);
    }

    const iframes = navIframeWindows(this._nav);

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
      const targetGroup = this._subgroupFor(group, raw.style.style);
      const isRuler = raw.style.style === "ruler";
      const decoration: Decoration = {
        id: raw.id,
        locator: Locator.deserialize(raw.locator)!,
        style: {
          tint: raw.style.tint,
          layout: isRuler ? Layout.Boxes : Layout.Bounds,
          width: isRuler ? Width.Viewport : Width.Wrap,
        },
      };
      sendDecorate(this._nav, targetGroup, "add", decoration);
      this._decorationsByGroup.get(targetGroup)!.add(raw.id);
    }

    // Spotlight is driven by decoration presence: activate when the spotlight
    // subgroup is non-empty, deactivate when empty.
    const hasSpotlight = (this._decorationsByGroup.get(spotlightGroup)?.size ?? 0) > 0;
    setSpotlightGroupOnIframes(iframes, hasSpotlight ? spotlightGroup : null);
  }

  private _subgroupFor(group: string, style: string): string {
    switch (style) {
      case "underline": return group + UNDERLINE_GROUP_SUFFIX;
      case "spotlight": return group + SPOTLIGHT_GROUP_SUFFIX;
      case "ruler":     return group + RULER_GROUP_SUFFIX;
      default:          return group; // "highlight" and anything unknown
    }
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
    this._utteranceStyle = utteranceStyleJson ? JSON.parse(utteranceStyleJson) : null;
    this._rangeStyle = rangeStyleJson ? JSON.parse(rangeStyleJson) : null;
    this._ttsEngine?.updateDecorationStyles(this._utteranceStyle, this._rangeStyle);
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
    this._ttsEngine?.destroy();
    this._ttsEngine = undefined;
    this._audioNav?.stop();
    this._audioNav?.destroy();
    this._audioNav = undefined;

    this._hasSyncNarration = false;
    this._hasGuidedNavigation = false;
    this._syncItems = [];
    this._positions = [];
    this._publication = undefined;
    this._lastMediaOverlayLocatorKey = null;
    this._isComicBook = false;
    this._decorationsByGroup.clear();

    // Detach the visual navigator reference synchronously so any late
    // media-overlay sync callback (which guards on `this._nav`) becomes a no-op
    // even while the async destroy() below is still settling.
    const nav = this._nav;
    this._nav = undefined;

    const container = document.getElementById("container");
    if (container) {
      container.innerHTML = ""; // Clear the container
    }
    // Emit status synchronously so Dart receives it before any async navigator cleanup.
    // Do NOT delete the window callbacks here — the Dart side re-registers them before each
    // openPublication call, and deleting them asynchronously races with the new registration.
    window.updateReaderStatus?.(error ? ReadiumReaderStatus.error : ReadiumReaderStatus.closed);

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
   *
   * See `seekAudioAndResume` for why the pause-before-seek is required (upstream
   * `go()` leaves position polling stopped when resuming an already-playing
   * element, freezing `currentLocator` and Media Overlay highlights).
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
    if (this._ttsEngine) { this._ttsEngine.stop(); return; }
    this._audioNav?.stop();
    // Clear Media Overlay / Guided Navigation utterance decoration when narration stops.
    if ((this._hasSyncNarration || this._hasGuidedNavigation) && this._nav) {
      this._lastMediaOverlayLocatorKey = null;
      this.applyDecorations("media_overlay_utterance", "[]");
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

    if (this._nav && this._positions.length > 0) {
      const index = Math.min(
        Math.floor(progression * this._positions.length),
        this._positions.length - 1
      );
      const locator = this._positions[index];
      this._nav.go(locator, true, (ok) => {
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
    this._ttsEngine = new WebTTSEngine(
      this._nav,
      this._publication,
      prefs,
      !this._disableSynchronization,
      this._utteranceStyle,
      this._rangeStyle,
      (group, decorationsJson) => this.applyDecorations(group, decorationsJson)
    );
    const fromLocator = fromLocatorJson
      ? Locator.deserialize(JSON.parse(fromLocatorJson)) ?? undefined
      : undefined;
    await this._ttsEngine.play(fromLocator);
  }

  /** Returns a JSON string containing available browser TTS voices. */
  public async ttsGetAvailableVoices(): Promise<string> {
    return WebTTSEngine.getAvailableVoices();
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
   * Follows Media Overlay / Guided Navigation audio with the visual navigator:
   * turns the page to the spoken text, then highlights it. Invoked on every
   * audio cue; de-duplicated by "<href><fragment>" so repeated poll ticks
   * within a single cue don't re-navigate or re-decorate.
   *
   * Order matters. The page turn must finish before the decoration is applied,
   * otherwise the target resource's iframe isn't rendered yet and the upstream
   * Decorator logs "Can't locate DOM range for decoration". `nav.go()` resolves
   * the resource from the position list by href — so a position-less text
   * locator (sync-narration / guided-nav locators only carry href + fragments)
   * is fine — and scrolls to the fragment / cssSelector within it. The
   * decoration is applied in the navigation-completion callback.
   *
   * Mirrors iOS FlutterMediaOverlayNavigator: `reachedLocator` → syncToLocator
   * (page-follow, skipped when sync is disabled) plus `requestsHighlightAt` →
   * decoration. When synchronization is disabled the page is left where it is
   * and only the highlight is refreshed.
   */
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
   * Synchronises the visual EPUB navigator to the active Media Overlay / Guided
   * Navigation cue.
   *
   * For normal (non-comic) publications: calls nav.go() to follow the page, then
   * applies the utterance-highlight decoration.
   *
   * For comic-book publications (detected via window.isNotaComicBook()): skips
   * nav.go() entirely (it would crash ColumnSnapper on quirks-mode FXL docs) and
   * delegates pan/zoom to window.gotoComicFrame(fragmentId, durationMs).
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
    // Check whether any loaded iframe is a comic page. Once confirmed, cache the
    // result so subsequent cues don't re-scan (all pages in a comic book are comics).
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

      // Determine whether the target resource is already loaded in an iframe.
      // If not (cross-resource navigation), we must call nav.go() first so Readium
      // loads the new XHTML into the iframe. Without it the reader stays on the old
      // resource. Once nav.go() completes (new document rendered), we call
      // gotoComicFrame to pan to the first panel. The scrollingElement null-guard
      // in our bootstrap script prevents the ColumnSnapper crash during navigation.
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
        // Resource not loaded yet — navigate first, then pan.
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
          // After nav.go() the iframes list is updated — find the newly loaded one.
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
        // Same resource — skip nav.go() entirely, just pan.
        log.debug(
          `${sourceLabel}: [comic] same-resource frame, calling gotoComicFrame directly`
        );
        doGotoFrame(targetWnd);
      }
      return;
    }

    // --- Normal (non-comic) path ---
    const applyUtteranceDecoration = () => {
      if (!this._utteranceStyle || !this._nav) return;
      try {
        const decoration = [
          {
            id: textLocator.href,
            locator: textLocator.serialize(),
            style: this._utteranceStyle,
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

    // When the user has disabled synchronization, don't drag the page around —
    // just refresh the highlight on whatever is currently shown.
    if (this._disableSynchronization) {
      applyUtteranceDecoration();
      return;
    }

    // Follow the audio: turn the visual page to the spoken text, then highlight
    // once navigation settles so the target iframe is rendered.
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
   * Enables audio playback.
   *  - Pure audiobook: AudioNavigator already initialized in openPublication — just play.
   *  - Media Overlay EPUB: lazy-initialize MediaOverlayNavigator, then play.
   */
  public async audioEnable(prefsJson: string, fromLocatorJson?: string): Promise<void> {
    log.info("audioEnable");
    // Resolve starting locator: caller-supplied wins; otherwise fall back to the
    // visual navigator's current locator so audio picks up where the reader is.
    // Mirrors `initialLocator ?: epubNavigator?.currentLocator?.value` on Android.
    const resolvedFromLocator: Locator | undefined = fromLocatorJson
      ? Locator.deserialize(JSON.parse(fromLocatorJson)) ?? undefined
      : this._nav?.currentLocator;

    if (this._audioNav) {
      // AudioNavigator already initialized (pure audiobook or re-enable on MediaOverlay EPUB).
      // Seek to locator (if available), mapping text→audio for MediaOverlay first.
      if (resolvedFromLocator) {
        let locator = resolvedFromLocator;
        // MediaOverlay: map text locator → audio locator before seeking.
        if (this._syncItems.length > 0) {
          locator = textLocatorToAudioLocator(this._syncItems, locator) ?? locator;
        }
        this._seekAudioAndResume(locator, true);
        return;
      }
      this._audioNav.play();
      return;
    }

    if (this._hasGuidedNavigation && this._publication) {
      const fromLocator = resolvedFromLocator;
      this._lastMediaOverlayLocatorKey = null;
      await initializeGuidedNavigationNavigator(
        this._publication,
        fromLocator,
        prefsJson,
        (nav, items) => { this._audioNav = nav; this._syncItems = items; },
        (textLocator, durationMs) => this._syncVisualToMediaOverlayLocator(textLocator, "GuidedNavigation", durationMs)
      );
      (this._audioNav as AudioNavigator | undefined)?.play();
      return;
    }

    if (this._hasSyncNarration && this._publication) {
      const fromLocator = resolvedFromLocator;
      // Reset deduplication key so a fresh session always applies its first decoration.
      this._lastMediaOverlayLocatorKey = null;
      await initializeMediaOverlayNavigator(
        this._publication,
        fromLocator,
        prefsJson,
        (nav, items) => { this._audioNav = nav; this._syncItems = items; },
        (textLocator, durationMs) => this._syncVisualToMediaOverlayLocator(textLocator, "MediaOverlay", durationMs)
      );
      // Re-read after await; cast to break TypeScript's control-flow narrowing
      // which assumes _audioNav is still undefined (it was set by the callback).
      // TODO: This seems awkward, could the Future just return navigator?
      (this._audioNav as AudioNavigator | undefined)?.play();
      return;
    }

    log.warn("audioEnable: no audiobook or Media Overlay content detected");
  }

  public setAudioPreferences(preferencesJson: string): void {
    log.debug("setAudioPreferences");
    if (!this._audioNav) return;
    const prefs = JSON.parse(preferencesJson);
    this._audioNav.submitPreferences(new AudioPreferences({
      volume: prefs.volume ?? null,
      playbackRate: prefs.speed ?? null,
      skipBackwardInterval: prefs.seekInterval ?? null,
      skipForwardInterval: prefs.seekInterval ?? null,
      pollInterval: prefs.updateIntervalSecs != null
        ? prefs.updateIntervalSecs * 1000
        : null,
    }));
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
