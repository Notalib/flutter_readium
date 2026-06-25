/**
 * Unit tests for the audio-driven comic auto-pan gating rule.
 */

import { shouldAutoPan } from "../navigators/comicAutoPan";

describe("shouldAutoPan", () => {
  it("drives auto-pan when enabled and not manually overridden", () => {
    expect(shouldAutoPan({ autoPanEnabled: true, manuallyOverridden: false })).toBe(true);
  });

  it("does not drive auto-pan when disabled", () => {
    expect(shouldAutoPan({ autoPanEnabled: false, manuallyOverridden: false })).toBe(false);
  });

  it("does not drive auto-pan while manually overridden", () => {
    expect(shouldAutoPan({ autoPanEnabled: true, manuallyOverridden: true })).toBe(false);
  });

  it("stays off when both disabled and overridden", () => {
    expect(shouldAutoPan({ autoPanEnabled: false, manuallyOverridden: true })).toBe(false);
  });
});
