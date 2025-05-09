import { css, html, LitElement, nothing, TemplateResult } from 'lit';
import { customElement, property, query } from 'lit/decorators';
import { classMap } from 'lit/directives/class-map';

@customElement('demo-comic-panning')
export class DemoComicPanning extends LitElement {
  @property()
  private _books = ['text-book', 'comic-panning', 'comic-panning-figure', 'xkcd'];

  @property()
  private _selectedBook?: string;

  private get _canGoBack() {
    return this._navIdx > 0;
  }

  private get _canGoForward() {
    return this._navIdx + 1 < this._navLength;
  }

  private get _navLength() {
    return this.mediaOverlay?.narration?.[0]?.narration?.length ?? 0;
  }

  private get _narrationItem(): MediaOverlayNarrationNode {
    return this.mediaOverlay?.narration?.[0]?.narration[this._navIdx];
  }

  private _iframeLoaded = false;

  @query('#iframe-content-viewer')
  public iframe?: HTMLIFrameElement;

  @property()
  public mediaOverlay?: MediaOverlay;

  @property()
  private _navIdx = 0;

  @property()
  private _blackAndWhiteEnabled = false;

  private _buttonControlClasses(enabled: boolean) {
    return classMap({
      disabled: !enabled,
    });
  }

  private _iframeClasses() {
    return classMap({
      loaded: this._iframeLoaded && !!this.mediaOverlay,
    });
  }

  protected _renderBook(): TemplateResult | typeof nothing {
    if (!this._selectedBook) {
      return nothing;
    }

    return html`<iframe
      id="iframe-content-viewer"
      @load="${this._iframeOnLoadEvent}"
      src="/books/${this._selectedBook}/index.html"
      class="${this._iframeClasses()}"
    ></iframe>`;
  }

  protected _renderControlButton(click: (e: Event) => void, isEnabled: boolean, label: string): TemplateResult {
    return html` <button @click="${click}" class="${this._buttonControlClasses(isEnabled)}" ?disabled="${!isEnabled}">${label}</button> `;
  }

  protected _renderControls(): TemplateResult | typeof nothing {
    if (!this._selectedBook) {
      return nothing;
    }

    return html`
      <div class="book-controls">
        ${this._renderControlButton(this.prevSegmentEvent, this._canGoBack, 'PREV')}
        <div class="nav-idx"><span>${this._navIdx + 1} / ${this._navLength}</span></div>
        ${this._renderControlButton(this._nextSegmentEvent, this._canGoForward, 'NEXT')}
      </div>
    `;
  }

  protected render(): TemplateResult {
    return html`
      <header class="book-selector">${this._books.map((book) => html`<button data-book="${book}" @click="${this.selectBookEvent}">${book}</button>`)}</header>

      ${this._renderControls()}

      <section class="content-viewer">${this._renderBook()}</section>

      <footer>
        DEMO
        <button
          class="${classMap({
            hidden: !this._selectedBook,
            'bw-active': this._blackAndWhiteEnabled,
          })}"
          @click=${this._enableBlackAndWhite}
        >
          Black & white
        </button>
      </footer>
    `;
  }

  private readonly prevSegmentEvent = () => {
    if (this._navIdx > 0) {
      this._navIdx -= 1;
    }

    this._updateNarration();
  };

  private readonly _nextSegmentEvent = () => {
    this._navIdx = Math.min(this._navLength - 1, this._navIdx + 1);

    this._updateNarration();
  };

  private _updateNarration() {
    const item = this._narrationItem;
    const iframe = this.iframe;

    if (item && iframe) {
      const { audio, text } = item;
      const audioUrl = new URL(`/books/${this._selectedBook}/${audio.replace('#', '?')}`, window.location.href);
      const textUrl = new URL(`/books/${this._selectedBook}/${text}`, window.location.href);

      const duration = audioUrl.searchParams
        .get('t')
        .split(',')
        .map((p) => parseFloat(p))
        .reverse()
        .reduce((p, v) => p + v, 0);

      iframe.contentWindow.GotoComicFrame(textUrl.hash, duration * 1000);
    }

    this.requestUpdate();
  }

  private _enableBlackAndWhite = () => {
    const enabled = !this._blackAndWhiteEnabled;
    this.iframe?.contentWindow.SetBlackAndWhiteMode(enabled);
    this._blackAndWhiteEnabled = enabled;
  };

  private readonly selectBookEvent = async (e: MouseEvent) => {
    this._iframeLoaded = false;
    this.mediaOverlay = undefined;
    this._navIdx = 0;

    this._selectedBook = (e.target as HTMLButtonElement).dataset.book;

    this.requestUpdate();

    this.mediaOverlay = await fetch(`/books/${this._selectedBook}/media-overlay.json`)
      .then((r) => r.json())
      .then((j) => j as MediaOverlay);

    this.requestUpdate();
  };

  private _iframeOnLoadEvent = (e: Event) => {
    const iframe = e.target as HTMLIFrameElement;

    const script = iframe.contentDocument.createElement('script');
    script.async = false;
    script.src = `/comics.js?r=${Date.now()}`;
    script.onload = () => {
      this._updateNarration();
      this._iframeLoaded = true;

      this._blackAndWhiteEnabled = iframe.contentWindow.IsBlackAndWhiteEnabled();
      script.onload = null;
    };
    iframe.contentDocument.head.appendChild(script);

    const epub = iframe.contentDocument.createElement('script');
    epub.async = false;
    epub.src = `/epub.js?r=${Date.now()}`;
    epub.onload = () => {
      this._updateNarration();
      this._iframeLoaded = true;
    };
    iframe.contentDocument.head.appendChild(epub);

    const epubCss = iframe.contentDocument.createElement('link');
    epubCss.href = `/epub.css?r=${Date.now()}`;
    epubCss.type = 'text/css';
    epubCss.rel = 'stylesheet';
    iframe.contentDocument.head.appendChild(epubCss);

    const link = iframe.contentDocument.createElement('link');
    link.href = `/comics.css?r=${Date.now()}`;
    link.type = 'text/css';
    link.rel = 'stylesheet';

    iframe.contentDocument.head.appendChild(link);
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
      height: 50px;
      justify-content: center;
    }

    .book-controls > .nav-idx {
      line-height: 50px;
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
