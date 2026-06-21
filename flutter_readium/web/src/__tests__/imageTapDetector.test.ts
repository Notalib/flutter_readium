/**
 * Unit tests for utils/ImageTapDetector.ts → tryBuildImageTapPayload.
 *
 * Exercises the hit-testing branches that can't be reached by the Flutter
 * integration suite (the tapped <img> lives inside a native WebView):
 *   - frame resolution (src match, document.URL match, single-iframe fallback)
 *   - element resolution (cssSelector preferred, dpr-corrected elementFromPoint
 *     fallback)
 *   - the <img> ancestor walk via closest("img")
 *   - href derivation by suffix-matching img.src against the manifest links
 *
 * The test runs under the `node` jest environment (no jsdom), so the Window /
 * Document / Element surfaces the function touches are hand-built mocks.
 */

import { FrameClickEvent } from "@readium/navigator-html-injectables";
import { EpubNavigator, WebPubNavigator } from "@readium/navigator";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { tryBuildImageTapPayload } from "../utils/ImageTapDetector";

// ---------------------------------------------------------------------------
// Mock builders
// ---------------------------------------------------------------------------

interface ImgOpts {
  src?: string;
  alt?: string | null;
  naturalWidth?: number;
  naturalHeight?: number;
  rect?: { x: number; y: number; width: number; height: number };
}

/** A mock <img>: closest("img") returns itself, anything else returns null. */
function makeImg(opts: ImgOpts = {}): Element {
  const img: any = {
    src: opts.src ?? "",
    naturalWidth: opts.naturalWidth ?? 0,
    naturalHeight: opts.naturalHeight ?? 0,
    getBoundingClientRect: () =>
      opts.rect ?? { x: 0, y: 0, width: 0, height: 0 },
    getAttribute: (name: string) =>
      name === "alt" ? (opts.alt ?? null) : null,
  };
  img.closest = (sel: string) => (sel === "img" ? img : null);
  return img as Element;
}

/** A mock non-image element: closest("img") always returns null. */
function makeNonImg(): Element {
  return { closest: () => null } as unknown as Element;
}

interface WindowOpts {
  href?: string;
  url?: string;
  dpr?: number;
  queryResult?: Element | null;
  pointResult?: Element | null;
}

function makeWindow(opts: WindowOpts = {}): Window {
  return {
    location: opts.href !== undefined ? { href: opts.href } : undefined,
    devicePixelRatio: opts.dpr ?? 1,
    document: {
      URL: opts.url,
      querySelector: (_sel: string) => opts.queryResult ?? null,
      elementFromPoint: (_x: number, _y: number) => opts.pointResult ?? null,
    },
  } as unknown as Window;
}

/** Wraps content windows in the `_cframes` shape navIframeWindows reads. */
function makeNav(windows: Window[]): EpubNavigator | WebPubNavigator {
  return {
    _cframes: windows.map((w) => ({ window: w })),
  } as unknown as EpubNavigator | WebPubNavigator;
}

function makePublication(hrefs: string[]): ReadiumPublication {
  return {
    allLinks: hrefs.map((href) => ({ href })),
  } as unknown as ReadiumPublication;
}

function makeEvent(opts: Partial<FrameClickEvent> = {}): FrameClickEvent {
  return {
    defaultPrevented: false,
    doNotDisturb: false,
    interactiveElement: undefined,
    cssSelector: undefined,
    targetElement: "",
    targetFrameSrc: "https://readium/chap1.xhtml",
    x: 0,
    y: 0,
    ...opts,
  };
}

const FRAME_SRC = "https://readium/chap1.xhtml";

// ---------------------------------------------------------------------------
// Happy paths
// ---------------------------------------------------------------------------

describe("tryBuildImageTapPayload — image hit", () => {
  it("builds a full payload from a cssSelector-resolved <img>", () => {
    const img = makeImg({
      src: "https://readium/images/cover.jpg",
      alt: "Cover art",
      naturalWidth: 800,
      naturalHeight: 1200,
      rect: { x: 10, y: 20, width: 100, height: 150 },
    });
    const wnd = makeWindow({ href: FRAME_SRC, queryResult: img });
    const nav = makeNav([wnd]);
    const pub = makePublication(["chap1.xhtml", "images/cover.jpg"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "img.cover" }),
      nav,
      pub
    );

    expect(result).not.toBeNull();
    const payload = JSON.parse(result!);
    expect(payload).toEqual({
      href: "images/cover.jpg",
      alt: "Cover art",
      rect: { x: 10, y: 20, width: 100, height: 150 },
      pixelWidth: 800,
      pixelHeight: 1200,
      srcUrl: "https://readium/images/cover.jpg",
    });
  });

  it("matches the frame by document.URL when location.href is absent", () => {
    const img = makeImg({ src: "https://readium/images/p1.png" });
    const wnd = makeWindow({ url: FRAME_SRC, queryResult: img });
    const nav = makeNav([wnd]);
    const pub = makePublication(["images/p1.png"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "img" }),
      nav,
      pub
    );

    expect(result).not.toBeNull();
    expect(JSON.parse(result!).href).toBe("images/p1.png");
  });

  it("falls back to the sole iframe when the frame src does not match", () => {
    const img = makeImg({ src: "https://readium/images/p2.png" });
    // Window src deliberately differs from the event's targetFrameSrc.
    const wnd = makeWindow({ href: "https://other/frame.xhtml", queryResult: img });
    const nav = makeNav([wnd]);
    const pub = makePublication(["images/p2.png"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "img" }),
      nav,
      pub
    );

    expect(result).not.toBeNull();
    expect(JSON.parse(result!).href).toBe("images/p2.png");
  });

  it("uses dpr-corrected elementFromPoint when no cssSelector is given", () => {
    const img = makeImg({ src: "https://readium/images/p3.png" });
    let calledWith: { x: number; y: number } | null = null;
    const wnd = makeWindow({ href: FRAME_SRC, dpr: 2 });
    // Override elementFromPoint to record the dpr-corrected coordinates.
    (wnd.document as any).elementFromPoint = (x: number, y: number) => {
      calledWith = { x, y };
      return img;
    };
    const nav = makeNav([wnd]);
    const pub = makePublication(["images/p3.png"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, x: 200, y: 400, cssSelector: undefined }),
      nav,
      pub
    );

    expect(result).not.toBeNull();
    // 200/2, 400/2 — Peripherals multiplies by dpr, so we divide it back out.
    expect(calledWith).toEqual({ x: 100, y: 200 });
  });

  it("walks up to the <img> ancestor from a tapped child element", () => {
    const img: any = makeImg({ src: "https://readium/images/p4.png" });
    // Child element whose closest("img") resolves to the img.
    const child = { closest: (sel: string) => (sel === "img" ? img : null) } as unknown as Element;
    const wnd = makeWindow({ href: FRAME_SRC, queryResult: child });
    const nav = makeNav([wnd]);
    const pub = makePublication(["images/p4.png"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "span.inside" }),
      nav,
      pub
    );

    expect(result).not.toBeNull();
    expect(JSON.parse(result!).href).toBe("images/p4.png");
  });

  it("omits alt, dimensions, and srcUrl when unavailable", () => {
    const img = makeImg({ src: "", alt: null, naturalWidth: 0, naturalHeight: 0 });
    const wnd = makeWindow({ href: FRAME_SRC, queryResult: img });
    const nav = makeNav([wnd]);
    const pub = makePublication([]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "img" }),
      nav,
      pub
    );

    expect(result).not.toBeNull();
    const payload = JSON.parse(result!);
    expect(payload.alt).toBeUndefined();
    expect(payload.pixelWidth).toBeUndefined();
    expect(payload.pixelHeight).toBeUndefined();
    expect(payload.srcUrl).toBeUndefined();
    // No src → empty href, but the rect is still emitted.
    expect(payload.href).toBe("");
    expect(payload.rect).toEqual({ x: 0, y: 0, width: 0, height: 0 });
  });
});

// ---------------------------------------------------------------------------
// Non-image / no-op paths → null
// ---------------------------------------------------------------------------

describe("tryBuildImageTapPayload — returns null", () => {
  it("returns null when the tapped element is not an image", () => {
    const wnd = makeWindow({ href: FRAME_SRC, queryResult: makeNonImg() });
    const nav = makeNav([wnd]);
    const pub = makePublication(["chap1.xhtml"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "p" }),
      nav,
      pub
    );

    expect(result).toBeNull();
  });

  it("returns null when no frame matches and there are multiple iframes", () => {
    const wndA = makeWindow({ href: "https://other/a.xhtml" });
    const wndB = makeWindow({ href: "https://other/b.xhtml" });
    const nav = makeNav([wndA, wndB]);
    const pub = makePublication(["chap1.xhtml"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "img" }),
      nav,
      pub
    );

    expect(result).toBeNull();
  });

  it("returns null when the element cannot be resolved at all", () => {
    // No cssSelector match and elementFromPoint returns null.
    const wnd = makeWindow({ href: FRAME_SRC, queryResult: null, pointResult: null });
    const nav = makeNav([wnd]);
    const pub = makePublication(["chap1.xhtml"]);

    const result = tryBuildImageTapPayload(
      makeEvent({ targetFrameSrc: FRAME_SRC, cssSelector: "img.missing" }),
      nav,
      pub
    );

    expect(result).toBeNull();
  });
});
