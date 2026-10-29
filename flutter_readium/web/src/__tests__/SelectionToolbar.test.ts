/** @jest-environment jsdom */
import { Locator, LocatorText } from "@readium/shared";
import { SelectionToolbar, placeToolbar } from "../selection/SelectionToolbar";

const locator = new Locator({
  href: "ch1.xhtml",
  type: "application/xhtml+xml",
  text: new LocatorText({ highlight: "word", before: "a ", after: " b" }),
});

function setup() {
  const container = document.createElement("div");
  document.body.appendChild(container);
  const iframe = document.createElement("iframe");
  container.appendChild(iframe);
  const wnd = iframe.contentWindow!;
  wnd.document.body.textContent = "a word b";

  const onAction = jest.fn();
  const toolbar = new SelectionToolbar(onAction);
  toolbar.attach(container);
  toolbar.setActions([
    { id: "note", title: "Add note" },
    { id: "share", title: "Share" },
  ]);

  const select = () => {
    const range = wnd.document.createRange();
    range.selectNodeContents(wnd.document.body);
    wnd.getSelection()!.removeAllRanges();
    wnd.getSelection()!.addRange(range);
  };
  select();

  const show = () =>
    toolbar.show({
      frame: { window: wnd, iframe },
      rect: { x: 10, y: 40, width: 30, height: 12 },
      resolve: () => ({ locator, text: "word" }),
    });

  return { container, wnd, toolbar, onAction, show };
}

const buttons = (container: HTMLElement) =>
  Array.from(container.querySelectorAll<HTMLButtonElement>(".flutter-readium-selection-toolbar button"));

describe("SelectionToolbar", () => {
  afterEach(() => {
    document.body.innerHTML = "";
  });

  it("shows one button per configured action", () => {
    const { container, show } = setup();

    show();

    expect(buttons(container).map((b) => b.textContent)).toEqual(["Add note", "Share"]);
    expect(buttons(container).every((b) => b.type === "button")).toBe(true);
    expect(container.querySelector("[role=toolbar]")).not.toBeNull();
  });

  it("shows nothing without actions or before attach", () => {
    const { container, toolbar, show } = setup();
    toolbar.setActions([]);
    show();
    expect(buttons(container)).toHaveLength(0);

    const detached = new SelectionToolbar(jest.fn());
    detached.setActions([{ id: "a", title: "A" }]);
    detached.show({
      frame: { window, iframe: document.createElement("iframe") },
      rect: { x: 0, y: 0, width: 1, height: 1 },
      resolve: () => undefined,
    });
    expect(document.querySelector(".flutter-readium-selection-toolbar")).toBeNull();
  });

  it("emits the action with the resolved locator and text, then clears the selection and hides", () => {
    const { container, wnd, onAction, show } = setup();
    show();

    buttons(container)[1].click();

    expect(onAction).toHaveBeenCalledWith({
      actionId: "share",
      locator: locator.serialize(),
      selectedText: "word",
    });
    expect(wnd.getSelection()!.isCollapsed).toBe(true);
    expect(buttons(container)).toHaveLength(0);
  });

  it("keeps the selection when a button is pressed", () => {
    const { container, show } = setup();
    show();
    const toolbar = container.querySelector(".flutter-readium-selection-toolbar")!;

    const mouse = new MouseEvent("mousedown", { bubbles: true, cancelable: true });
    const pointer = new MouseEvent("pointerdown", { bubbles: true, cancelable: true });
    buttons(container)[0].dispatchEvent(mouse);
    buttons(container)[0].dispatchEvent(pointer);

    expect(toolbar).not.toBeNull();
    expect(mouse.defaultPrevented).toBe(true);
    expect(pointer.defaultPrevented).toBe(true);
  });

  it("hides when the selection collapses", () => {
    const { container, wnd, show } = setup();
    show();

    wnd.getSelection()!.removeAllRanges();
    wnd.document.dispatchEvent(new Event("selectionchange"));

    expect(buttons(container)).toHaveLength(0);
  });

  it("stays while the selection is still there", () => {
    const { container, wnd, show } = setup();
    show();

    wnd.document.dispatchEvent(new Event("selectionchange"));

    expect(buttons(container)).toHaveLength(2);
  });

  it("hides on scroll and on an explicit hide", () => {
    const { container, wnd, toolbar, show } = setup();

    show();
    wnd.dispatchEvent(new Event("scroll"));
    expect(buttons(container)).toHaveLength(0);

    show();
    toolbar.hide();
    expect(buttons(container)).toHaveLength(0);
  });

  it("replaces the previous toolbar on a new selection", () => {
    const { container, show } = setup();

    show();
    show();

    expect(container.querySelectorAll(".flutter-readium-selection-toolbar")).toHaveLength(1);
  });

  it("hides and forgets the container on detach", () => {
    const { container, toolbar, show } = setup();
    show();

    toolbar.detach();
    show();

    expect(buttons(container)).toHaveLength(0);
  });

  it("does not emit when the selection is gone by click time", () => {
    const { container, onAction, toolbar, wnd } = setup();
    toolbar.show({
      frame: { window: wnd, iframe: container.querySelector("iframe")! },
      rect: { x: 0, y: 0, width: 1, height: 1 },
      resolve: () => undefined,
    });

    buttons(container)[0].click();

    expect(onAction).not.toHaveBeenCalled();
    expect(buttons(container)).toHaveLength(0);
  });
});

describe("placeToolbar", () => {
  const base = {
    anchorTop: 100,
    anchorBottom: 140,
    anchorCenterX: 200,
    toolbarWidth: 100,
    toolbarHeight: 30,
    containerWidth: 400,
  };

  it("sits above the first line when there is room", () => {
    expect(placeToolbar(base)).toEqual({ top: 100 - 30 - 8, left: 150 });
  });

  it("goes below the last line when there is no room above", () => {
    expect(placeToolbar({ ...base, anchorTop: 10 }).top).toBe(140 + 8);
  });

  it("stays inside the container horizontally", () => {
    expect(placeToolbar({ ...base, anchorCenterX: 5 }).left).toBe(4);
    expect(placeToolbar({ ...base, anchorCenterX: 399 }).left).toBe(400 - 100 - 4);
  });
});
