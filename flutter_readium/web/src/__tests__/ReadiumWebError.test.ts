import { ReadiumWebError, ReadiumWebErrorCode } from "../errors/ReadiumWebError";
import { Locator, LocatorLocations } from "@readium/shared";
import { __testing__ } from "../ReadiumReader";

const { ReadiumReader } = __testing__;

describe("ReadiumWebError", () => {
  it("carries code and details and remains a real Error", () => {
    const err = new ReadiumWebError("boom", ReadiumWebErrorCode.resourceReadError, {
      reason: "could not resolve URL",
      href: "images/cover.png",
    });

    expect(err).toBeInstanceOf(Error);
    expect(err.name).toBe("ReadiumWebError");
    expect(err.message).toBe("boom");
    expect(err.code).toBe("ResourceReadError");
    expect(err.details).toEqual({ reason: "could not resolve URL", href: "images/cover.png" });
  });

  it("allows details to be omitted", () => {
    const err = new ReadiumWebError("nope", ReadiumWebErrorCode.invalidArgument);
    expect(err.details).toBeUndefined();
  });
});

describe("ReadiumReader error classification at the TS boundary", () => {
  it("goTo: throws InvalidArgument when the locator JSON doesn't deserialize", async () => {
    const reader = new ReadiumReader();
    // Valid JSON, but missing the fields Locator.deserialize requires (e.g. href).
    await expect(reader.goTo("{}")).rejects.toMatchObject({
      code: ReadiumWebErrorCode.invalidArgument,
    });
  });

  it("setEPUBPreferences: throws NoPublication when no EPUB navigator is active", () => {
    const reader = new ReadiumReader();
    expect(() => reader.setEPUBPreferences("{}")).toThrow(
      expect.objectContaining({ code: ReadiumWebErrorCode.noPublication })
    );
  });

  describe("getResourceUrl", () => {
    it("throws NoPublication when no publication is open", async () => {
      const reader = new ReadiumReader();
      await expect(reader.getResourceUrl("images/cover.png")).rejects.toMatchObject({
        code: ReadiumWebErrorCode.noPublication,
      });
    });

    it("throws InvalidArgument for an unknown href", async () => {
      const reader = new ReadiumReader();
      (reader as any)._publication = { allLinks: [] };
      await expect(reader.getResourceUrl("images/missing.png")).rejects.toMatchObject({
        code: ReadiumWebErrorCode.invalidArgument,
        details: { href: "images/missing.png" },
      });
    });

    it("throws ResourceReadError when the link cannot be resolved to a URL", async () => {
      const reader = new ReadiumReader();
      const link = { href: "images/cover.png", toURL: () => undefined };
      (reader as any)._publication = { allLinks: [link], baseURL: undefined };
      await expect(reader.getResourceUrl("images/cover.png")).rejects.toMatchObject({
        code: ReadiumWebErrorCode.resourceReadError,
        details: { reason: "could not resolve URL", href: "images/cover.png" },
      });
    });
  });

  it("goTo: throws InvalidArgument when an audiobook link href is unknown", async () => {
    const reader = new ReadiumReader();
    (reader as any)._publication = {
      conformsToAudiobook: true,
      readingOrder: { items: [] },
      resources: { items: [] },
    };
    const locator = new Locator({
      href: "missing.mp3",
      type: "audio/mpeg",
      locations: new LocatorLocations({}),
    });
    await expect(reader.goTo(JSON.stringify(locator.serialize()))).rejects.toMatchObject({
      code: ReadiumWebErrorCode.invalidArgument,
      details: { href: "missing.mp3" },
    });
  });
});
