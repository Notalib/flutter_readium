/**
 * A 401/403 on an audio resource must surface as `AudioStreamAuthError` on the
 * bridge, for plain audiobooks and for Media Overlay (sync narration) sessions.
 *
 * ts-toolkit's AudioNavigator is replaced with a fake that only captures the
 * listeners, and the HTTP probe is stubbed.
 */

import { Locator, LocatorLocations } from "@readium/shared";
import { AudioStreamErrorAction } from "../navigators/AudioStreamErrorPolicy";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

let capturedListeners: Record<string, (...args: unknown[]) => void> | undefined;
const navStop = jest.fn();

jest.mock("@readium/navigator", () => ({
  AudioNavigator: class {
    currentTime = 0;
    duration = 60;
    isPlaying = false;
    currentLocator: unknown;
    constructor(_pub: unknown, listeners: Record<string, (...args: unknown[]) => void>, initial: unknown) {
      capturedListeners = listeners;
      this.currentLocator = initial;
    }
    play() {}
    pause() {}
    stop() {
      navStop();
    }
    destroy() {}
  },
}));

const probe = jest.fn();
jest.mock("../navigators/AudioStreamHttpProbe", () => ({
  probeAudioStreamHttpStatus: (...args: unknown[]) => probe(...args),
}));

import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";

const HREF = "https://example.test/pub/audio/track1.mp3";
const PLAY_REJECTION = { name: "NotSupportedError", code: 9, message: "The element has no supported sources." };

const initial = new Locator({
  href: HREF,
  type: "audio/mpeg",
  locations: new LocatorLocations({ fragments: ["t=0"] }),
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
  const mapper = opts.mediaOverlay
    ? (_nav: unknown, loc: Locator) => ({ stateLocator: loc })
    : undefined;
  const created = FlutterAudioNavigator.create(
    fakePublication(),
    initial,
    "{}",
    () => {},
    mapper as never,
    undefined,
    opts.mediaOverlay ? 100 : undefined,
    { emitError } as unknown as ReadiumBridge
  );
  capturedListeners!.trackLoaded(undefined);
  await created;
}

async function fail(mediaError: unknown): Promise<void> {
  capturedListeners!.error(mediaError, initial);
  // Let the awaited probe settle.
  await new Promise((r) => setTimeout(r, 0));
}

const errorCodes = () => emitError.mock.calls.map((c) => c[1]);
const emittedStates = () => states.mock.calls.map((c) => JSON.parse(c[0] as string).state);

beforeAll(() => {
  (globalThis as { window?: unknown }).window = { updateTimebasedPlayerState: states };
});

beforeEach(() => {
  capturedListeners = undefined;
  probe.mockReset();
  probe.mockResolvedValue(AudioStreamErrorAction.fail("AudioStreamAuthError", 401));
  states.mockReset();
  emitError.mockReset();
  navStop.mockReset();
});

afterEach(() => {
  FlutterAudioNavigator.resetRecovery();
});

describe("plain audiobook", () => {
  it.each([
    ["MediaError SRC_NOT_SUPPORTED", { code: 4 }],
    ["rejected play()", PLAY_REJECTION],
  ])("%s + probe 401 emits AudioStreamAuthError", async (_label, mediaError) => {
    await open({ mediaOverlay: false });
    await fail(mediaError);
    expect(probe).toHaveBeenCalledWith(HREF);
    expect(errorCodes()).toEqual(["AudioStreamAuthError"]);
  });
});

describe("media overlay", () => {
  it.each([
    ["MediaError SRC_NOT_SUPPORTED", { code: 4 }],
    ["rejected play()", PLAY_REJECTION],
  ])("%s + probe 401 emits AudioStreamAuthError, then failure", async (_label, mediaError) => {
    await open({ mediaOverlay: true });
    await fail(mediaError);
    expect(probe).toHaveBeenCalledWith(HREF);
    expect(emitError).toHaveBeenCalledTimes(1);
    expect(emitError.mock.calls[0][1]).toBe("AudioStreamAuthError");
    expect(emitError.mock.calls[0][2]).toEqual({ href: HREF, httpStatus: 401 });
    expect(navStop).toHaveBeenCalled();
    expect(emittedStates().at(-1)).toBe("failure");
  });

  it("inconclusive probe emits AudioStreamNetworkError, then failure", async () => {
    probe.mockResolvedValue(undefined);
    await open({ mediaOverlay: true });
    await fail({ code: 2 });
    expect(errorCodes()).toEqual(["AudioStreamNetworkError"]);
    expect(emittedStates().at(-1)).toBe("failure");
  });

  it("MEDIA_ERR_ABORTED emits nothing and skips the probe", async () => {
    await open({ mediaOverlay: true });
    const before = states.mock.calls.length;
    await fail({ code: 1 });
    expect(probe).not.toHaveBeenCalled();
    expect(emitError).not.toHaveBeenCalled();
    expect(states.mock.calls.length).toBe(before);
  });

  it("repeated errors emit one error until playback is requested again", async () => {
    await open({ mediaOverlay: true });
    await fail({ code: 4 });
    await fail(PLAY_REJECTION);
    expect(emitError).toHaveBeenCalledTimes(1);

    FlutterAudioNavigator.setPlaybackIntent(true);
    await fail(PLAY_REJECTION);
    expect(emitError).toHaveBeenCalledTimes(2);
  });
});
