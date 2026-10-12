/**
 * Audio streaming errors must be classified and recovered the same way for plain
 * audiobooks and Media Overlay (sync narration) sessions: a 401/403 surfaces as
 * `AudioStreamAuthError`, and a network error rebuilds the navigator without
 * losing the text mapping.
 *
 * ts-toolkit's AudioNavigator is replaced with a fake that captures the
 * listeners and reports `trackLoaded` right away; the HTTP probe is stubbed.
 */

import { Locator, LocatorLocations } from "@readium/shared";
import {
  AudioRecoveryPolicy,
  AudioStreamErrorAction,
  setCurrentAudioRecoveryPolicy,
} from "../navigators/AudioStreamErrorPolicy";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

let capturedListeners: Record<string, (...args: unknown[]) => void> | undefined;
let navCount = 0;

jest.mock("@readium/navigator", () => ({
  AudioNavigator: class {
    currentTime = 0;
    duration = 60;
    isPlaying = false;
    currentLocator: unknown;
    constructor(_pub: unknown, listeners: Record<string, (...args: unknown[]) => void>, initial: unknown) {
      capturedListeners = listeners;
      navCount += 1;
      this.currentLocator = initial;
      queueMicrotask(() => listeners.trackLoaded(undefined));
    }
    play() {
      this.currentTime += 5;
    }
    pause() {}
    stop() {}
    destroy() {}
  },
}));

const probe = jest.fn();
jest.mock("../navigators/AudioStreamHttpProbe", () => ({
  probeAudioStreamHttpStatus: (...args: unknown[]) => probe(...args),
}));

import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";

const HREF = "https://example.test/pub/audio/track1.mp3";
const TEXT_HREF = "chapter1.xhtml";
const PLAY_REJECTION = { name: "NotSupportedError", code: 9, message: "The element has no supported sources." };

const initial = new Locator({
  href: HREF,
  type: "audio/mpeg",
  locations: new LocatorLocations({ fragments: ["t=0"] }),
});

// Stands in for the Media Overlay mapper: audio locator -> text locator.
const textMapper = (_nav: unknown, loc: Locator) => ({
  stateLocator: new Locator({ href: TEXT_HREF, type: "application/xhtml+xml", locations: loc.locations }),
});

function fakePublication(): ReadiumPublication {
  const link = { href: HREF, type: "audio/mpeg", duration: 60, toURL: () => HREF };
  return {
    readingOrder: { items: [link] },
    allLinks: [link],
    baseURL: "https://example.test/pub/",
  } as unknown as ReadiumPublication;
}

const states = jest.fn();
const emitError = jest.fn();

async function open(opts: { mediaOverlay: boolean }): Promise<void> {
  await FlutterAudioNavigator.create(
    fakePublication(),
    initial,
    "{}",
    () => {},
    opts.mediaOverlay ? (textMapper as never) : undefined,
    undefined,
    opts.mediaOverlay ? 100 : undefined,
    { emitError } as unknown as ReadiumBridge
  );
}

async function fail(mediaError: unknown): Promise<void> {
  capturedListeners!.error(mediaError, initial);
  // Let the awaited probe settle.
  await new Promise((r) => setTimeout(r, 0));
}

const errorCodes = () => emitError.mock.calls.map((c) => c[1]);
const payloads = () => states.mock.calls.map((c) => JSON.parse(c[0] as string));

beforeAll(() => {
  (globalThis as { window?: unknown }).window = { updateTimebasedPlayerState: states };
  setCurrentAudioRecoveryPolicy(new AudioRecoveryPolicy(3, 0.001, 20, 1));
});

afterAll(() => {
  setCurrentAudioRecoveryPolicy(new AudioRecoveryPolicy());
});

beforeEach(() => {
  capturedListeners = undefined;
  navCount = 0;
  probe.mockReset();
  probe.mockResolvedValue(AudioStreamErrorAction.fail("AudioStreamAuthError", 401));
  states.mockReset();
  emitError.mockReset();
});

afterEach(() => {
  FlutterAudioNavigator.resetRecovery();
});

describe.each([
  ["plain audiobook", false],
  ["media overlay", true],
])("%s", (_label, mediaOverlay) => {
  it.each([
    ["MediaError SRC_NOT_SUPPORTED", { code: 4 }],
    ["rejected play()", PLAY_REJECTION],
  ])("%s + probe 401 emits AudioStreamAuthError, then failure", async (_kind, mediaError) => {
    await open({ mediaOverlay });
    await fail(mediaError);
    expect(probe).toHaveBeenCalledWith(HREF);
    expect(emitError).toHaveBeenCalledTimes(1);
    expect(emitError.mock.calls[0][1]).toBe("AudioStreamAuthError");
    expect(emitError.mock.calls[0][2]).toEqual({ href: HREF, httpStatus: 401 });
    expect(FlutterAudioNavigator.isTerminallyFailed()).toBe(true);
    expect(payloads().at(-1).state).toBe("failure");
  });

  it("MEDIA_ERR_ABORTED emits nothing and skips the probe", async () => {
    await open({ mediaOverlay });
    const before = states.mock.calls.length;
    await fail({ code: 1 });
    expect(probe).not.toHaveBeenCalled();
    expect(emitError).not.toHaveBeenCalled();
    expect(states.mock.calls.length).toBe(before);
  });

  it("network error rebuilds the navigator and keeps playing", async () => {
    probe.mockResolvedValue(undefined);
    await open({ mediaOverlay });
    await fail({ code: 2 });
    await new Promise((r) => setTimeout(r, 50));

    expect(errorCodes()).toEqual(["AudioStreamRetry"]);
    expect(navCount).toBe(2);
    expect(FlutterAudioNavigator.isTerminallyFailed()).toBe(false);
  });
});

describe("media overlay recovery", () => {
  it("the rebuilt navigator still maps audio to text", async () => {
    probe.mockResolvedValue(undefined);
    await open({ mediaOverlay: true });
    await fail({ code: 2 });
    await new Promise((r) => setTimeout(r, 50));
    expect(navCount).toBe(2);

    states.mockReset();
    capturedListeners!.positionChanged(initial);
    expect(payloads().at(-1).currentLocator.href).toBe(TEXT_HREF);
  });

  it("pinned recovery states carry the text locator", async () => {
    probe.mockResolvedValue(undefined);
    await open({ mediaOverlay: true });
    await fail({ code: 2 });
    const loading = payloads().find((p) => p.state === "loading");
    expect(loading?.currentLocator.href).toBe(TEXT_HREF);
  });

  it("recreateAfterFailure keeps the text mapping", async () => {
    await open({ mediaOverlay: true });
    await fail({ code: 4 });
    expect(FlutterAudioNavigator.isTerminallyFailed()).toBe(true);

    FlutterAudioNavigator.retryAfterFailure();
    let rebuilt = false;
    expect(FlutterAudioNavigator.recreateAfterFailure(initial, "{}", () => (rebuilt = true))).toBe(true);
    await new Promise((r) => setTimeout(r, 0));
    expect(rebuilt).toBe(true);

    states.mockReset();
    capturedListeners!.positionChanged(initial);
    expect(payloads().at(-1).currentLocator.href).toBe(TEXT_HREF);
  });
});
