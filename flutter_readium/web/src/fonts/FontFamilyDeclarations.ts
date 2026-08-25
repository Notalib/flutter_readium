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

export function fontFaceCss(
  declarations: FontFamilyDeclaration[],
  baseUrl: string
): string {
  return declarations
    .flatMap((family) => family.faces.map((face) => {
      const assetUrl = new URL(`assets/${face.asset}`, baseUrl).href;
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
  const document = wnd.document;
  const existing = document.getElementById("flutter-readium-font-faces");
  if (existing) existing.remove();

  const style = document.createElement("style");
  style.id = "flutter-readium-font-faces";
  style.textContent = fontFaceCss(declarations, baseUrl);
  document.head.appendChild(style);
}
