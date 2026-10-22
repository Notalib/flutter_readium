/** @jest-environment jsdom */
import * as fs from "fs";
import * as path from "path";
import * as ts from "typescript";
import { minify } from "terser";
import * as fonts from "../fonts/FontFamilyDeclarations";

const declarations = [{
  name: "Atkinson",
  fallbacks: [],
  faces: [{ asset: "fonts/Atkinson-Regular.ttf", style: "normal" as const, weight: 400 }],
}];

// Some bugs only exist after minification, so the module also runs through
// terser with the production build's options.
async function minifiedModule(): Promise<typeof fonts> {
  const source = fs.readFileSync(path.join(__dirname, "../fonts/FontFamilyDeclarations.ts"), "utf8");
  const js = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2017, module: ts.ModuleKind.CommonJS },
  }).outputText;
  const { code } = await minify(js, { compress: { pure_funcs: ["console.log"] } });
  const exports = {};
  new Function("exports", code!)(exports);
  return exports as typeof fonts;
}

describe("injectFontFacesIntoWindow", () => {
  it.each([
    ["source", async () => fonts],
    ["minified", minifiedModule],
  ])("resolves assets against the host page, not the frame (%s)", async (_, load) => {
    const { injectFontFacesIntoWindow } = await load();
    const frameDocument = document.implementation.createHTMLDocument();

    injectFontFacesIntoWindow({ document: frameDocument } as unknown as Window, declarations);

    expect(frameDocument.getElementById("flutter-readium-font-faces")?.textContent)
      .toContain(`url("${document.baseURI}assets/fonts/Atkinson-Regular.ttf")`);
  });
});
