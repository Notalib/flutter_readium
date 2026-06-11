import "./style.css";

import { AudioNavigator, EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { Link, Locator } from "@readium/shared";

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
import { FlutterAudioNavigator, setAudioEmissionsEnabled, seekAudioAndResume } from "./navigators/FlutterAudioNavigator";
import { FlutterTTSNavigator } from "./navigators/FlutterTTSNavigator";
import { initializeMediaOverlayNavigator, initializeGuidedNavigationNavigator } from "./navigators/FlutterMediaOverlayNavigator";
// Preferences
import { setEpubPreferencesFromString } from "./preferences/FlutterEpubPreferences";
import { ttsPreferencesFromJson } from "./preferences/FlutterTTSPreferences";
import { applyAudioPreferences } from "./preferences/FlutterAudioPreferences";
// Sync narration
import { SyncNarrationItem, detectSyncNarration, textLocatorToAudioLocator } from "./mediaoverlay/syncNarration";
import { detectGuidedNavigation } from "./mediaoverlay/guidedNavigation";
// Decoration overrides (for comic/visual sync)
import { navIframeWindows } from "./decorations/decorationFrameUtils";

const log = createLogger("Reader");

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
  private _ttsEngine: FlutterTTSNavigator | undefined;
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

  public get isNavigatorReady(): boolean {
    return !!this._nav;
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

    try {
      // TODO: match native
      this._publication = await this._pubManager.getOrFetch(pubId, publicationURL);

      if (this._publication.conformsToAudiobook) {
        log.info("Publication conforms to Audiobook profile");
        // AudioNavigator doesn't need a DOM container — it drives <audio> elements directly.
        await FlutterAudioNavigator.create(
          this._publication,
          initialPosition,
          preferencesJsonString,
          (nav) => {
            this._audioNav = nav;
            this._bridge.emitReaderStatus(ReadiumReaderStatus.ready);
          }
        );
      } else {
        // EPUB and WebPub navigators render into a DOM container.
        const container: HTMLElement | null =
          document.body.querySelector("#container");
        if (!container) {
          log.error("Container element #container not found in DOM");
          this._bridge.emitReaderStatus(ReadiumReaderStatus.error);
          throw new Error("Container element not found");
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
            (json) => { this._bridge.emitImageTapped(json); }
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
      const errorMessage = error instanceof Error ? error.message : String(error);
      this._bridge.emitError("Failed to open publication: " + errorMessage);
      this.closePublication(error);
      throw error;
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
      this._ttsEngine?.setSyncEnabled(!this._disableSynchronization);
    } catch (_) {
      // Ignore parse errors — setEpubPreferencesFromString will surface them.
    }
    setEpubPreferencesFromString(newPreferencesString, this._nav);
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
    this._decorations.reset();

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
    this._ttsEngine = new FlutterTTSNavigator(
      this._nav,
      this._publication,
      prefs,
      !this._disableSynchronization,
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

    if (this._disableSynchronization) {
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
   * Fetches the raw bytes for a publication resource identified by its
   * publication-relative href (e.g. `images/cover.png`).
   * Returns a `Uint8Array` that can be passed directly back to Dart as a
   * typed array — do NOT JSON-encode it.
   */
  public async getResourceBytes(href: string): Promise<Uint8Array> {
    const pub = this._publication;
    if (!pub) {
      throw new Error("getResourceBytes: no publication is open");
    }
    const link = findLinkByHref(pub.allLinks, href);
    if (!link) {
      throw new Error(`getResourceBytes: no resource found for href: ${href}`);
    }
    const resource = pub.get(link);
    const bytes = await resource.read();
    if (!bytes) {
      throw new Error(`getResourceBytes: read() returned undefined for href: ${href}`);
    }
    return bytes;
  }

  /**
   * Enables audio playback.
   *  - Pure audiobook: AudioNavigator already initialized in openPublication — just play.
   *  - Media Overlay EPUB: lazy-initialize MediaOverlayNavigator, then play.
   */
  public async audioEnable(prefsJson: string, fromLocatorJson?: string): Promise<void> {
    log.info("audioEnable");
    const resolvedFromLocator: Locator | undefined = fromLocatorJson
      ? Locator.deserialize(JSON.parse(fromLocatorJson)) ?? undefined
      : this._nav?.currentLocator;

    if (this._audioNav) {
      if (resolvedFromLocator) {
        let locator = resolvedFromLocator;
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
      this._lastMediaOverlayLocatorKey = null;
      await initializeMediaOverlayNavigator(
        this._publication,
        fromLocator,
        prefsJson,
        (nav, items) => { this._audioNav = nav; this._syncItems = items; },
        (textLocator, durationMs) => this._syncVisualToMediaOverlayLocator(textLocator, "MediaOverlay", durationMs)
      );
      (this._audioNav as AudioNavigator | undefined)?.play();
      return;
    }

    log.warn("audioEnable: no audiobook or Media Overlay content detected");
  }

  public setAudioPreferences(preferencesJson: string): void {
    log.debug("setAudioPreferences");
    if (!this._audioNav) return;
    applyAudioPreferences(this._audioNav, preferencesJson);
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
