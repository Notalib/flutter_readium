/**
 * Unit tests for FlutterTTSNavigator: the speechSynthesis stall watchdog, where
 * play() starts, and the utterance language.
 *
 * The stall itself is not reproducible on healthy hardware — measured start
 * latency is 1-500ms for local and Google network voices alike — so these tests
 * drive a fake speechSynthesis to pin down what happens once it does stall.
 */

import { Body, Locator, LocatorText, TextElement, TextSegment } from "@readium/shared";
import { FlutterTTSNavigator } from "../navigators/FlutterTTSNavigator";
import { WebTTSPreferences } from "../preferences/FlutterTTSPreferences";

const STALL_WATCHDOG_MS = 8000;
const STALL_RECOVERY_DELAY_MS = 200;

/** Start locator of every content iterator `play()` created. */
const mockIteratorStarts: (Locator | undefined)[] = [];

jest.mock("@readium/shared", () => {
  const actual = jest.requireActual("@readium/shared");
  return {
    ...actual,
    // An empty publication: play() records where it starts, then ends.
    PublicationContentIterator: jest.fn().mockImplementation((_publication, start) => {
      mockIteratorStarts.push(start);
      return { hasNext: async () => false };
    }),
  };
});

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
  /** Loaded by default; tests of the empty list before `voiceschanged` override it. */
  voices: any[] = [{ name: "Fake", voiceURI: "fake", lang: "xx", localService: true, default: true }];
  getVoices(): any[] {
    return this.voices;
  }
  listeners = new Map<string, () => void>();
  addEventListener(type: string, listener: () => void): void {
    this.listeners.set(type, listener);
  }
  removeEventListener(type: string): void {
    this.listeners.delete(type);
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

function makeNavigator(
  options: {
    initialLocator?: Locator;
    lang?: string;
    utteranceStyle?: object;
    rangeStyle?: object;
    onApplyDecorations?: (group: string, json: string) => void;
  } = {}
): FlutterTTSNavigator {
  const publication = {
    manifest: {
      toc: undefined,
      subcollections: undefined,
      metadata: { languages: ["da"] },
    },
    metadata: { languages: ["da"] },
  };
  const prefs = { rate: 1, pitch: 1, voice: null, lang: options.lang ?? null } as unknown as WebTTSPreferences;
  const nav = new FlutterTTSNavigator(
    { go: jest.fn() } as any,
    publication as any,
    prefs,
    true,
    options.utteranceStyle ?? null,
    options.rangeStyle ?? null,
    options.onApplyDecorations ?? null,
    () => options.initialLocator
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
  mockIteratorStarts.length = 0;
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

describe("play start position", () => {
  const readerPosition = new Locator({ href: "chap3.html", type: "text/html" });

  it("starts at the initial locator when nothing has been spoken", async () => {
    const nav = makeNavigator({ initialLocator: readerPosition });

    await nav.play();

    expect(mockIteratorStarts).toEqual([readerPosition]);
  });

  it("resumes at the current utterance instead of the start of the publication", async () => {
    const nav = makeNavigator({ initialLocator: readerPosition });
    const spoken = makeElement("Hello", "chap5.html");
    (nav as any)._currentElement = spoken;

    await nav.play();

    expect(mockIteratorStarts).toEqual([spoken.locator]);
  });

  it("starts at an explicit locator", async () => {
    const nav = makeNavigator({ initialLocator: readerPosition });
    const target = new Locator({ href: "chap9.html", type: "text/html" });

    await nav.play(target);

    expect(mockIteratorStarts).toEqual([target]);
  });
});

describe("play engine state", () => {
  it("resumes a paused engine, which would otherwise queue utterances silently", async () => {
    const nav = makeNavigator();
    synth.paused = true;

    await nav.play();

    expect(synth.paused).toBe(false);
  });

  it("waits for the voice list before speaking", async () => {
    const nav = makeNavigator();
    synth.voices = [];
    let done = false;

    const playing = nav.play().then(() => (done = true));
    await jest.advanceTimersByTimeAsync(100);
    expect(done).toBe(false);

    synth.voices = [{ name: "Sara", voiceURI: "sara", lang: "da-DK", localService: true, default: false }];
    synth.listeners.get("voiceschanged")!();
    await playing;
    expect(mockIteratorStarts).toHaveLength(1);
  });

  it("does not speak when stopped while waiting for voices", async () => {
    const nav = makeNavigator();
    synth.voices = [];
    const speakNext = jest.spyOn(nav as any, "_speakNext");

    const playing = nav.play();
    nav.stop();
    await jest.advanceTimersByTimeAsync(1000);
    await playing;

    expect(speakNext).not.toHaveBeenCalled();
  });

  it("stays paused when paused while waiting for voices, and starts on resume", async () => {
    const nav = makeNavigator();
    synth.voices = [];
    const speakNext = jest.spyOn(nav as any, "_speakNext");

    const playing = nav.play();
    nav.pause();
    synth.voices = [{ name: "Sara", voiceURI: "sara", lang: "da-DK", localService: true, default: false }];
    synth.listeners.get("voiceschanged")!();
    await playing;
    expect(speakNext).not.toHaveBeenCalled();

    nav.resume();
    expect(speakNext).toHaveBeenCalledTimes(1);
  });
});

describe("play engine priming", () => {
  /** Mirrors Chrome, which reports every utterance as pending once queued. */
  function reportQueuedAsPending(): void {
    const speak = synth.speak.bind(synth);
    synth.speak = (u: FakeUtterance) => {
      speak(u);
      synth.pending = true;
    };
  }

  it("does not cancel its own priming utterance on an idle engine", async () => {
    const nav = makeNavigator();
    reportQueuedAsPending();

    await nav.play();

    expect(synth.spoken.map((u) => u.text)).toEqual([""]);
    expect(synth.cancelCalls).toBe(0);
  });

  it("stops earlier speech before priming", async () => {
    const nav = makeNavigator();
    reportQueuedAsPending();
    synth.speaking = true;
    const order: string[] = [];
    const cancel = synth.cancel.bind(synth);
    synth.cancel = () => {
      order.push("cancel");
      cancel();
    };
    const speak = synth.speak.bind(synth);
    synth.speak = (u: FakeUtterance) => {
      order.push(`speak:${u.text}`);
      speak(u);
    };

    const playing = nav.play();
    await jest.advanceTimersByTimeAsync(50);
    await playing;

    expect(order).toEqual(["cancel", "speak:"]);
  });
});

describe("utterance language", () => {
  it("uses the publication language when no voice is chosen", () => {
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hej"));

    expect(realUtterances()[0].lang).toBe("da");
  });

  it("picks a suitable installed voice for the language", () => {
    synth.getVoices = () => [
      { name: "Albert", voiceURI: "Albert", lang: "da-DK", localService: true, default: false },
      { name: "Sara", voiceURI: "Sara", lang: "da-DK", localService: true, default: false },
    ];
    const nav = makeNavigator();
    speakElement(nav, makeElement("Hej"));

    expect(realUtterances()[0].voice?.name).toBe("Sara");
  });

  it("prefers the language override", () => {
    const nav = makeNavigator({ lang: "nb" });
    speakElement(nav, makeElement("Hei"));

    expect(realUtterances()[0].lang).toBe("nb");
  });
});

describe("word boundaries", () => {
  const rangeStyle = { style: "highlight", tint: "#00000000" };

  function textElement(text: string): TextElement {
    const locator = new Locator({
      href: "chap1.html",
      type: "text/html",
      text: new LocatorText({ highlight: text }),
    });
    return new TextElement(locator, Body, [new TextSegment(locator, text)]);
  }

  /** Speaks `text`, fires `events` and returns the `tts_range` decorations applied. */
  function rangesFor(
    text: string,
    utteranceStyle?: object,
    events = [{ name: "word", charIndex: text.indexOf(" ") + 1, charLength: 0 }]
  ): any[] {
    const ranges: any[] = [];
    const nav = makeNavigator({
      utteranceStyle,
      rangeStyle,
      onApplyDecorations: (group, json) => {
        if (group === "tts_range") ranges.push(...JSON.parse(json));
      },
    });
    speakElement(nav, textElement(text));
    const utterance = realUtterances()[0];
    utterance.onstart!();
    for (const ev of events) utterance.onboundary!(ev);
    return ranges;
  }

  it("decorates the spoken word, not its segment", () => {
    const [range] = rangesFor("Hello brave world", { style: "highlight" });

    expect(range.locator.text.highlight).toBe("brave");
    expect(range.style).toEqual(rangeStyle);
  });

  it("decorates a one-word utterance when only words are decorated", () => {
    expect(rangesFor(" Prologue")).toHaveLength(1);
  });

  it("does not decorate a sentence that spans the whole utterance", () => {
    expect(rangesFor("Hello brave world", undefined, [{ name: "sentence", charIndex: 0, charLength: 0 }])).toEqual([]);
  });

  it("decorates the word right after a sentence boundary", () => {
    const ranges = rangesFor("Hello brave world", undefined, [
      { name: "sentence", charIndex: 0, charLength: 0 },
      { name: "word", charIndex: 0, charLength: 5 },
    ]);

    expect(ranges.map((r) => r.locator.text.highlight)).toEqual(["Hello"]);
  });

  it("decorates every word, however fast they arrive", () => {
    const ranges = rangesFor("in a box", undefined, [
      { name: "word", charIndex: 0, charLength: 2 },
      { name: "word", charIndex: 3, charLength: 1 },
      { name: "word", charIndex: 5, charLength: 3 },
    ]);

    expect(ranges.map((r) => r.locator.text.highlight)).toEqual(["in", "a", "box"]);
  });

  it("keeps the word highlight when a sentence boundary follows a word", () => {
    const text = "Hello brave";
    const locator = new Locator({ href: "chap1.html", type: "text/html", text: new LocatorText({ highlight: text }) });
    const segment = (t: string) =>
      new TextSegment(new Locator({ href: "chap1.html", type: "text/html", text: new LocatorText({ highlight: t.trim() }) }), t);
    const ranges: any[] = [];
    const nav = makeNavigator({
      rangeStyle,
      onApplyDecorations: (group, json) => {
        if (group === "tts_range") ranges.push(...JSON.parse(json));
      },
    });
    speakElement(nav, new TextElement(locator, Body, [segment("Hello "), segment("brave")]));
    const utterance = realUtterances()[0];
    utterance.onstart!();
    utterance.onboundary!({ name: "word", charIndex: 0, charLength: 5 });
    utterance.onboundary!({ name: "sentence", charIndex: 6, charLength: 0 });

    expect(ranges.map((r) => r.locator.text.highlight)).toEqual(["Hello"]);
  });
});
