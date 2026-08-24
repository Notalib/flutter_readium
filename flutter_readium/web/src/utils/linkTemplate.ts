import { Link } from "@readium/shared";
import { createLogger } from "./ReadiumPluginLogger";

const log = createLogger("LinkTemplate");
const reportedFailures = new Set<string>();

export type LinkTemplateContext = Readonly<Record<string, string>>;

export type LinkResolutionFailureReason =
  | "missing-variable"
  | "invalid-template"
  | "invalid-href";

export type LinkResolution =
  | {
      ok: true;
      link: Link;
      url: string | undefined;
    }
  | {
      ok: false;
      link: Link;
      reason: LinkResolutionFailureReason;
      missingVariables?: string[];
    };

/**
 * Resolves a Link Object URI template without changing non-templated links.
 *
 * URI templates are expanded only when the manifest explicitly marks the link
 * as templated. Missing values and malformed expressions are returned as
 * typed failures so optional sidecar callers can continue without issuing a
 * request for the literal template.
 */
export function resolveLink(
  link: Link,
  context: LinkTemplateContext = {},
  baseURL?: string
): LinkResolution {
  if (!link.templated) {
    const url = safeToURL(link, baseURL);
    return url === undefined
      ? failure(link, "invalid-href")
      : { ok: true, link, url };
  }

  const expressions = parseExpressions(link.href);
  if (expressions === undefined) {
    return failure(link, "invalid-template");
  }

  const parameters = expressions.flatMap((expression) => expression.parameters);
  const missingVariables = parameters.filter((parameter) => !(parameter in context));
  if (missingVariables.length > 0) {
    return failure(link, "missing-variable", [...new Set(missingVariables)]);
  }

  const expandedHref =
    expressions.length === 0 ? link.href : link.expandTemplate(context).href;
  if (/[{}]/.test(expandedHref)) {
    return failure(link, "invalid-template");
  }

  const resolvedLink = copyLink(link, expandedHref);
  const url = safeToURL(resolvedLink, baseURL);
  if (url === undefined) {
    return failure(link, "invalid-href");
  }

  return { ok: true, link: resolvedLink, url };
}

/**
 * Builds the standard context used when a sidecar Link is attached to a
 * publication resource.
 */
export function linkTemplateContext(
  resourceLink: Link,
  sidecarLink?: Link
): LinkTemplateContext {
  const context: Record<string, string> = {
    ref: resourceLink.href,
    resource: resourceLink.href,
  };

  const fragmentIndex = resourceLink.href.indexOf("#");
  if (fragmentIndex >= 0 && fragmentIndex < resourceLink.href.length - 1) {
    context.id = resourceLink.href.slice(fragmentIndex + 1);
  }

  if (sidecarLink) {
    context.mediaOverlay = sidecarLink.href;
    context["media-overlay"] = sidecarLink.href;
  }

  return context;
}

interface TemplateExpression {
  parameters: string[];
}

function parseExpressions(href: string): TemplateExpression[] | undefined {
  const expressions: TemplateExpression[] = [];
  let cursor = 0;

  while (cursor < href.length) {
    const open = href.indexOf("{", cursor);
    const close = href.indexOf("}", cursor);

    if (open === -1) {
      return close === -1 ? expressions : undefined;
    }
    const nestedOpen = href.indexOf("{", open + 1);
    if (close === -1 || close < open || (nestedOpen >= 0 && nestedOpen < close)) {
      return undefined;
    }

    const body = href.slice(open + 1, close);
    const operator = body.startsWith("?") ? "?" : "";
    const variableList = operator ? body.slice(1) : body;
    const parameters = variableList.split(",");
    if (
      variableList.length === 0 ||
      parameters.some((parameter) => !/^[A-Za-z][A-Za-z0-9._-]*$/.test(parameter))
    ) {
      return undefined;
    }

    expressions.push({ parameters });
    cursor = close + 1;
  }

  return expressions;
}

function copyLink(link: Link, href: string): Link {
  const serialized = link.serialize();
  serialized.href = href;
  serialized.templated = false;
  return Link.deserialize(serialized) ?? new Link({ href });
}

function safeToURL(link: Link, baseURL?: string): string | undefined {
  try {
    return link.toURL(baseURL);
  } catch {
    return undefined;
  }
}

function failure(
  link: Link,
  reason: LinkResolutionFailureReason,
  missingVariables?: string[]
): LinkResolution {
  const key = `${reason}:${link.href}:${missingVariables?.join(",") ?? ""}`;
  if (!reportedFailures.has(key)) {
    reportedFailures.add(key);
    if (reason === "missing-variable") {
      log.warn("Unable to resolve templated link; missing variables", {
        href: link.href,
        missingVariables,
      });
    } else {
      log.warn("Unable to resolve templated link", {
        href: link.href,
        reason,
      });
    }
  }

  return { ok: false, link, reason, missingVariables };
}
