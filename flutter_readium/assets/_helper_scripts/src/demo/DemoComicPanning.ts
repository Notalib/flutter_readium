import { css, html, LitElement, nothing, TemplateResult } from 'lit';
import { customElement, property, query } from 'lit/decorators.js';
import { classMap } from 'lit/directives/class-map.js';

@customElement('demo-comic-panning')
export class DemoComicPanning extends LitElement {
  @property()
  private _books = ['text-book', 'comic-panning-figure', 'xkcd'];

  @property()
  public selectedBook?: string;

  get #canGoBack() {
    return this.navIndex > 0;
  }

  get #canGoForward() {
    return this.navIndex + 1 < this.#navLength;
  }

  get #navLength() {
    return this.mediaOverlay?.narration?.[0]?.narration?.length ?? 0;
  }

  get #narrationItem(): MediaOverlayNarrationNode | undefined {
    return this.mediaOverlay?.narration?.[0]?.narration[this.navIndex];
  }

  #iframeLoaded = false;

  @query('#iframe-content-viewer')
  public iframe?: HTMLIFrameElement;

  @property()
  public mediaOverlay?: MediaOverlay;

  @property()
  public navIndex = 0;

  @property()
  public blackAndWhiteModeEnabled = false;

  #buttonControlClasses(enabled: boolean) {
    return classMap({
      disabled: !enabled,
    });
  }

  #iframeClasses() {
    return classMap({
      loaded: this.#iframeLoaded && !!this.mediaOverlay,
    });
  }

  #renderBook(): TemplateResult | typeof nothing {
    if (!this.selectedBook) {
      return nothing;
    }

    return html`<iframe
      id="iframe-content-viewer"
      @load="${this.#iframeOnLoadEvent}"
      src="/books/${this.selectedBook}/index.html"
      class="${this.#iframeClasses()}"
    ></iframe>`;
  }

  #renderControlButton(click: (e: Event) => void, isEnabled: boolean, label: string): TemplateResult {
    return html` <button @click="${click}" class="${this.#buttonControlClasses(isEnabled)}" ?disabled="${!isEnabled}">${label}</button> `;
  }

  #renderControls(): TemplateResult | typeof nothing {
    if (!this.selectedBook) {
      return nothing;
    }

    return html`
      <div class="book-controls">
        ${this.#renderControlButton(this.#prevSegmentEvent, this.#canGoBack, 'PREV')}
        <div class="nav-idx"><span>${this.navIndex + 1} / ${this.#navLength}</span></div>
        ${this.#renderControlButton(this.#nextSegmentEvent, this.#canGoForward, 'NEXT')}
      </div>
    `;
  }

  protected render(): TemplateResult {
    return html`
      <header class="book-selector">${this._books.map((book) => html`<button data-book="${book}" @click="${this.#selectBookEvent}">${book}</button>`)}</header>

      ${this.#renderControls()}

      <section class="content-viewer">${this.#renderBook()}</section>

      <footer>
        DEMO
        <button
          class="${classMap({
      hidden: !this.selectedBook,
      'bw-active': this.blackAndWhiteModeEnabled,
    })}"
          @click=${this.#enableBlackAndWhite}
        >
          Black & white
        </button>
      </footer>
    `;
  }

  readonly #prevSegmentEvent = () => {
    if (this.navIndex > 0) {
      this.navIndex -= 1;
    }

    this.#updateNarration();
  };

  readonly #nextSegmentEvent = () => {
    this.navIndex = Math.min(this.#navLength - 1, this.navIndex + 1);

    this.#updateNarration();
  };

  #updateNarration() {
    const item = this.#narrationItem;
    const iframe = this.iframe;

    if (item && iframe) {
      const { audio, text } = item;
      const audioUrl = new URL(`/books/${this.selectedBook}/${audio.replace('#', '?')}`, window.location.href);
      const textUrl = new URL(`/books/${this.selectedBook}/${text}`, window.location.href);

      const duration = audioUrl.searchParams
        ?.get('t')
        ?.split(',')
        ?.map((p) => parseFloat(p))
        ?.reverse()
        ?.reduce((p, v) => p + v, 0) ?? 0;

      iframe.contentWindow?.gotoComicFrame?.(textUrl.hash, duration * 1000);
    }

    this.requestUpdate();
  }

  readonly #enableBlackAndWhite = () => {
    const enabled = !this.blackAndWhiteModeEnabled;
    this.iframe?.contentWindow?.readium?.setCSSProperties?.({ "--FLUTTER_READIUM-black-white-comic-mode": enabled ? '1' : '' });
    this.blackAndWhiteModeEnabled = enabled;
  };

  readonly #selectBookEvent = async (e: MouseEvent) => {
    this.#iframeLoaded = false;
    this.mediaOverlay = undefined;
    this.navIndex = 0;

    this.selectedBook = (e.target as HTMLButtonElement).dataset.book;

    this.requestUpdate();

    this.mediaOverlay = await fetch(`/books/${this.selectedBook}/media-overlay.json`)
      .then((r) => r.json())
      .then((j) => j as MediaOverlay);

    this.requestUpdate();
  };

  #iframeOnLoadEvent = (e: Event) => {
    const iframe = e.target as HTMLIFrameElement;
    const contentDocument = iframe.contentDocument;
    if (!contentDocument) {
      return;
    }

    const flutterReadiumScript = contentDocument.createElement('script');
    flutterReadiumScript.async = false;
    flutterReadiumScript.src = `/flutterReadiumTools.js?r=${Date.now()}`;
    flutterReadiumScript.onload = () => {
      this.#updateNarration();
      this.#iframeLoaded = true;
    };
    contentDocument.head.appendChild(flutterReadiumScript);

    const flutterReadiumCssLink = contentDocument.createElement('link');
    flutterReadiumCssLink.href = `/flutterReadiumTools.css?r=${Date.now()}`;
    flutterReadiumCssLink.type = 'text/css';
    flutterReadiumCssLink.rel = 'stylesheet';
    contentDocument.head.appendChild(flutterReadiumCssLink);
  };

  // Define scoped styles right with your component, in plain CSS
  static styles = css`
    :host {
      display: flex;
      flex-direction: column;
      height: 100vh;
    }

    .book-selector,
    .book-controls {
      display: flex;
      flex-direction: row;
      background-color: blue;
      justify-content: center;
    }

    .book-controls > .nav-idx {
      margin: 0 2em;
    }

    .book-controls > .nav-idx > span {
      display: inline-block;
      vertical-align: middle;
      line-height: normal;
      color: white;
      font-weight: bolder;
    }

    button {
      cursor: pointer;
    }

    button[disabled],
    button.disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .content-viewer,
    .placeholder {
      flex-grow: 1;
      flex-shrink: 0;
    }

    .content-viewer {
      overflow: hidden;
    }

    .content-viewer iframe {
      border: 0;
      padding: 0;
      margin: 0 auto;
      height: 100%;
      width: 100vw;
      opacity: 0;
    }

    .content-viewer iframe.loaded {
      opacity: 1;
    }

    footer {
      background-color: yellow;
      display: block;
      text-align: center;
      justify-content: flex-end;

      > button {
        cursor: pointer;
        --border-color: black;
        --background-color: white;
        --color: black;

        border: 1px solid var(--border-color);
        background-color: var(--background-color);
        color: var(--color);

        &.hidden {
          display: none;
        }

        &.bw-active {
          --border-color: white;
          --background-color: black;
          --color: white;
        }
      }
    }
  `;
}

export interface MediaOverlay {
  role: string;
  narration: MediaOverlayNarration[];
}

export interface MediaOverlayNarration {
  narration: MediaOverlayNarrationNode[];
}

export interface MediaOverlayNarrationNode {
  text: string;
  audio: string;
}
