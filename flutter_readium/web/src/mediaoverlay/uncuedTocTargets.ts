/**
 * ToC entries can target an element (e.g. a newspaper `<section>` or `<aside>`) that is
 * neither a Sync Narration cue nor a narration container; only its descendants have cues.
 * Resolves such targets at lookup time from the resource's XHTML, parsed once per resource.
 * Mirrors XhtmlIdTree on iOS and Android. See ADR 0001.
 */

import { Link, Locator, LocatorLocations } from "@readium/shared";
import { ReadiumPublication } from "../utils/ReadiumExtensions";
import { createLogger } from "../utils/ReadiumPluginLogger";
import { SyncNarrationItem, normalizeHref, parseTextField } from "./syncNarration";

const log = createLogger("UncuedTocTargets");

/** The parts of a DOM `Element` the id tree reads. */
export interface IdTreeElement {
  id: string;
  children: ArrayLike<IdTreeElement>;
}

/** Element ids in document order, with each element's subtree. */
export class XhtmlIdTree {
  readonly ids: string[] = [];
  /** The descendants of `ids[i]` are `ids.slice(i + 1, subtreeEnd[i])`. */
  private readonly subtreeEnd: number[] = [];

  constructor(root: IdTreeElement) {
    this.visit(root);
  }

  /** Parses XHTML, retrying as HTML when the XML is malformed. */
  static parse(xhtml: string): XhtmlIdTree {
    const parser = new DOMParser();
    let doc = parser.parseFromString(xhtml, "application/xhtml+xml");
    if (doc.getElementsByTagName("parsererror").length > 0) {
      log.debug("XHTML parse failed; retrying as HTML");
      doc = parser.parseFromString(xhtml, "text/html");
    }
    return new XhtmlIdTree(doc.documentElement);
  }

  /** The first id inside element `id`, excluding `id` itself, that is in `candidates`. */
  firstDescendant(id: string, candidates: Set<string>): string | undefined {
    const start = this.ids.indexOf(id);
    if (start === -1) return undefined;
    return this.ids.slice(start + 1, this.subtreeEnd[start]).find((x) => candidates.has(x));
  }

  private visit(element: IdTreeElement): void {
    const index = element.id ? this.ids.push(element.id) - 1 : -1;
    if (index !== -1) this.subtreeEnd.push(this.ids.length);
    for (let i = 0; i < element.children.length; i++) this.visit(element.children[i]);
    if (index !== -1) this.subtreeEnd[index] = this.ids.length;
  }
}

/**
 * Gives each cue of one resource that has no `tocHref` the ToC entry that precedes it in
 * document order. An uncued ToC target counts at its first cue descendant; when a target
 * and a deeper entry share that cue, the deeper (later) entry wins. Cues before every
 * entry use the resource's file-only entry when present, otherwise remain unowned.
 */
export function assignUncuedTocOwners(
  resourceItems: SyncNarrationItem[],
  resourceToc: Link[],
  tree: XhtmlIdTree | undefined
): void {
  const cueIds = new Set(resourceItems.map((item) => item.textId));
  const entries = new Map<number, Link>();
  for (const link of resourceToc) {
    const { textId } = parseTextField(link.href);
    if (!textId) {
      entries.set(-1, link);
      continue;
    }
    const target = cueIds.has(textId) ? textId : tree?.firstDescendant(textId, cueIds);
    const index = resourceItems.findIndex((item) => item.textId === target);
    if (index !== -1) entries.set(index, link);
  }
  if (entries.size === 0) return;

  const sorted = [...entries.entries()].sort(([a], [b]) => a - b);
  resourceItems.forEach((item, index) => {
    if (item.tocHref) return;
    const owner = [...sorted].reverse().find(([start]) => start <= index)?.[1];
    if (!owner) return;
    item.tocHref = owner.href;
    item.tocTitle = owner.title;
  });
}

/** Lookup-time resolution of uncued ToC targets for one Sync Narration session. */
export class UncuedTocTargets {
  private readonly trees = new Map<string, Promise<XhtmlIdTree | undefined>>();
  private readonly filled = new Set<string>();

  constructor(
    private readonly publication: ReadiumPublication,
    private readonly items: SyncNarrationItem[],
    private readonly toc: Link[]
  ) {}

  /**
   * Gives the cues of one resource a ToC owner when the narration nesting gave them none.
   * Runs once per resource; cues emitted before it finishes keep no owner.
   */
  async fillOwners(textHref: string): Promise<void> {
    const resource = normalizeHref(textHref);
    if (this.filled.has(resource)) return;
    this.filled.add(resource);

    const resourceToc = this.toc.filter((link) => normalizeHref(link.href) === resource);
    if (resourceToc.length === 0) return;
    const resourceItems = this.items.filter((item) => normalizeHref(item.textHref) === resource);
    assignUncuedTocOwners(resourceItems, resourceToc, await this.tree(resource));
  }

  /**
   * Points a text locator at the first cue at or after its element when the element is neither a
   * cue nor a known ToC anchor. Without this, seeking to one inside the playing resource
   * fails (#139 forbids the resource fallback there).
   */
  async anchor(locator: Locator): Promise<Locator | undefined> {
    const textId = this.uncuedTextId(locator);
    if (!textId) return locator;

    const resource = normalizeHref(locator.href);
    const resourceItems = this.items.filter((item) => normalizeHref(item.textHref) === resource);
    const cueIds = new Set(resourceItems.map((item) => item.textId));
    const tree = await this.tree(resource);
    const start = tree?.ids.indexOf(textId) ?? -1;
    if (!tree || start === -1) return locator;
    const first = tree.ids.slice(start).find((id) => cueIds.has(id));
    if (!first) return undefined;

    log.debug(`anchor: ${resource}#${textId} -> #${first}`);
    const otherLocations = new Map(locator.locations?.otherLocations ?? []);
    otherLocations.set("cssSelector", `#${first}`);
    return new Locator({
      href: locator.href,
      type: locator.type,
      title: locator.title,
      text: locator.text,
      locations: new LocatorLocations({
        fragments: [first],
        progression: locator.locations?.progression,
        position: locator.locations?.position,
        totalProgression: locator.locations?.totalProgression,
        otherLocations,
      }),
    });
  }

  /** Whether [anchor] may change this locator, without loading any XHTML. */
  isUncued(locator: Locator): boolean {
    return this.uncuedTextId(locator) !== undefined;
  }

  /** The locator's text id when it is neither a cue nor a known ToC anchor in its resource. */
  private uncuedTextId(locator: Locator): string | undefined {
    if (locator.locations?.fragments?.some((fragment) => fragment.startsWith("t="))) return undefined;
    const resource = normalizeHref(locator.href);
    const textId =
      locator.locations?.fragments?.find((fragment) => !fragment.startsWith("t=")) ??
      locator.locations?.otherLocations?.get?.("cssSelector")?.replace(/^#/, "");
    if (!textId) return undefined;

    let hasCues = false;
    for (const item of this.items) {
      if (normalizeHref(item.textHref) !== resource) continue;
      hasCues = true;
      if (item.textId === textId) return undefined;
    }
    const known = this.items.some((item) => {
      if (!item.tocHref) return false;
      const owner = parseTextField(item.tocHref);
      return owner.textId === textId && normalizeHref(owner.textHref) === resource;
    });
    return hasCues && !known ? textId : undefined;
  }

  private tree(resource: string): Promise<XhtmlIdTree | undefined> {
    let tree = this.trees.get(resource);
    if (!tree) {
      tree = this.load(resource);
      this.trees.set(resource, tree);
    }
    return tree;
  }

  private async load(resource: string): Promise<XhtmlIdTree | undefined> {
    const link = this.publication.readingOrder.items.find((l) => normalizeHref(l.href) === resource);
    if (!link) return undefined;
    try {
      const xhtml = await this.publication.get(link).readAsString();
      return xhtml ? XhtmlIdTree.parse(xhtml) : undefined;
    } catch (err) {
      log.warn("Failed to read XHTML for", resource, err);
      return undefined;
    }
  }
}
