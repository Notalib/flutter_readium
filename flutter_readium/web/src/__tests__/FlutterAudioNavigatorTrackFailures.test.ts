/**
 * Track-level failures in a multi-track audio session:
 *   - a track proven broken in the publication (gone, served empty, undecodable) fails at once
 *     with a `reason`, like iOS and Android it is not skipped; a transient failure is retried;
 *   - a closed session's pending create, listeners and recovery never reach Flutter.
 *
 * ts-toolkit's AudioNavigator is replaced with a fake that loads a track by firing
 * `trackLoaded` or, for a broken track, `error`. The HTTP probe is stubbed per track.
 */

import { Locator, LocatorLocations } from "@readium/shared";
import {
  AudioRecoveryPolicy,
  AudioStreamErrorAction,
  setCurrentAudioRecoveryPolicy,
} from "../navigators/AudioStreamErrorPolicy";
import { ReadiumBridge } from "../bridge/ReadiumBridge";
import { ReadiumPublication } from "../utils/ReadiumExtensions";

type Listeners = Record<string, (...args: unknown[]) => void>;

const BASE = "https://example.test/pub/";
const track = (n: number) => `${BASE}track${n}.mp3`;

/** Tracks whose load fails with a MediaError; everything else loads. */
let brokenTracks = new Set<string>();
/** Tracks whose load never settles, like a stalled connection. */
let hangingTracks = new Set<string>();

class FakeAudioNavigator {
  static instances: FakeAudioNavigator[] = [];
  currentTime = 0;
  duration = 60;
  isPlaying = false;
  destroyed = false;
  currentLocator: Locator;

  constructor(
    pub: ReadiumPublication,
    readonly listeners: Listeners,
    initial: Locator | undefined
  ) {
    FakeAudioNavigator.instances.push(this);
    this.currentLocator = initial ?? locatorFor(pub.readingOrder.items[0].href);
    const href = this.currentLocator.href;
    queueMicrotask(() => {
      if (this.destroyed || hangingTracks.has(href)) return;
      if (brokenTracks.has(href)) this.listeners.error({ code: 4 }, this.currentLocator);
      else this.listeners.trackLoaded(undefined);
    });
  }

  play(): void {
    this.isPlaying = true;
    this.currentTime += 5;
  }
  pause(): void {
    this.isPlaying = false;
  }
  stop(): void {
    this.isPlaying = false;
  }
  destroy(): void {
    this.destroyed = true;
  }
}

jest.mock("@readium/navigator", () => ({
  AudioNavigator: function (...args: ConstructorParameters<typeof FakeAudioNavigator>) {
    return new FakeAudioNavigator(...args);
  },
}));

const probeResults = new Map<string, AudioStreamErrorAction | undefined>();
const probe = jest.fn(async (url: string, _options?: unknown) => probeResults.get(url));
jest.mock("../navigators/AudioStreamHttpProbe", () => ({
  probeAudioStreamHttpStatus: (url: string, options?: unknown) => probe(url, options),
}));

import { FlutterAudioNavigator } from "../navigators/FlutterAudioNavigator";
import { ReadiumWebErrorCode } from "../errors/ReadiumWebError";

function locatorFor(href: string): Locator {
  return new Locator({
    href,
    type: "audio/mpeg",
    locations: new LocatorLocations({ fragments: ["t=0"] }),
  });
}

function fakePublication(trackCount: number): ReadiumPublication {
  const links = Array.from({ length: trackCount }, (_, i) => {
    const href = track(i + 1);
    return { href, type: "audio/mpeg", duration: 60, toURL: () => href };
  });
  return {
    readingOrder: { items: links },
    allLinks: links,
    baseURL: BASE,
    toc: { items: [] },
  } as unknown as ReadiumPublication;
}

const states = jest.fn();
const emitError = jest.fn();
const bridge = { emitError } as unknown as ReadiumBridge;

let installed: FakeAudioNavigator | undefined;

function open(trackCount: number, initialTrack?: number): Promise<boolean> {
  return FlutterAudioNavigator.create(
    fakePublication(trackCount),
    initialTrack ? locatorFor(track(initialTrack)) : undefined,
    "{}",
    (nav) => (installed = nav as unknown as FakeAudioNavigator),
    undefined,
    undefined,
    undefined,
    bridge
  );
}

const settle = (ms = 0) => new Promise((r) => setTimeout(r, ms));
const errorCodes = () => emitError.mock.calls.map((c) => c[1]);
const lastNav = () => FakeAudioNavigator.instances.at(-1)!;

function usePolicy(policy: AudioRecoveryPolicy): void {
  setCurrentAudioRecoveryPolicy(policy);
}

beforeAll(() => {
  (globalThis as { window?: unknown }).window = { updateTimebasedPlayerState: states };
});

beforeEach(() => {
  FakeAudioNavigator.instances = [];
  brokenTracks = new Set();
  hangingTracks = new Set();
  probeResults.clear();
  probe.mockClear();
  states.mockReset();
  emitError.mockReset();
  installed = undefined;
  // Short timeouts keep the timeout paths fast; real timers keep upstream ordering intact.
  usePolicy(new AudioRecoveryPolicy(1, 0.001, 20, 0.1));
});

afterEach(() => {
  FlutterAudioNavigator.resetRecovery();
});

afterAll(() => {
  setCurrentAudioRecoveryPolicy(new AudioRecoveryPolicy());
});

describe("defective tracks", () => {
  it("fails at once with the defect's code and reason, without retrying or moving on", async () => {
    brokenTracks = new Set([track(1)]);
    probeResults.set(track(1), AudioStreamErrorAction.fail("AudioStreamHTTPError", 416, "empty"));

    await expect(open(3)).rejects.toMatchObject({ code: ReadiumWebErrorCode.audioStreamNetworkError });

    expect(errorCodes()).toEqual(["AudioStreamHTTPError"]);
    expect(emitError.mock.calls[0][2]).toEqual({ href: track(1), httpStatus: 416, reason: "empty" });
    expect(FlutterAudioNavigator.isTerminallyFailed()).toBe(true);
    expect(FakeAudioNavigator.instances).toHaveLength(1); // no rebuild
    expect(lastNav().currentLocator.href).toBe(track(1));
  });

  it("probes a decode error and reports the probe's verdict", async () => {
    await open(2);
    const nav = lastNav();
    probeResults.set(track(1), AudioStreamErrorAction.fail("AudioStreamError", 200, "undecodable"));

    nav.listeners.error({ code: 3 }, nav.currentLocator);
    await settle();

    expect(probe).toHaveBeenCalledWith(track(1), { decodeError: true });
    expect(errorCodes()).toEqual(["AudioStreamError"]);
    expect(emitError.mock.calls[0][2]).toEqual({ href: track(1), httpStatus: 200, reason: "undecodable" });
  });

  it("reports a decode error without a reason when the probe is inconclusive", async () => {
    await open(2);
    const nav = lastNav();

    nav.listeners.error({ code: 3 }, nav.currentLocator);
    await settle();

    expect(errorCodes()).toEqual(["AudioStreamError"]);
    expect(emitError.mock.calls[0][2]?.reason).toBeUndefined();
  });

  it("retries a transient failure (5xx), then fails as a network error without a reason", async () => {
    brokenTracks = new Set([track(1)]);
    probeResults.set(track(1), AudioStreamErrorAction.retry());

    await expect(open(3)).rejects.toMatchObject({ code: ReadiumWebErrorCode.audioStreamNetworkError });
    await settle(300);

    expect(errorCodes()).toEqual(["AudioStreamRetry", "AudioStreamNetworkError"]);
    expect(emitError.mock.calls[1][2]?.reason).toBeUndefined();
  });

  it("does not claim a defect when the probe is inconclusive", async () => {
    brokenTracks = new Set([track(1)]);
    probeResults.set(track(1), undefined); // MediaError 4 alone -> AudioStreamNetworkError

    await expect(open(3)).rejects.toMatchObject({ code: ReadiumWebErrorCode.audioStreamNetworkError });

    expect(errorCodes()).toEqual(["AudioStreamNetworkError"]);
    expect(emitError.mock.calls[0][2]?.reason).toBeUndefined();
  });
});

describe("recovery during the first load", () => {
  it("opens on the rebuilt navigator instead of timing out and destroying it", async () => {
    brokenTracks = new Set([track(1)]);
    probe.mockImplementationOnce(async () => {
      brokenTracks.delete(track(1)); // the connection comes back
      return AudioStreamErrorAction.retry();
    });

    await expect(open(2)).resolves.toBe(true);

    expect(FakeAudioNavigator.instances).toHaveLength(2);
    expect(installed).toBe(FakeAudioNavigator.instances[1]);
    expect(installed?.destroyed).toBe(false);
    expect(FlutterAudioNavigator.isTerminallyFailed()).toBe(false);
    expect(errorCodes()).toEqual(["AudioStreamRetry"]);
  });
});

describe("closing the publication", () => {
  it("a create still pending at close resolves quietly and destroys its navigator", async () => {
    hangingTracks = new Set([track(1)]);
    const pending = open(2);
    await settle();

    FlutterAudioNavigator.resetRecovery(); // what closePublication does
    await expect(pending).resolves.toBe(false);

    expect(lastNav().destroyed).toBe(true);
    expect(installed).toBeUndefined();
    expect(emitError).not.toHaveBeenCalled();
  });

  it("a closed session's late error neither probes nor emits", async () => {
    await open(2);
    const closed = lastNav();
    FlutterAudioNavigator.resetRecovery();

    closed.listeners.error({ code: 2 }, closed.currentLocator);
    await settle();

    expect(probe).not.toHaveBeenCalled();
    expect(emitError).not.toHaveBeenCalled();
  });

  it("a closed session's late events stay silent after the next session starts", async () => {
    await open(2);
    const closed = lastNav();
    FlutterAudioNavigator.resetRecovery();
    await open(2); // re-enables emissions for the new session
    states.mockReset();

    closed.listeners.positionChanged(closed.currentLocator);
    closed.listeners.play(closed.currentLocator);

    expect(states).not.toHaveBeenCalled();
  });

  it("stops an in-flight recovery: no retry, rebuild or terminal error after close", async () => {
    usePolicy(new AudioRecoveryPolicy(3, 0.05, 20, 0.1));
    await open(2);
    probeResults.set(track(1), AudioStreamErrorAction.retry());
    lastNav().listeners.error({ code: 2 }, lastNav().currentLocator);
    await settle();
    expect(errorCodes()).toEqual(["AudioStreamRetry"]);

    FlutterAudioNavigator.resetRecovery();
    await settle(500);

    expect(errorCodes()).toEqual(["AudioStreamRetry"]);
    expect(FakeAudioNavigator.instances).toHaveLength(1);
  });
});
