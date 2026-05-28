import "./style.css";

import { AudioNavigator, AudioPreferences, EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { Locator, Resource } from "@readium/shared";
import { Link } from "@readium/shared";

// Helpers and extensions
import { fetchManifest } from "./helpers";
import { createLogger, LogLevel, setLogLevel } from "./logger";
import { ReadiumReaderStatus } from "./enums";
import { ReadiumPublication } from "./extensions/ReadiumPublication";
import { initializeEpubNavigatorAndPeripherals } from "./Epub/epubNavigator";
import { setEpubPreferencesFromString } from "./Epub/epubPreferences";
import { initializeWebPubNavigatorAndPeripherals } from "./WebPub/webpubNavigator";
import { initializeAudioNavigator } from "./Audio/audioNavigator";
import { detectSyncNarration } from "./Audio/syncNarration";
import { initializeMediaOverlayNavigator } from "./Audio/mediaOverlayNavigator";
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
  /**
   * Latest value of `EPUBPreferences.disableSynchronization` from the Dart side.
   * Held here because it is plugin-side state, not part of the navigator's
   * preference surface. Passed to the TTS engine on enable and on every change.
   */
  private _disableSynchronization = false;

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

  public async goTo(href: string): Promise<void> {
    log.debug("goTo", href);
    // Audiobook: build a Locator from the publication's reading order and navigate via AudioNavigator.
    if (this._audioNav) {
      const pub = this._publication;
      const allLinks = [
        ...(pub?.readingOrder?.items ?? []),
        ...(pub?.resources?.items ?? []),
      ];
      const link = findLinkByHref(allLinks, href);
      if (!link) {
        log.error("Audio link not found:", href);
        throw new Error("Audio link not found " + href);
      }
      const locator = new Locator({ href: link.href, type: link.type ?? "audio/mpeg" });
      await this._audioNav.go(locator, false, (ok) => {
        if (!ok) log.error("Audiobook navigation failed for href:", href);
      });
      return;
    }

    // EPUB / WebPub: TOC entries point into the reading order or resources.
    const pub = this._nav?.publication;
    const allLinks = [
      ...(pub?.readingOrder?.items ?? []),
      ...(pub?.resources?.items ?? []),
    ];
    const link = findLinkByHref(allLinks, href);
    if (!link) {
      log.error("Link not found:", href);
      throw new Error("Link not found " + href);
    }
    this._nav?.goLink(link, true, (ok) => {
      if (!ok) {
        log.error("Failed to navigate to link:", href);
        throw new Error("Failed to navigate to link " + href);
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

  public closePublication(error?: any) {
    log.info("closePublication", error ? `(error: ${error})` : "");
    this._ttsEngine?.destroy();
    this._ttsEngine = undefined;
    this._hasSyncNarration = false;
    this._positions = [];
    this._publication = undefined;

    // Emit status synchronously so Dart receives it before any async navigator cleanup.
    // Do NOT delete the window callbacks here — the Dart side re-registers them before each
    // openPublication call, and deleting them asynchronously races with the new registration.
    if (error) {
      window.updateReaderStatus?.(ReadiumReaderStatus.error);
    } else {
      window.updateReaderStatus?.(ReadiumReaderStatus.closed);
    }

    this._audioNav?.destroy();
    this._audioNav = undefined;

    const clearContainer = () => {
      this._nav = undefined;
      const container = document.getElementById("container");
      if (container) {
        container.innerHTML = "";
      }
    };

    const navDestroy = this._nav?.destroy();
    if (navDestroy) {
      navDestroy.catch((err) => {
        log.error("Error destroying navigator:", err);
      }).finally(() => {
        clearContainer();
      });
    } else {
      clearContainer();
    }
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
      const locator = Locator.deserialize(JSON.parse(locatorJson));
      if (locator) {
        // Ensure playback is active so go() sees wasPlaying=true and resumes
        // after seeking.
        this._audioNav.play();
        this._audioNav.go(locator, false, () => {});
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
      !this._disableSynchronization
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
   * Enables audio playback.
   *  - Pure audiobook: AudioNavigator already initialized in openPublication — just play.
   *  - Media Overlay EPUB: lazy-initialize MediaOverlayNavigator, then play.
   */
  public async audioEnable(prefsJson: string, fromLocatorJson?: string): Promise<void> {
    log.info("audioEnable");
    if (this._audioNav) {
      // Pure audiobook already initialized — seek to locator (if provided) and play.
      if (fromLocatorJson) {
        const locator = Locator.deserialize(JSON.parse(fromLocatorJson));
        if (locator) {
          // Set play intent before go() so wasPlaying is true and playback
          // resumes automatically after the seek completes.
          this._audioNav.play();
          this._audioNav.go(locator, false, () => {});
          return;
        }
      }
      this._audioNav.play();
      return;
    }

    if (this._hasSyncNarration && this._publication) {
      const fromLocator = fromLocatorJson
        ? Locator.deserialize(JSON.parse(fromLocatorJson)) ?? undefined
        : undefined;
      await initializeMediaOverlayNavigator(
        this._publication,
        fromLocator,
        prefsJson,
        (nav) => { this._audioNav = nav; }
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
