/**
 * Media Overlay `next()` / `previous()` step one cue, keep the play state, move the
 * view even while paused, and leave manual mode in a single, target-first step.
 */
import { Locator } from "@readium/shared";
import { SyncNarrationItem } from "../mediaoverlay/syncNarration";
import { __testing__ } from "../ReadiumReader";

const { ReadiumReader } = __testing__;

function cue(id: string, start: number, end: number, region?: { x: number; y: number; w: number; h: number }): SyncNarrationItem {
  return {
    audio: `a.mp3#t=${start},${end}`,
    text: `p.xhtml#${id}`,
    position: 0,
    audioHref: "a.mp3",
    audioStart: start,
    audioEnd: end,
    textHref: "p.xhtml",
    textId: id,
    region,
  };
}

const ITEMS = [
  cue("c1", 0, 5, { x: 1, y: 1, w: 10, h: 10 }),
  cue("c2", 5, 9, { x: 2, y: 2, w: 20, h: 20 }),
  cue("c3", 9, 14, { x: 3, y: 3, w: 30, h: 30 }),
];

let updateNarrationSync: jest.Mock;
const savedWindow = (globalThis as any).window;

beforeEach(() => {
  updateNarrationSync = jest.fn();
  (globalThis as any).window = { updateNarrationSync };
});

afterEach(() => {
  if (savedWindow === undefined) delete (globalThis as any).window;
  else (globalThis as any).window = savedWindow;
});

function audioNav(time: number, isPlaying: boolean) {
  const nav = {
    currentLocator: Locator.deserialize({
      href: "a.mp3",
      type: "audio/mpeg",
      locations: { fragments: [`t=${time}`] },
    })!,
    currentTime: time,
    isPlaying,
    play: jest.fn(),
    pause: jest.fn(),
    go: jest.fn(async (_locator: Locator, _animated: boolean, cb: (ok: boolean) => void) => cb(true)),
  };
  return nav;
}

function readerWith(nav: ReturnType<typeof audioNav>) {
  const reader = new ReadiumReader() as any;
  reader._audioNav = nav;
  reader._audioNavPublication = { readingOrder: { items: [] } };
  reader._syncItems = ITEMS;
  return reader;
}

/** next()/previous() are fire-and-forget; wait for the queued step. */
const settle = (reader: any): Promise<void> => reader._cueStepChain;
const seekedTo = (nav: ReturnType<typeof audioNav>) => nav.go.mock.calls.map((c) => c[0].locations?.fragments?.[0]);

describe("Media Overlay cue step", () => {
  it("steps to the next cue and keeps a paused navigator paused", async () => {
    const nav = audioNav(1, false);
    const reader = readerWith(nav);
    const visual = { go: jest.fn((_l: Locator, _a: boolean, cb: (ok: boolean) => void) => cb(true)), _cframes: [] };
    reader._nav = visual;

    reader.next();
    await settle(reader);

    expect(seekedTo(nav)).toEqual(["t=5"]);
    expect(nav.play).not.toHaveBeenCalled();
    expect(visual.go).toHaveBeenCalledTimes(1);
    expect(visual.go.mock.calls[0][0].locations?.fragments).toEqual(["c2"]);
    expect(updateNarrationSync).not.toHaveBeenCalled();
  });

  it("previous restarts the cue when more than 2 s in, else goes back", async () => {
    const nav = audioNav(8, false);
    const reader = readerWith(nav);
    reader.previous();
    await settle(reader);
    nav.currentLocator = Locator.deserialize({ href: "a.mp3", type: "audio/mpeg", locations: { fragments: ["t=5"] } })!;
    reader.previous();
    await settle(reader);
    expect(seekedTo(nav)).toEqual(["t=5", "t=0"]);
  });

  it("is a no-op on the last cue", async () => {
    const nav = audioNav(10, true);
    const reader = readerWith(nav);
    reader.next();
    await settle(reader);
    expect(nav.go).not.toHaveBeenCalled();
  });

  it("from manual mode: re-enables sync once and routes only the target cue", async () => {
    const nav = audioNav(1, false);
    const reader = readerWith(nav);
    const visual = { go: jest.fn((_l: Locator, _a: boolean, cb: (ok: boolean) => void) => cb(true)), _cframes: [] };
    reader._nav = visual;
    reader._narrationSyncEnabled = false;
    // The old cue was deferred while sync was off.
    reader._lastDeferredSyncLocator = new Locator({ href: "p.xhtml", type: "text/html" });

    reader.next();
    await settle(reader);

    expect(updateNarrationSync.mock.calls).toEqual([[true]]);
    expect(reader._narrationSyncEnabled).toBe(true);
    expect(visual.go).toHaveBeenCalledTimes(1);
    expect(visual.go.mock.calls[0][0].locations?.fragments).toEqual(["c2"]);

    // The audio navigator's own emission of the same cue must not navigate again.
    reader._routeNarrationCue(visual.go.mock.calls[0][0], "MediaOverlay", 4000);
    expect(visual.go).toHaveBeenCalledTimes(1);
  });

  describe("comic navigator", () => {
    function comic(manuallyOverridden: boolean, onSetAutoPan?: () => void) {
      const calls: string[] = [];
      return {
        calls,
        manuallyOverridden,
        go: jest.fn((_l: Locator, _a: boolean, cb: (ok: boolean) => void) => { calls.push("go"); cb(true); }),
        setAutoPan: jest.fn((_enabled: boolean) => { calls.push("setAutoPan"); onSetAutoPan?.(); }),
        panToRegion: jest.fn((r: unknown) => calls.push(`pan:${(r as { x: number } | null)?.x}`)),
      };
    }

    it("a manual override is cleared by the step: the target panel is the only one framed", async () => {
      const nav = audioNav(1, true);
      const reader = readerWith(nav);
      const divina = comic(true);
      reader._comicNav = divina;
      reader._lastMediaOverlayLocatorKey = "p.xhtml";

      reader.next();
      await settle(reader);

      // Page turn first, then the target region; never the old panel (x: 1).
      expect(divina.calls[0]).toBe("go");
      expect(divina.calls.filter((c: string) => c.startsWith("pan:"))).not.toContain("pan:1");
      expect(divina.calls.indexOf("setAutoPan")).toBeGreaterThan(divina.calls.indexOf("go"));
      expect(divina.calls[divina.calls.length - 1]).toBe("pan:2");
      expect(divina.setAutoPan).toHaveBeenCalledWith(true);
      // The comic navigator emits updateNarrationSync itself; the reader adds no second one.
      expect(updateNarrationSync).not.toHaveBeenCalled();
    });

    it("both reader flag and comic override set: still a single updateNarrationSync(true)", async () => {
      const nav = audioNav(1, true);
      const reader = readerWith(nav);
      // Stand-in for the navigator's own emission when it clears the override.
      const divina = comic(true, () => window.updateNarrationSync?.(true));
      reader._comicNav = divina;
      reader._narrationSyncEnabled = false;

      reader.next();
      await settle(reader);

      expect(updateNarrationSync).toHaveBeenCalledTimes(1);
    });

    it("an in-sync step neither touches auto-pan nor re-turns the page", async () => {
      const nav = audioNav(1, true);
      const reader = readerWith(nav);
      const divina = comic(false);
      reader._comicNav = divina;
      reader._lastMediaOverlayLocatorKey = "p.xhtml";

      reader.next();
      await settle(reader);

      expect(divina.go).not.toHaveBeenCalled();
      expect(divina.setAutoPan).not.toHaveBeenCalled();
      expect(divina.calls).toEqual(["pan:2"]);
    });
  });
});
