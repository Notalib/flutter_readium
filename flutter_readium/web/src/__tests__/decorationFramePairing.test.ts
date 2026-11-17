/** @jest-environment jsdom */
import {
  injectDecorationOverrides,
  setSpotlightGroupOnIframes,
  clearSpotlightState,
} from "../decorations/decorationFrameUtils";

type Frame = { wnd: Window; send: (group: string, action: string, tint?: string) => void };

/**
 * An iframe window with a stand-in for upstream's Decorator: it numbers groups in
 * first-message order and creates `<style id="readium-decoration-N-style">` on the
 * first `add` of a group, both inside the same message dispatch like upstream.
 * The stand-in registers first, as upstream's Comms does before the plugin injects.
 */
function makeFrame(opts: { inject?: boolean } = {}): Frame {
  const iframe = document.createElement("iframe");
  document.body.appendChild(iframe);
  const wnd = iframe.contentWindow!;

  const ids = new Map<string, number>();
  wnd.addEventListener("message", (e: MessageEvent) => {
    const msg = e.data;
    if (msg?.key !== "decorate") return;
    const { group, action } = msg.data;
    if (!ids.has(group)) ids.set(group, ids.size);
    const id = `readium-decoration-${ids.get(group)}`;
    if (action === "add" && !wnd.document.getElementById(`${id}-style`)) {
      const style = wnd.document.createElement("style");
      style.id = `${id}-style`;
      wnd.document.head.appendChild(style);
    }
  });

  if (opts.inject !== false) injectDecorationOverrides(wnd);

  return {
    wnd,
    send: (group, action, tint) =>
      wnd.dispatchEvent(
        new (wnd as any).MessageEvent("message", {
          data: {
            _readium: 2,
            key: "decorate",
            data: { group, action, decoration: tint ? { id: "d", style: { tint } } : undefined },
          },
        })
      ),
  };
}

function groupIds(wnd: Window): Record<string, string> {
  const state = (wnd as any).__flutterReadiumDecorationState;
  return Object.fromEntries(state.groupInternalId);
}

describe("decoration group pairing", () => {
  afterEach(() => {
    clearSpotlightState();
    document.body.innerHTML = "";
  });

  it("pairs a group with the style its own add created", () => {
    const { wnd, send } = makeFrame();

    send("notes", "add", "#ff0000ff");

    expect(groupIds(wnd)).toEqual({ notes: "readium-decoration-0" });
  });

  it("does not depend on the order groups are first mentioned in", () => {
    const { wnd, send } = makeFrame();

    // "a" is numbered first (by its clear) but only "b" gets a style first.
    send("a", "clear");
    send("b", "add", "#00ff00ff");
    send("a", "add", "#ff0000ff");

    expect(groupIds(wnd)).toEqual({
      b: "readium-decoration-1",
      a: "readium-decoration-0",
    });
  });

  it("keeps the pairing when a group is re-applied", () => {
    const { wnd, send } = makeFrame();
    send("notes", "add", "#ff0000ff");

    send("notes", "clear");
    send("notes", "add", "#ff0000ff");

    expect(groupIds(wnd)).toEqual({ notes: "readium-decoration-0" });
  });

  it("pairs per frame: a frame that only gets some groups numbers them itself", () => {
    const first = makeFrame();
    const second = makeFrame();

    first.send("a", "add", "#ff0000ff");
    first.send("b", "add", "#00ff00ff");
    // The second page of a spread holds only decorations for "b".
    second.send("b", "add", "#00ff00ff");

    expect(groupIds(first.wnd)).toEqual({
      a: "readium-decoration-0",
      b: "readium-decoration-1",
    });
    expect(groupIds(second.wnd)).toEqual({ b: "readium-decoration-0" });
  });

  it("pairs a frame loaded after decorations were applied, in upstream's reapply order", () => {
    const late = makeFrame();

    // Reapply order is the navigator's map order, not the order the app applied groups in.
    late.send("b", "clear");
    late.send("b", "add", "#00ff00ff");
    late.send("a", "clear");
    late.send("a", "add", "#ff0000ff");

    expect(groupIds(late.wnd)).toEqual({
      b: "readium-decoration-0",
      a: "readium-decoration-1",
    });
  });

  it("leaves styles that predate injection unpaired instead of guessing", () => {
    const { wnd, send } = makeFrame({ inject: false });
    send("early", "add", "#ff0000ff");
    injectDecorationOverrides(wnd);

    send("late", "add", "#00ff00ff");

    expect(groupIds(wnd)).toEqual({ late: "readium-decoration-1" });
  });

  it("restores spotlit text through the spotlight group's paired id, whenever it is paired", () => {
    const { wnd, send } = makeFrame();

    setSpotlightGroupOnIframes([wnd], "tts__spotlight", true);
    send("other", "add", "#00ff00ff");
    send("tts__spotlight", "add", "#ff0000ff");

    const css = wnd.document.getElementById("flutter-readium-spotlight-style")!.textContent!;
    expect(css).toContain("::highlight(readium-decoration-1)");
    expect(css).not.toContain("::highlight(readium-decoration-0)");
  });
});
