/**
 * Unit tests for pure helpers in helpers.ts.
 *
 * Covers: dartColorToCss — the #AARRGGBB → #RRGGBBAA conversion used when
 * translating Dart Color values into CSS colour strings for decorations.
 */

import { dartColorToCss } from "../helpers";

describe("dartColorToCss", () => {
  // ── Normal 8-digit hex ──────────────────────────────────────────────────

  it("converts fully opaque black (#ff000000) to CSS #000000ff", () => {
    // Dart Color(0xFF000000) → '#ff000000'; CSS expects '#000000ff'
    expect(dartColorToCss("#ff000000")).toBe("#000000ff");
  });

  it("converts fully opaque white (#ffffffff) to CSS #ffffffff", () => {
    // Both representations happen to be identical for fully-opaque white.
    expect(dartColorToCss("#ffffffff")).toBe("#ffffffff");
  });

  it("converts transparent white (#00ffffff) to CSS #ffffff00", () => {
    expect(dartColorToCss("#00ffffff")).toBe("#ffffff00");
  });

  it("converts a typical semi-transparent highlight (#66ff9fff) to CSS form", () => {
    // Dart: AA=0x66, RR=0xff, GG=0x9f, BB=0xff
    // CSS:  #ff9fff66
    expect(dartColorToCss("#66ff9fff")).toBe("#ff9fff66");
  });

  it("converts alpha-only-zero (#00000000) to CSS #00000000", () => {
    expect(dartColorToCss("#00000000")).toBe("#00000000");
  });

  it("moves the leading AA bytes to the trailing position correctly", () => {
    // Dart: #aabbccdd → AA=aa, RR=bb, GG=cc, BB=dd → CSS: #bbccddaa
    expect(dartColorToCss("#aabbccdd")).toBe("#bbccddaa");
  });

  it("handles uppercase hex digits", () => {
    expect(dartColorToCss("#FFAABBCC")).toBe("#AABBCCFF");
  });

  it("handles mixed-case hex digits", () => {
    expect(dartColorToCss("#FfAaBbCc")).toBe("#AaBbCcFf");
  });

  // ── Non-8-digit inputs (returned unchanged) ─────────────────────────────

  it("returns a 6-digit CSS colour (#RRGGBB) unchanged", () => {
    expect(dartColorToCss("#aabbcc")).toBe("#aabbcc");
  });

  it("returns a 3-digit CSS colour (#RGB) unchanged", () => {
    expect(dartColorToCss("#abc")).toBe("#abc");
  });

  it("returns a named colour unchanged", () => {
    expect(dartColorToCss("red")).toBe("red");
  });

  it("returns an empty string unchanged", () => {
    expect(dartColorToCss("")).toBe("");
  });

  it("returns a 9-digit string unchanged (one digit too many)", () => {
    expect(dartColorToCss("#aabbccdd1")).toBe("#aabbccdd1");
  });

  it("returns a 7-digit string unchanged (not 8 hex digits after #)", () => {
    expect(dartColorToCss("#aabbccd")).toBe("#aabbccd");
  });

  it("returns an 8-digit string that starts without # unchanged", () => {
    // No leading '#' → not matched by the regex
    expect(dartColorToCss("aabbccdd")).toBe("aabbccdd");
  });

  it("returns a string with non-hex characters unchanged", () => {
    expect(dartColorToCss("#gghhiijj")).toBe("#gghhiijj");
  });
});
