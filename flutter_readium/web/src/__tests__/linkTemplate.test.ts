import { Link } from "@readium/shared";
import {
  linkTemplateContext,
  resolveLink,
} from "../utils/linkTemplate";

describe("resolveLink", () => {
  it("expands form-style query templates and resolves the result against the base URL", () => {
    const link = new Link({
      href: "~readium/guided-navigation.json{?ref}",
      templated: true,
      type: "application/guided-navigation+json",
    });

    const result = resolveLink(
      link,
      { ref: "chapters/one.xhtml" },
      "https://example.test/book/"
    );

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.link.href).toBe(
        "~readium/guided-navigation.json?ref=chapters%2Fone.xhtml"
      );
      expect(result.link.templated).toBe(false);
      expect(result.url).toBe(
        "https://example.test/book/~readium/guided-navigation.json?ref=chapters%2Fone.xhtml"
      );
    }
  });

  it("uses the standard resource context for sidecar links", () => {
    const resource = new Link({ href: "chapter.xhtml#section-1" });
    const sidecar = new Link({
      href: "overlay.json{?ref,id}",
      templated: true,
    });

    const result = resolveLink(
      sidecar,
      linkTemplateContext(resource, sidecar),
      "https://example.test/book/"
    );

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.link.href).toBe(
        "overlay.json?ref=chapter.xhtml%23section-1&id=section-1"
      );
    }
  });

  it("returns a typed failure when a variable is missing", () => {
    const link = new Link({ href: "search{?query}", templated: true });

    expect(resolveLink(link, {}, "https://example.test/book/")).toEqual({
      ok: false,
      link,
      reason: "missing-variable",
      missingVariables: ["query"],
    });
  });

  it("returns a typed failure for malformed template syntax", () => {
    const link = new Link({ href: "search{?query", templated: true });

    expect(resolveLink(link, { query: "readium" })).toEqual({
      ok: false,
      link,
      reason: "invalid-template",
    });
  });

  it("returns a typed failure when expansion produces an invalid href", () => {
    const link = new Link({
      href: "https://[invalid]{?ref}",
      templated: true,
    });

    expect(resolveLink(link, { ref: "chapter.xhtml" })).toEqual({
      ok: false,
      link,
      reason: "invalid-href",
    });
  });

  it("leaves non-templated links unchanged", () => {
    const link = new Link({ href: "chapter.xhtml" });

    const result = resolveLink(link, {}, "https://example.test/book/");

    expect(result).toEqual({
      ok: true,
      link,
      url: "https://example.test/book/chapter.xhtml",
    });
  });
});
