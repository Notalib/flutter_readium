// Peripherals based on XBReader
// copied from readium ts-toolkit test app vanilla

export interface PCallbacks {
  moveTo: (direction: 'left' | 'right' | 'up' | 'down') => void;
  menu: (show?: boolean) => void;
  goProgression: (shiftKey?: boolean) => void;
}

/**
 * True when the key event comes from a form field or contenteditable element, where arrow keys,
 * Space and Enter belong to the user's typing. Uses the event's target (the focused element) and
 * walks into shadow roots, because `document.activeElement` stops at the shadow host.
 */
export function isEditableTarget(e: KeyboardEvent): boolean {
  const target = (e.composedPath?.()[0] ?? e.target) as HTMLElement | null;
  if (!target || typeof target.tagName !== 'string') return false;
  if (target.isContentEditable) return true;
  const tag = target.tagName.toLowerCase();
  return tag === 'input' || tag === 'textarea' || tag === 'select';
}

export default class Peripherals {
  private readonly observers = ['keyup', 'keydown'];
  private targets: EventTarget[] = [];
  private readonly callbacks: PCallbacks;

  constructor(callbacks: PCallbacks) {
    this.observers.forEach((method) => {
      (this as any)['on' + method] = (this as any)['on' + method].bind(this);
    });
    this.callbacks = callbacks;
  }

  destroy() {
    this.targets.forEach((t) => this.unobserve(t));
  }

  unobserve(item: EventTarget) {
    if (!item) return;
    this.observers.forEach((EventName) => {
      item.removeEventListener(
        EventName,
        (this as any)['on' + EventName],
        false
      );
    });
    this.targets = this.targets.filter((t) => t !== item);
  }

  observe(item: EventTarget) {
    if (!item) return;
    if (this.targets.includes(item)) return;
    this.observers.forEach((EventName) => {
      item.addEventListener(EventName, (this as any)['on' + EventName], false);
    });
    this.targets.push(item);
  }

  onkeyup(e: KeyboardEvent) {
    if (isEditableTarget(e)) return;
    if (e.code === 'Space') this.callbacks.goProgression(e.shiftKey);
    if (e.code === 'Enter') this.callbacks.menu(true);
  }

  onkeydown(e: KeyboardEvent) {
    if (isEditableTarget(e)) return;
    switch (e.code) {
      case 'ArrowRight':
        this.callbacks.moveTo('right');
        e.preventDefault();
        break;
      case 'ArrowLeft':
        this.callbacks.moveTo('left');
        e.preventDefault();
        break;
      case 'ArrowUp':
        this.callbacks.moveTo('up');
        e.preventDefault();
        break;
      case 'ArrowDown':
        this.callbacks.moveTo('down');
        e.preventDefault();
        break;
    }
  }
}
