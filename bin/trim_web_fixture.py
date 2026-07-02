#!/usr/bin/env python3
"""Explode a packaged Readium .webpub/.audiobook into an exploded directory (for
use as an offline web integration-test fixture under example/web/), optionally
trimming it to the first N reading-order entries to keep the committed size down.

The packaged Nota assets already contain a relative-href manifest.json, so the
exploded tree serves directly at the app origin during `flutter drive`.

Trimming keeps the first N reading-order entries and only the resources/toc/audio
they reference (everything else is deleted), then recomputes metadata.duration.
Omit N to explode the publication as-is (no trim).

Usage:
  bin/trim_web_fixture.py <src.webpub|.audiobook> <out_dir> [num_reading_order]

Examples (run from the repo root):
  # media overlay -> first 4 chapters
  bin/trim_web_fixture.py \\
    flutter_readium/example/assets/pubs/38533_overlay_preview.webpub \\
    flutter_readium/example/web/test-overlay 4

  # audiobook -> first 3 tracks
  bin/trim_web_fixture.py \\
    flutter_readium/example/assets/pubs/38533.audiobook \\
    flutter_readium/example/web/test-audiobook-nota 3

  # comic -> keep everything (omit the count)
  bin/trim_web_fixture.py \\
    flutter_readium/example/assets/pubs/50272-nota-comics.webpub \\
    flutter_readium/example/web/test-comic
"""
import json
import os
import re
import shutil
import sys
import zipfile


def strip_frag(href):
    return href.split("#")[0]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)

    src, out_dir = sys.argv[1], sys.argv[2]
    n = int(sys.argv[3]) if len(sys.argv) > 3 else None

    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir)
    with zipfile.ZipFile(src) as z:
        z.extractall(out_dir)

    # The served fixture must be reachable as `manifest.json` regardless of
    # what the source package's own manifest file is named internally.
    mpath = os.path.join(out_dir, "manifest.json")
    if not os.path.exists(mpath):
        json_names = [name for name in os.listdir(out_dir) if name.endswith(".json")]
        if len(json_names) != 1:
            raise SystemExit(f"Expected exactly one top-level .json in {out_dir}, found {json_names}")
        os.rename(os.path.join(out_dir, json_names[0]), mpath)

    if n is None:
        # Explode as-is: no trim requested, so nothing gets pruned — every
        # extracted file and the manifest stay exactly as packaged.
        print(f"Exploded {src} -> {out_dir} (as-is, no trim)")
        return

    with open(mpath, encoding="utf-8") as f:
        m = json.load(f)

    reading_order = m["readingOrder"][:n]
    m["readingOrder"] = reading_order

    # Collect the relative hrefs that must survive the trim.
    kept = {"manifest.json"}

    # Cover (declared in links or resources).
    for link in m.get("links", []) + m.get("resources", []):
        rels = link.get("rel")
        rels = rels if isinstance(rels, list) else [rels] if rels else []
        if "cover" in rels and not link.get("href", "").startswith("http"):
            kept.add(strip_frag(link["href"]))

    xhtml_kept = set()
    for entry in reading_order:
        href = strip_frag(entry["href"])
        if not href.startswith("http"):
            kept.add(href)
            xhtml_kept.add(href)
        media_overlay = entry.get("properties", {}).get("media-overlay")
        if media_overlay:
            kept.add(strip_frag(media_overlay))
        for alt in entry.get("alternate", []):
            alt_href = strip_frag(alt.get("href", ""))
            if alt_href and not alt_href.startswith("http"):
                kept.add(alt_href)
        # Audio files referenced inside this entry's media-overlay (syncnarr) JSON.
        if media_overlay:
            jp = os.path.join(out_dir, strip_frag(media_overlay))
            if os.path.exists(jp):
                with open(jp, encoding="utf-8") as jf:
                    blob = jf.read()
                for audio in re.findall(r'"audio"\s*:\s*"([^"#]+)', blob):
                    if not audio.startswith("http"):
                        kept.add(audio)

    # Guided Navigation (a separate mechanism from Media Overlay): a top-level
    # `links` entry of type `application/guided-navigation+json` points to a
    # document whose `guided` sections pair each `textref` with an `audioref`.
    # Trim its sections to the kept xhtml files and keep only their audio.
    guided_nav_path = None
    for link in m.get("links", []):
        if "guided-navigation" in link.get("type", "") and not link.get("href", "").startswith("http"):
            guided_nav_path = strip_frag(link["href"])
            kept.add(guided_nav_path)
            break

    if guided_nav_path:
        gp = os.path.join(out_dir, guided_nav_path)
        with open(gp, encoding="utf-8") as gf:
            guided_doc = json.load(gf)

        def section_in_scope(section):
            in_scope = False
            for child in section.get("children", []):
                textref = strip_frag(child.get("textref", ""))
                if textref in xhtml_kept:
                    in_scope = True
                    audioref = strip_frag(child.get("audioref", ""))
                    if audioref and not audioref.startswith("http"):
                        kept.add(audioref)
            return in_scope

        guided_doc["guided"] = [s for s in guided_doc.get("guided", []) if section_in_scope(s)]
        with open(gp, "w", encoding="utf-8") as gf:
            json.dump(guided_doc, gf, ensure_ascii=False, indent=2)

    # Filter the resources list (and add any kept resources to the keep set).
    if "resources" in m:
        m["resources"] = [
            r
            for r in m["resources"]
            if r.get("href", "").startswith("http") or strip_frag(r["href"]) in kept
        ]
        for r in m["resources"]:
            if not r.get("href", "").startswith("http"):
                kept.add(strip_frag(r["href"]))

    # Filter the toc recursively to kept reading-order/audio bases.
    def filter_toc(items):
        out = []
        for it in items:
            base = strip_frag(it.get("href", ""))
            children = filter_toc(it.get("children", [])) if it.get("children") else []
            if base in kept or base in xhtml_kept or children:
                new = dict(it)
                if children:
                    new["children"] = children
                elif "children" in new:
                    del new["children"]
                out.append(new)
        return out

    if "toc" in m:
        m["toc"] = filter_toc(m["toc"])

    # Recompute total duration from the kept reading-order entries.
    total = sum(e.get("duration", 0) for e in reading_order)
    if "duration" in m.get("metadata", {}):
        m["metadata"]["duration"] = round(total, 3)

    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)

    # Delete any extracted files that are no longer referenced (walking
    # subdirectories, e.g. `images/cover.jpg`), then prune dirs left empty.
    removed = []
    for dirpath, _dirnames, filenames in os.walk(out_dir, topdown=False):
        for filename in filenames:
            file_path = os.path.join(dirpath, filename)
            rel_path = os.path.relpath(file_path, out_dir)
            if rel_path not in kept:
                os.remove(file_path)
                removed.append(rel_path)
        if dirpath != out_dir and not os.listdir(dirpath):
            os.rmdir(dirpath)

    print(f"Exploded {src} -> {out_dir}")
    print(f"  readingOrder entries: {len(reading_order)}")
    print(f"  duration: {m.get('metadata', {}).get('duration')}")
    print(f"  kept {len(kept)} files, removed {len(removed)}")
    if removed:
        print(f"  removed: {sorted(removed)}")


if __name__ == "__main__":
    main()
