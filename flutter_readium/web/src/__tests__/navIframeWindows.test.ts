import { navIframeWindows } from "../decorations/decorationFrameUtils";

// Mirrors the toolkit FrameManager: `window` throws once the frame is destroyed
// or its iframe has left the document.
function frame(wnd: Window | null) {
  return {
    get window(): Window {
      if (!wnd) throw Error("Trying to use frame window when it doesn't exist");
      return wnd;
    },
  };
}

describe("navIframeWindows", () => {
  it("skips frames whose window getter throws", () => {
    const live = {} as Window;
    const nav = { _cframes: [frame(null), undefined, frame(live)] };

    expect(navIframeWindows(nav as any)).toEqual([live]);
  });
});
