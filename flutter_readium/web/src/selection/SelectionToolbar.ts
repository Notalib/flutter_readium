/**
 * SelectionToolbar — floating buttons for the app's custom selection actions.
 *
 * A browser cannot extend its native context menu, so on web the actions are drawn
 * by the plugin next to the selection. It lives inside the navigator container
 * (a Flutter platform view), so taps reach it without a PointerInterceptor.
 */

import { Locator } from "@readium/shared";
import { SelectionFrame } from "../navigators/navigatorUtils";

export interface SelectionActionConfig {
  id: string;
  title: string;
}

/** Selection geometry in the content frame's viewport (CSS px), as `text_selected` reports it. */
export interface SelectionRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface SelectionToolbarTarget {
  frame: SelectionFrame;
  rect: SelectionRect;
  /** Rebuilds locator and text from the live selection, which may have changed since `show`. */
  resolve: () => { locator: Locator; text: string } | undefined;
}

export interface ToolbarPlacementInput {
  /** Top of the first selected line (container coordinates). */
  anchorTop: number;
  /** Bottom of the last selected line (container coordinates). */
  anchorBottom: number;
  anchorCenterX: number;
  toolbarWidth: number;
  toolbarHeight: number;
  containerWidth: number;
}

const TOOLBAR_CLASS = "flutter-readium-selection-toolbar";
const GAP = 8;
const EDGE = 4;

/** Above the selection, or below it when there is no room; kept inside the container horizontally. */
export function placeToolbar(input: ToolbarPlacementInput): { top: number; left: number } {
  const above = input.anchorTop - input.toolbarHeight - GAP;
  const top = above >= EDGE ? above : input.anchorBottom + GAP;
  const maxLeft = Math.max(EDGE, input.containerWidth - input.toolbarWidth - EDGE);
  const left = Math.min(Math.max(input.anchorCenterX - input.toolbarWidth / 2, EDGE), maxLeft);
  return { top, left };
}

export class SelectionToolbar {
  private _actions: SelectionActionConfig[] = [];
  private _container: HTMLElement | undefined;
  private _element: HTMLElement | undefined;
  private _target: SelectionToolbarTarget | undefined;
  private _removeFrameListeners: (() => void) | undefined;

  constructor(
    private readonly _onAction: (event: {
      actionId: string;
      locator: object;
      selectedText: string;
    }) => void
  ) {}

  /** Sets the element to draw into: the container the navigator renders into. */
  attach(container: HTMLElement): void {
    this.hide();
    this._container = container;
  }

  setActions(actions: SelectionActionConfig[]): void {
    this._actions = actions;
    if (actions.length === 0) this.hide();
  }

  show(target: SelectionToolbarTarget): void {
    const container = this._container;
    if (!container || this._actions.length === 0) return;

    this.hide();
    this._target = target;

    const doc = container.ownerDocument;
    const toolbar = doc.createElement("div");
    toolbar.className = TOOLBAR_CLASS;
    toolbar.setAttribute("role", "toolbar");
    // Keep the selection: a press on a button must not collapse it or move focus.
    toolbar.addEventListener("mousedown", (e) => e.preventDefault());
    toolbar.addEventListener("pointerdown", (e) => e.preventDefault());

    for (const action of this._actions) {
      const button = doc.createElement("button");
      button.type = "button";
      button.textContent = action.title;
      button.addEventListener("click", () => this._activate(action));
      toolbar.appendChild(button);
    }

    // Hidden while measuring so it never flashes at the wrong spot.
    toolbar.style.visibility = "hidden";
    container.appendChild(toolbar);
    this._element = toolbar;
    this._position(toolbar, container, target);
    toolbar.style.visibility = "visible";

    this._listenToFrame(target.frame.window);
  }

  hide(): void {
    this._removeFrameListeners?.();
    this._removeFrameListeners = undefined;
    this._element?.remove();
    this._element = undefined;
    this._target = undefined;
  }

  /** Hides the toolbar and forgets the container (call on closePublication). */
  detach(): void {
    this.hide();
    this._container = undefined;
  }

  private _activate(action: SelectionActionConfig): void {
    const target = this._target;
    const resolved = target?.resolve();
    if (!target || !resolved) {
      this.hide();
      return;
    }
    this._onAction({
      actionId: action.id,
      // serialize() keeps otherLocations Map entries that a plain stringify drops.
      locator: resolved.locator.serialize(),
      selectedText: resolved.text,
    });
    try {
      target.frame.window.getSelection()?.removeAllRanges();
    } catch {
      // The frame may already be gone; the toolbar is hidden either way.
    }
    this.hide();
  }

  private _position(
    toolbar: HTMLElement,
    container: HTMLElement,
    { frame, rect }: SelectionToolbarTarget
  ): void {
    const containerRect = container.getBoundingClientRect();
    const iframeRect = frame.iframe.getBoundingClientRect();
    // A fixed-layout frame is CSS-scaled, so its client rects are not 1:1 with the page.
    const scaleX = frame.iframe.clientWidth ? iframeRect.width / frame.iframe.clientWidth : 1;
    const scaleY = frame.iframe.clientHeight ? iframeRect.height / frame.iframe.clientHeight : 1;

    const firstLineTop = iframeRect.top - containerRect.top + rect.y * scaleY;
    // The selection may span lines; "below" must clear the last one, not just the first.
    const bottom = this._selectionBottom(frame.window);
    const anchorBottom =
      bottom !== undefined
        ? iframeRect.top - containerRect.top + bottom * scaleY
        : firstLineTop + rect.height * scaleY;

    const { top, left } = placeToolbar({
      anchorTop: firstLineTop,
      anchorBottom,
      anchorCenterX: iframeRect.left - containerRect.left + (rect.x + rect.width / 2) * scaleX,
      toolbarWidth: toolbar.offsetWidth,
      toolbarHeight: toolbar.offsetHeight,
      containerWidth: containerRect.width,
    });
    toolbar.style.top = `${top}px`;
    toolbar.style.left = `${left}px`;
  }

  private _selectionBottom(wnd: Window): number | undefined {
    try {
      const selection = wnd.getSelection();
      if (!selection || selection.rangeCount === 0) return undefined;
      return selection.getRangeAt(0).getBoundingClientRect().bottom;
    } catch {
      return undefined;
    }
  }

  private _listenToFrame(wnd: Window): void {
    const hide = () => this.hide();
    const onSelectionChange = () => {
      const selection = wnd.getSelection();
      if (!selection || selection.isCollapsed || selection.toString().length === 0) this.hide();
    };
    const doc = wnd.document;
    doc.addEventListener("selectionchange", onSelectionChange);
    // Capture: scroll events from nested scroll containers do not bubble.
    wnd.addEventListener("scroll", hide, { capture: true, passive: true });
    wnd.addEventListener("resize", hide);
    this._removeFrameListeners = () => {
      doc.removeEventListener("selectionchange", onSelectionChange);
      wnd.removeEventListener("scroll", hide, { capture: true });
      wnd.removeEventListener("resize", hide);
    };
  }
}
