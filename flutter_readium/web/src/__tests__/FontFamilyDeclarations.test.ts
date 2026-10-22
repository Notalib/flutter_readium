import { Injector } from "@readium/navigator";
import {
  fontFaceAllowedDomains,
  fontFaceCss,
  parseFontFamilyDeclarations,
} from "../fonts/FontFamilyDeclarations";

describe("font family declarations", () => {
  const declaration = {
    name: "Atkinson Hyperlegible",
    fallbacks: ["sans-serif"],
    faces: [
      {
        asset: "assets/fonts/Atkinson/Atkinson-Regular.ttf",
        style: "normal" as const,
        weight: 400,
      },
      {
        asset: "assets/fonts/Atkinson/Atkinson-BoldItalic.ttf",
        style: "italic" as const,
        weight: 700,
      },
    ],
  };

  it("parses a serialized family without losing face metadata", () => {
    expect(parseFontFamilyDeclarations(JSON.stringify([declaration])))
      .toEqual([declaration]);
  });

  it("generates Flutter asset URLs and one font-family descriptor per face", () => {
    expect(fontFaceCss([declaration], "https://reader.example/app/")).toBe(
      '@font-face { font-family: "Atkinson Hyperlegible"; src: url("https://reader.example/app/assets/assets/fonts/Atkinson/Atkinson-Regular.ttf"); font-style: normal; font-weight: 400; }\n' +
      '@font-face { font-family: "Atkinson Hyperlegible"; src: url("https://reader.example/app/assets/assets/fonts/Atkinson/Atkinson-BoldItalic.ttf"); font-style: italic; font-weight: 700; }'
    );
  });

  it("allows the asset directory every generated font URL lives under", () => {
    const baseUrl = "https://reader.example/app/";
    const allowed = fontFaceAllowedDomains([declaration], baseUrl);
    // The navigator copies these into the frame CSP, where a source ending in "/" matches by path prefix.
    expect(new Injector({ rules: [], allowedDomains: allowed }).getAllowedDomains())
      .toEqual(["https://reader.example/app/assets/"]);
    const urls = [...fontFaceCss([declaration], baseUrl).matchAll(/url\("([^"]+)"\)/g)].map((m) => m[1]);
    expect(urls).toHaveLength(2);
    for (const url of urls) expect(url.startsWith(allowed[0])).toBe(true);
  });

  it("allows no extra domains without declarations", () => {
    expect(fontFaceAllowedDomains([], "https://reader.example/app/")).toEqual([]);
  });

  it("rejects a family without faces", () => {
    expect(() => parseFontFamilyDeclarations(JSON.stringify([{
      name: "Empty",
      fallbacks: [],
      faces: [],
    }]))).toThrow("must contain at least one face");
  });
});
