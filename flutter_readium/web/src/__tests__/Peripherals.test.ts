/**
 * Unit tests for utils/Peripherals.ts.
 *
 * Covers: reader keyboard shortcuts must not fire while the user types in a
 * form field or contenteditable element (isEditableTarget + the key handlers).
 *
 * Runs under the `node` jest environment, so key events are hand-built mocks.
 */

import Peripherals, { isEditableTarget } from "../utils/Peripherals";

interface TargetOpts {
  tagName: string;
  isContentEditable?: boolean;
}

function keyEvent(
  code: string,
  target?: TargetOpts,
): KeyboardEvent & { preventDefault: jest.Mock } {
  return {
    code,
    shiftKey: false,
    target,
    composedPath: () => (target ? [target] : []),
    preventDefault: jest.fn(),
  } as unknown as KeyboardEvent & { preventDefault: jest.Mock };
}

function makePeripherals() {
  const callbacks = { moveTo: jest.fn(), menu: jest.fn(), goProgression: jest.fn() };
  return { callbacks, peripherals: new Peripherals(callbacks) };
}

describe("isEditableTarget", () => {
  it.each(["INPUT", "TEXTAREA", "SELECT"])("is true for <%s>", (tagName) => {
    expect(isEditableTarget(keyEvent("ArrowLeft", { tagName }))).toBe(true);
  });

  it("is true for a contenteditable element", () => {
    expect(
      isEditableTarget(keyEvent("ArrowLeft", { tagName: "DIV", isContentEditable: true })),
    ).toBe(true);
  });

  it("is false for non-editable elements such as <body>", () => {
    expect(isEditableTarget(keyEvent("ArrowLeft", { tagName: "BODY" }))).toBe(false);
  });

  it("is false when the event has no target", () => {
    expect(isEditableTarget(keyEvent("ArrowLeft"))).toBe(false);
  });
});

describe("Peripherals key handling", () => {
  it("navigates on arrow keys when focus is on the page", () => {
    const { callbacks, peripherals } = makePeripherals();
    const e = keyEvent("ArrowRight", { tagName: "BODY" });
    peripherals.onkeydown(e);
    expect(callbacks.moveTo).toHaveBeenCalledWith("right");
    expect(e.preventDefault).toHaveBeenCalled();
  });

  it("ignores arrow keys typed in an input", () => {
    const { callbacks, peripherals } = makePeripherals();
    const e = keyEvent("ArrowRight", { tagName: "INPUT" });
    peripherals.onkeydown(e);
    expect(callbacks.moveTo).not.toHaveBeenCalled();
    expect(e.preventDefault).not.toHaveBeenCalled();
  });

  it("ignores Space and Enter typed in a textarea", () => {
    const { callbacks, peripherals } = makePeripherals();
    peripherals.onkeyup(keyEvent("Space", { tagName: "TEXTAREA" }));
    peripherals.onkeyup(keyEvent("Enter", { tagName: "TEXTAREA" }));
    expect(callbacks.goProgression).not.toHaveBeenCalled();
    expect(callbacks.menu).not.toHaveBeenCalled();
  });

  it("still handles Space and Enter on the page", () => {
    const { callbacks, peripherals } = makePeripherals();
    peripherals.onkeyup(keyEvent("Space", { tagName: "BODY" }));
    peripherals.onkeyup(keyEvent("Enter", { tagName: "BODY" }));
    expect(callbacks.goProgression).toHaveBeenCalledWith(false);
    expect(callbacks.menu).toHaveBeenCalledWith(true);
  });
});
