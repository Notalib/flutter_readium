import {
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

  it("rejects a family without faces", () => {
    expect(() => parseFontFamilyDeclarations(JSON.stringify([{
      name: "Empty",
      fallbacks: [],
      faces: [],
    }]))).toThrow("must contain at least one face");
  });
});
