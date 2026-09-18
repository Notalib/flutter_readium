/**
 * Unit tests for FlutterTTSNavigator's speechSynthesis stall watchdog.
 *
 * The stall itself is not reproducible on healthy hardware — measured start
 * latency is 1-500ms for local and Google network voices alike — so these tests
 * drive a fake speechSynthesis to pin down what happens once it does stall.
 */

import { Locator, TextElement } from "@readium/shared";
import { FlutterTTSNavigator } from "../navigators/FlutterTTSNavigator";
import { WebTTSPreferences } from "../preferences/FlutterTTSPreferences";

const STALL_WATCHDOG_MS = 8000;
const STALL_RECOVERY_DELAY_MS = 200;

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class FakeUtterance {
  text: string;
  voice: any = null;
  lang = "";
  rate = 1;
  pitch = 1;
  onstart: (() => void) | null = null;
  onend: (() => void) | null = null;
  onerror: ((ev: { error: string }) => void) | null = null;
  onboundary: ((ev: any) => void) | null = null;
  constructor(text: string) {
    this.text = text;
  }
}

class FakeSpeechSynthesis {
  speaking = false;
  pending = false;
  paused = false;
  cancelCalls = 0;
  /** Every utterance passed to speak(), priming utterances included. */
  spoken: FakeUtterance[] = [];

  speak(u: FakeUtterance): void {
    this.spoken.push(u);
    // Mirrors the real engine: `speaking` flips synchronously inside speak(),
    // before any event is dispatched.
    if (u.text !== "") this.speaking = true;
  }
  cancel(): void {
    this.cancelCalls++;
    this.speaking = false;
    this.pending = false;
  }
  pause(): void {
    this.paused = true;
  }
  resume(): void {
    this.paused = false;
  }
  getVoices(): any[] {
    return [];
  }
}

let synth: FakeSpeechSynthesis;
let states: string[];

/** Utterances the navigator spoke, excluding the zero-length priming ones. */
function realUtterances(): FakeUtterance[] {
  return synth.spoken.filter((u) => u.text !== "");
}

function makeElement(text: string, href = "chap1.html"): TextElement {
  return {
    text,
    locator: new Locator({ href, type: "text/html" }),
    segments: [],
  } as unknown as TextElement;
}

function makeNavigator(): FlutterTTSNavigator {
  const publication = {
    manifest: {
      toc: undefined,
      subcollections: undefined,
      metadata: { languages: ["da"] },
    },
    metadata: { languages: ["da"] },
  };
  const prefs = { rate: 1, pitch: 1 } as unknown as WebTTSPreferences;
  const nav = new FlutterTTSNavigator(
    { go: jest.fn() } as any,
    publication as any,
    prefs
  );
  // The constructor hard-resets the engine; don't count that as recovery.
  synth.cancelCalls = 0;
  return nav;
}

/** Arms the watchdog by speaking `element`, without any engine response. */
function speakElement(nav: FlutterTTSNavigator, element: TextElement): void {
  (nav as any)._speakElement(element);
}

beforeEach(() => {
  jest.useFakeTimers();
  synth = new FakeSpeechSynthesis();
  states = [];
  (globalThis as any).speechSynthesis = synth;
  (globalThis as any).SpeechSynthesisUtterance = FakeUtterance;
  (globalThis as any).window = {
    updateTimebasedPlayerState: (json: string) => states.push(JSON.parse(json).state),
    updateTextLocator: () => {},
  };
});

afterEach(() => {
  jest.useRealTimers();
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("stall watchdog", () => {
  it("stops watching once the utterance starts", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hello"));
    const cancelsBefore = synth.cancelCalls;

    realUtterances()[0].onstart!();
    jest.advanceTimersByTime(STALL_WATCHDOG_MS * 3);

    expect(realUtterances()).toHaveLength(1);
    expect(synth.cancelCalls).toBe(cancelsBefore);
    expect(states).not.toContain("failure");
  });

  it("does not fire while the utterance is merely slow to start", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hello"));

    jest.advanceTimersByTime(STALL_WATCHDOG_MS - 1);
    expect(realUtterances()).toHaveLength(1);

    realUtterances()[0].onstart!();
    jest.advanceTimersByTime(STALL_WATCHDOG_MS);
    expect(realUtterances()).toHaveLength(1);
  });

  it("re-speaks the same utterance once when the engine goes silent", () => {
    const nav = makeNavigator();
    const element = makeElement("Hello");
    speakElement(nav, element);
    const original = realUtterances()[0];

    jest.advanceTimersByTime(STALL_WATCHDOG_MS);
    expect(synth.cancelCalls).toBe(1);

    jest.advanceTimersByTime(STALL_RECOVERY_DELAY_MS);
    expect(realUtterances()).toEqual([original, original]);
    expect(states).not.toContain("failure");
  });

  it("recovers even when the engine reports speaking: false", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hello"));
    // The engine dropped the utterance without any event — previously this was
    // a silent give-up that left playback stopped with no state emitted.
    synth.speaking = false;

    jest.advanceTimersByTime(STALL_WATCHDOG_MS + STALL_RECOVERY_DELAY_MS);

    expect(realUtterances()).toHaveLength(2);
  });

  it("keeps waiting instead of recovering while paused", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hello"));
    synth.paused = true;

    jest.advanceTimersByTime(STALL_WATCHDOG_MS * 2);
    expect(realUtterances()).toHaveLength(1);
    expect(synth.cancelCalls).toBe(0);

    synth.paused = false;
    jest.advanceTimersByTime(STALL_WATCHDOG_MS + STALL_RECOVERY_DELAY_MS);
    expect(realUtterances()).toHaveLength(2);
  });

  it("reports failure and resets the engine when recovery also stalls", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hello"));

    jest.advanceTimersByTime(STALL_WATCHDOG_MS + STALL_RECOVERY_DELAY_MS);
    const cancelsAfterRecovery = synth.cancelCalls;
    jest.advanceTimersByTime(STALL_WATCHDOG_MS);

    expect(states).toContain("failure");
    // The reset is what makes a later play() work: a stalled engine keeps
    // reporting speaking: true until something cancels it.
    expect(synth.cancelCalls).toBeGreaterThan(cancelsAfterRecovery);
    expect(synth.speaking).toBe(false);

    jest.advanceTimersByTime(STALL_WATCHDOG_MS * 3);
    expect(states.filter((s) => s === "failure")).toHaveLength(1);
  });

  it("does not re-speak after stop() during the recovery delay", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hello"));

    jest.advanceTimersByTime(STALL_WATCHDOG_MS);
    nav.stop();
    jest.advanceTimersByTime(STALL_RECOVERY_DELAY_MS + STALL_WATCHDOG_MS);

    expect(realUtterances()).toHaveLength(1);
    expect(states).not.toContain("failure");
  });

  it("does not let a superseded utterance's watchdog touch the current one", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("First"));
    jest.advanceTimersByTime(STALL_WATCHDOG_MS - 100);
    speakElement(nav, makeElement("Second"));

    jest.advanceTimersByTime(STALL_WATCHDOG_MS + STALL_RECOVERY_DELAY_MS);

    // Exactly one recovery happened, and it re-spoke the current utterance.
    const spoken = realUtterances();
    expect(spoken).toHaveLength(3);
    expect(spoken[2].text).toBe("Second");
    expect(synth.cancelCalls).toBe(1);
  });
});
