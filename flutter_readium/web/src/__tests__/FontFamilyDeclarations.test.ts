import {
  fontFaceCss,
  fontFaceUrls,
  parseFontFamilyDeclarations,
} from "../fonts/FontFamilyDeclarations";

describe("font family declarations", () => {
  const declaration = {
    name: "Atkinson Hyperlegible",
    fallbacks: ["sans-serif"],
    faces: [
      {
        asset: "assets/assets/fonts/Atkinson/Atkinson-Regular.ttf",
        style: "normal" as const,
        weight: 400,
      },
      {
        asset: "assets/assets/fonts/Atkinson/Atkinson-BoldItalic.0123abcd.ttf",
        style: "italic" as const,
        weight: 700,
      },
    ],
  };

  it("parses a serialized family without losing face metadata", () => {
    expect(parseFontFamilyDeclarations(JSON.stringify([declaration])))
      .toEqual([declaration]);
  });

  it("resolves the asset manager's URLs against the base, one font-family descriptor per face", () => {
    expect(fontFaceCss([declaration], "https://reader.example/app/")).toBe(
      '@font-face { font-family: "Atkinson Hyperlegible"; src: url("https://reader.example/app/assets/assets/fonts/Atkinson/Atkinson-Regular.ttf"); font-style: normal; font-weight: 400; }\n' +
      '@font-face { font-family: "Atkinson Hyperlegible"; src: url("https://reader.example/app/assets/assets/fonts/Atkinson/Atkinson-BoldItalic.0123abcd.ttf"); font-style: italic; font-weight: 700; }'
    );
  });

  const cssUrls = (css: string) => [...css.matchAll(/url\("([^"]+)"\)/g)].map((m) => m[1]);

  it("allows exactly the font URLs the @font-face rules load", () => {
    const baseUrl = "https://reader.example/app/";
    expect(fontFaceUrls([declaration], baseUrl)).toEqual(cssUrls(fontFaceCss([declaration], baseUrl)));
  });

  it("allows fonts served from a cross-origin asset base", () => {
    const cdnDeclaration = {
      ...declaration,
      faces: [{ ...declaration.faces[0], asset: "https://cdn.example/app/assets/assets/fonts/Atkinson/Atkinson-Regular.ttf" }],
    };
    const baseUrl = "https://reader.example/app/";
    expect(fontFaceUrls([cdnDeclaration], baseUrl)).toEqual([
      "https://cdn.example/app/assets/assets/fonts/Atkinson/Atkinson-Regular.ttf",
    ]);
    expect(cssUrls(fontFaceCss([cdnDeclaration], baseUrl))).toEqual(fontFaceUrls([cdnDeclaration], baseUrl));
  });

  it("allows nothing when no fonts are declared", () => {
    expect(fontFaceUrls([], "https://reader.example/app/")).toEqual([]);
  });

  it("rejects a family without faces", () => {
    expect(() => parseFontFamilyDeclarations(JSON.stringify([{
      name: "Empty",
      fallbacks: [],
      faces: [],
    }]))).toThrow("must contain at least one face");
  });
});
