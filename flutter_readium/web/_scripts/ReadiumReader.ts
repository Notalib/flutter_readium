import "./style.css";

import { AudioNavigator, AudioPreferences, EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { Locator, Profile, Publication, Resource } from "@readium/shared";
import { Link } from "@readium/shared";

// Helpers and extensions
import { fetchManifest } from "./helpers";
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

class _ReadiumReader {
  public constructor() {
    console.log("R2Navigator initialized");
  }

  private _publication: ReadiumPublication | undefined;
  private _nav: EpubNavigator | WebPubNavigator | undefined;
  private _audioNav: AudioNavigator | undefined;
  private _ttsEngine: WebTTSEngine | undefined;
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
    try {
      const { manifest, fetcher } = await fetchManifest(publicationURL);
      this._publication = new ReadiumPublication({ manifest, fetcher });

      let pubId = this._publication.metadata.identifier ?? "unidentified";
      _ReadiumReader._publications.set(pubId, this._publication);

      return JSON.stringify(manifest.serialize());
    } catch (error) {
      throw new Error("Error getting publication: " + error);
    }
  }

  public goRight() {
    this._nav?.goRight(true, () => {});
  }

  public goLeft() {
    this._nav?.goLeft(true, () => {});
  }

  /**
   * Progression-aware navigation. `goForward` / `goBackward` are RTL-aware on
   * the upstream navigator (unlike `goRight` / `goLeft`, which are purely
   * visual). The Dart-side `goForward`/`goBackward` API maps to these.
   */
  public goForward() {
    this._nav?.goForward(true, () => {});
  }

  public goBackward() {
    this._nav?.goBackward(true, () => {});
  }

  public async goTo(href: string): Promise<void> {
    // TOC entries point into the reading order, not the resources collection.
    // Check both — readingOrder first, since that's the common case for
    // chapter navigation via the Dart-side `goToLocator`.
    const pub = this._nav?.publication;
    const link =
      pub?.readingOrder?.findWithHref(href) ??
      pub?.resources?.findWithHref(href);
    if (!link) {
      const triedLinks = [
        ...(pub?.readingOrder?.items ?? []),
        ...(pub?.resources?.items ?? []),
      ]
        .map((l) => l.href)
        .join(", ");
      console.error("Link not found " + href + ". Tried all resource links", triedLinks);
      throw new Error("Link not found " + href);
    }
    this._nav?.goLink(link, true, (ok) => {
      if (!ok) {
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
    (window as any).updateReaderStatus?.(ReadiumReaderStatus.loading);

    let initialPosition: Locator | undefined;

    if (initialPositionJson) {
      initialPosition = Locator.deserialize(JSON.parse(initialPositionJson));
    }

    let preferencesJsonString =
      !preferencesJson || preferencesJson === "null" ? "{}" : preferencesJson;

    // Reset per-publication state so stale values don't bleed across openPublication calls.
    this._hasSyncNarration = false;

    try {
      // TODO: match native
      this._publication = _ReadiumReader._publications.get(pubId);
      if (!this._publication) {
        const { manifest, fetcher } = await fetchManifest(publicationURL);
        this._publication = new ReadiumPublication({ manifest, fetcher });
        _ReadiumReader._publications.set(pubId, this._publication);
      }

      if (this._publication.conformsToAudiobook) {
        // AudioNavigator doesn't need a DOM container — it drives <audio> elements directly.
        await initializeAudioNavigator(
          this._publication,
          initialPosition,
          preferencesJsonString,
          (nav) => {
            this._audioNav = nav;
            (window as any).updateReaderStatus?.(ReadiumReaderStatus.ready);
          }
        );
      } else {
        // EPUB and WebPub navigators render into a DOM container.
        const container: HTMLElement | null =
          document.body.querySelector("#container");
        if (!container) {
          console.error("Container element not found");
          (window as any).updateReaderStatus?.("error");
          throw new Error("Container element not found");
        }
        if (this._publication.conformsToEpub) {
          // Detect sync narration before opening the navigator (async fetch-free check).
          this._hasSyncNarration = detectSyncNarration(this._publication);
          await initializeEpubNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              (window as any).updateReaderStatus?.(ReadiumReaderStatus.ready);
            }
          );
        } else {
          await initializeWebPubNavigatorAndPeripherals(
            container,
            this._publication,
            initialPosition,
            preferencesJsonString,
            (nav) => {
              this._nav = nav;
              (window as any).updateReaderStatus?.(ReadiumReaderStatus.ready);
            }
          );
        }
      }
    } catch (error) {
      this.closePublication(error);
      throw new Error("Error opening publication: " + error);
    }
  }

  public setEPUBPreferences(newPreferencesString: string) {
    if (!this._nav) {
      throw new Error("Navigator is not initialized");
    }
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
    this._publication = undefined;
    this._ttsEngine?.destroy();
    this._ttsEngine = undefined;
    this._nav?.destroy();
    this._audioNav?.destroy();
    this._audioNav = undefined;
    this._hasSyncNarration = false;
    const container = document.getElementById("container");
    if (container) {
      container.innerHTML = "";
    }
    if (error) {
      (window as any).updateReaderStatus?.(ReadiumReaderStatus.error);
    } else {
      (window as any).updateReaderStatus?.(ReadiumReaderStatus.closed);
    }

    delete (window as any).updateTextLocator;
    delete (window as any).updateReaderStatus;
    delete (window as any).updateTimebasedPlayerState;
  }

  public play(locatorJson?: string): void {
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
        this._audioNav.go(locator, false, () => {});
        return;
      }
    }
    this._audioNav.play();
  }

  public pause(): void {
    if (this._ttsEngine) { this._ttsEngine.pause(); return; }
    this._audioNav?.pause();
  }

  public resume(): void {
    if (this._ttsEngine) { this._ttsEngine.resume(); return; }
    this._audioNav?.play();
  }

  public stop(): void {
    if (this._ttsEngine) { this._ttsEngine.stop(); return; }
    this._audioNav?.stop();
  }

  public next(): void {
    if (this._ttsEngine) { this._ttsEngine.next(); return; }
    this._audioNav?.goForward(false, () => {});
  }

  public previous(): void {
    if (this._ttsEngine) { this._ttsEngine.previous(); return; }
    this._audioNav?.goBackward(false, () => {});
  }

  /** Relative seek by seconds. Applies to AudioNavigator (audiobook / Media Overlay). */
  public seekBy(seconds: number): void {
    this._audioNav?.jump(seconds);
  }

  // ---------------------------------------------------------------------------
  // TTS API
  // ---------------------------------------------------------------------------

  /**
   * Initialises (or re-initialises) the TTS engine and starts playback.
   * Requires an EPUB or WebPub visual navigator to already be active.
   */
  public async ttsEnable(prefsJson: string, fromLocatorJson?: string): Promise<void> {
    if (!this._nav || !this._publication) {
      console.warn("ttsEnable: no visual navigator active");
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
    if (this._audioNav) {
      // Pure audiobook already initialized — seek to locator (if provided) and play.
      if (fromLocatorJson) {
        const locator = Locator.deserialize(JSON.parse(fromLocatorJson));
        if (locator) {
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

    console.log("audioEnable: no audiobook or Media Overlay content detected");
  }

  public setAudioPreferences(preferencesJson: string): void {
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

  public async getResource(linkString: String, asBytes: boolean = false) {
    // Step one - linkString to json object
    let linkJson = JSON.parse(linkString.toString());
    // Step two - json to Link object
    let link: Link | undefined = Link.deserialize(linkJson);
    if (!link) {
      console.error("Invalid link string");
    }
    // Step three - fetch the resource link
    let resourceLink: Resource | undefined = this._publication?.get(link!);

    if (!resourceLink) {
      console.error("Resource not found", link);
    }

    // Step four - get resource as string
    let resourceString: string | undefined;
    if (asBytes) {
      let resourceBytes = await resourceLink?.read();
      resourceString = JSON.stringify(Array.from(resourceBytes!));
    } else {
      resourceString = await resourceLink?.readAsString();
    }

    return resourceString;
  }
}

declare global {
  namespace globalThis {
    var ReadiumReader: typeof _ReadiumReader;
  }
}

globalThis.ReadiumReader = _ReadiumReader;
