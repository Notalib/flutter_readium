/**
 * Unit tests for the voice TTS uses when the app has not chosen one.
 * Voice lists mirror Chrome on macOS, which lists novelty voices first.
 */
import { pickDefaultVoice } from "../navigators/defaultVoice";

function voice(name: string, lang: string, extra: Partial<SpeechSynthesisVoice> = {}): SpeechSynthesisVoice {
  return { name, lang, voiceURI: name, default: false, localService: true, ...extra } as SpeechSynthesisVoice;
}

const macVoices = [
  voice("Albert", "en-US"),
  voice("Bad News", "en-US"),
  voice("Daniel", "en-GB"),
  voice("Eddy (English (United States))", "en-US"),
  voice("Fred", "en-US"),
  voice("Samantha", "en-US"),
  voice("Google US English", "en-US", { localService: false }),
  voice("Sara (Enhanced)", "da-DK", { default: true }),
  voice("Magnus", "da-DK"),
];

describe("pickDefaultVoice", () => {
  it("never picks a novelty or Eloquence voice", () => {
    expect(pickDefaultVoice(macVoices, "en-US")?.name).toBe("Samantha");
  });

  it("skips localized novelty names and eSpeak voices", () => {
    const voices = [
      voice("Mauvaises nouvelles", "fr-FR"),
      voice("Thomas", "fr-FR"),
      voice("eSpeak Danish", "da-DK"),
      voice("Magnus", "da-DK"),
    ];

    expect(pickDefaultVoice(voices, "fr")?.name).toBe("Thomas");
    expect(pickDefaultVoice(voices, "da")?.name).toBe("Magnus");
  });

  it("matches a language without a region", () => {
    expect(pickDefaultVoice(macVoices, "en")?.name).toBe("Daniel");
  });

  it("prefers the browser default when it speaks the language", () => {
    expect(pickDefaultVoice(macVoices, "da")?.name).toBe("Sara (Enhanced)");
  });

  it("prefers the exact region", () => {
    expect(pickDefaultVoice(macVoices, "en-GB")?.name).toBe("Daniel");
  });

  it("prefers high-quality local voices over network voices", () => {
    const voices = [
      voice("Google US English", "en-US", { localService: false }),
      voice("Samantha", "en-US"),
      voice("Ava (Premium)", "en-US"),
    ];

    expect(pickDefaultVoice(voices, "en-US")?.name).toBe("Ava (Premium)");
  });

  it("prefers a plain local voice over a network voice", () => {
    const voices = [
      voice("Microsoft Christel Online (Natural) - Danish (Denmark)", "da-DK", { localService: false }),
      voice("Microsoft Helle - Danish (Denmark)", "da-DK"),
    ];

    expect(pickDefaultVoice(voices, "da")?.name).toBe("Microsoft Helle - Danish (Denmark)");
  });

  it("returns undefined when only unsuitable voices speak the language", () => {
    expect(pickDefaultVoice([voice("Albert", "en-US"), voice("Magnus", "da-DK")], "en")).toBeUndefined();
  });
});
