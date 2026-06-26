/**
 * Regression tests for EPUBPreferences.fontSize conversion.
 *
 * Prior to the fix, Dart sent fontSize as a percentage int (e.g. 120) and each
 * native platform divided by 100. The API was changed to a double ratio (1.0 =
 * default) forwarded unchanged, so these tests assert the mappers pass the
 * value through without any /100 conversion.
 */

import { epubPreferencesFromJson } from "../preferences/FlutterEpubPreferences";
import { initializeWebPubPreferencesFromString } from "../preferences/FlutterWebPubPreferences";

describe("EPUBPreferences fontSize — forwarded as ratio, not converted", () => {
  it("passes fontSize ratio through epubPreferencesFromJson unchanged", () => {
    const out = epubPreferencesFromJson({ fontSize: 1.5 });
    expect(out.fontSize).toBeCloseTo(1.5);
  });

  it("default ratio 1.0 is preserved", () => {
    const out = epubPreferencesFromJson({ fontSize: 1.0 });
    expect(out.fontSize).toBeCloseTo(1.0);
  });

  it("omitted fontSize produces undefined (not 0 or null)", () => {
    const out = epubPreferencesFromJson({});
    expect(out.fontSize).toBeUndefined();
  });
});

describe("WebPubPreferences fontSize → zoom — forwarded as ratio", () => {
  it("maps fontSize ratio directly to zoom", () => {
    const out = initializeWebPubPreferencesFromString(
      JSON.stringify({ fontSize: 1.2 }),
    );
    expect(out.zoom).toBeCloseTo(1.2);
  });

  it("explicit zoom takes precedence over fontSize", () => {
    const out = initializeWebPubPreferencesFromString(
      JSON.stringify({ fontSize: 1.5, zoom: 2.0 }),
    );
    expect(out.zoom).toBeCloseTo(2.0);
  });

  it("omitted fontSize leaves zoom null/undefined", () => {
    const out = initializeWebPubPreferencesFromString(JSON.stringify({}));
    expect(out.zoom ?? null).toBeNull();
  });
});
