export interface FontFaceDeclaration {
  asset: string;
  style: "normal" | "italic";
  weight: number;
}

export interface FontFamilyDeclaration {
  name: string;
  fallbacks: string[];
  faces: FontFaceDeclaration[];
}

export function parseFontFamilyDeclarations(json: string | undefined): FontFamilyDeclaration[] {
  if (!json) return [];

  const parsed: unknown = JSON.parse(json);
  if (!Array.isArray(parsed)) throw new Error("fontFamilyDeclarations must be an array");

  return parsed.map((family: any) => {
    if (typeof family?.name !== "string" || family.name.length === 0) {
      throw new Error("fontFamilyDeclarations contains a family without a name");
    }
    if (!Array.isArray(family.faces) || family.faces.length === 0) {
      throw new Error(`Font family ${family.name} must contain at least one face`);
    }
    const fallbacks = family.fallbacks ?? [];
    if (!Array.isArray(fallbacks) || fallbacks.some((fallback: unknown) => typeof fallback !== "string" || fallback.length === 0)) {
      throw new Error(`Font family ${family.name} contains an invalid fallback`);
    }
    const faces = family.faces.map((face: any) => {
      if (typeof face?.asset !== "string" || face.asset.length === 0) {
        throw new Error(`Font family ${family.name} contains a face without an asset`);
      }
      if (face.style !== "normal" && face.style !== "italic") {
        throw new Error(`Font family ${family.name} contains an invalid face style`);
      }
      if (!Number.isInteger(face.weight) || face.weight < 1 || face.weight > 1000) {
        throw new Error(`Font family ${family.name} contains an invalid face weight`);
      }
      return { asset: face.asset, style: face.style, weight: face.weight };
    });
    return { name: family.name, fallbacks, faces };
  });
}

function cssString(value: string): string {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

/** Directory that Flutter web serves app assets from. */
export function flutterAssetsUrl(baseUrl: string): string {
  return new URL("assets/", baseUrl).href;
}

/**
 * The EPUB frame CSP only allows fonts from the publication's origin, so the app's asset
 * directory must be listed for the injected `@font-face` rules to load.
 */
export function fontFaceAllowedDomains(
  declarations: FontFamilyDeclaration[],
  baseUrl: string
): string[] {
  return declarations.length === 0 ? [] : [flutterAssetsUrl(baseUrl)];
}

export function fontFaceCss(
  declarations: FontFamilyDeclaration[],
  baseUrl: string
): string {
  return declarations
    .flatMap((family) => family.faces.map((face) => {
      const assetUrl = new URL(face.asset, flutterAssetsUrl(baseUrl)).href;
      return `@font-face { font-family: ${cssString(family.name)}; src: url(${cssString(assetUrl)}); font-style: ${face.style}; font-weight: ${face.weight}; }`;
    }))
    .join("\n");
}

export function injectFontFacesIntoWindow(
  wnd: Window,
  declarations: FontFamilyDeclaration[],
  baseUrl: string = document.baseURI
): void {
  if (declarations.length === 0) return;
  // Don't name this `document`: terser then mangles the default parameter's global
  // `document` to the same local, and the production bundle throws "Invalid URL".
  const doc = wnd.document;
  const existing = doc.getElementById("flutter-readium-font-faces");
  if (existing) existing.remove();

  const style = doc.createElement("style");
  style.id = "flutter-readium-font-faces";
  style.textContent = fontFaceCss(declarations, baseUrl);
  doc.head.appendChild(style);
}
