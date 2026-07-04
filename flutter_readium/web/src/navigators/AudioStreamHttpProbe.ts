/**
 * HTTP diagnostic probe that upgrades web audio-streaming error
 * classification beyond the generic `MediaError` code.
 *
 * Browser constraint noted in `AudioStreamErrorPolicy.ts`: `HTMLMediaElement`
 * only ever exposes a `MediaError` with one of 4 generic codes — no HTTP
 * status. But ts-toolkit's `AudioNavigator` sets `mediaElement.crossOrigin =
 * "anonymous"` and assigns the resource URL directly to `element.src`, so CORS
 * is already required for playback to work at all. That means a follow-up
 * `fetch()` to the same URL is CORS-viable and can see the real HTTP status —
 * closing (most of) the gap with iOS/Android's `AudioStreamAuthError` /
 * `AudioStreamHTTPError` classification.
 *
 * This is a best-effort upgrade, not a guarantee: some origins block CORS
 * fetches even though `<audio crossorigin>` GETs succeed (rare in practice,
 * since browsers apply the same CORS check to both), and some proxies reject
 * HEAD. Any inconclusive outcome (timeout, thrown error while online, opaque
 * response) falls back to the existing `MediaError`-only mapping — never
 * fabricates a status.
 */

import { AudioStreamErrorAction } from "./AudioStreamErrorPolicy";

/** Injectable subset of the global `fetch` signature used by the probe. */
export type ProbeFetch = (
  input: string,
  init?: {
    method?: string;
    mode?: "cors";
    credentials?: "omit";
    cache?: "no-store";
    headers?: Record<string, string>;
    signal?: AbortSignal;
  }
) => Promise<{ status: number; ok: boolean }>;

export interface ProbeOptions {
  /** Injectable `fetch` — defaults to the global. */
  fetch?: ProbeFetch;
  /** Injectable online check — defaults to `navigator.onLine`. */
  isOnline?: () => boolean;
  /** Hard timeout per HTTP attempt (HEAD, then GET fallback), in ms. */
  timeoutMs?: number;
}

const DEFAULT_TIMEOUT_MS = 3_000;

function defaultIsOnline(): boolean {
  return typeof navigator === "undefined" ? true : navigator.onLine;
}

/** Runs `fetch` with a hard timeout. Resolves `undefined` on timeout (never rejects for that case). */
async function fetchWithTimeout(
  fetchFn: ProbeFetch,
  url: string,
  init: { method: string; headers?: Record<string, string> },
  timeoutMs: number
): Promise<{ status: number; ok: boolean } | undefined> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetchFn(url, {
      ...init,
      mode: "cors",
      credentials: "omit",
      cache: "no-store",
      signal: controller.signal,
    });
  } catch {
    return undefined;
  } finally {
    clearTimeout(timer);
  }
}

/** Maps a resolved HTTP status to a classification, or `undefined` if inconclusive (opaque/0). */
function classifyStatus(status: number): AudioStreamErrorAction | undefined {
  if (status <= 0) return undefined; // opaque response — no real status visible
  if (status === 401 || status === 403)
    return AudioStreamErrorAction.fail("AudioStreamAuthError", status);
  if (status >= 400 && status < 500)
    return AudioStreamErrorAction.fail("AudioStreamHTTPError", status);
  if (status >= 500) return AudioStreamErrorAction.retry();
  return AudioStreamErrorAction.retry(); // 2xx/3xx: resource reachable again
}

/**
 * Probes `url` (the resolved absolute URL of the failing audio resource) to
 * determine the real HTTP status behind a `MediaError`.
 *
 * Sequence: HEAD first; if that fails outright or returns 405 (method not
 * allowed — some static hosts/proxies reject HEAD), retries once with
 * `GET` + `Range: bytes=0-0` (fetches at most one byte).
 *
 * Returns `undefined` (inconclusive) when neither attempt yields a usable
 * status — callers should fall back to the existing `MediaError`-only
 * mapping in that case.
 */
export async function probeAudioStreamHttpStatus(
  url: string,
  options: ProbeOptions = {}
): Promise<AudioStreamErrorAction | undefined> {
  const fetchFn = options.fetch ?? (globalThis as { fetch?: ProbeFetch }).fetch;
  const isOnline = options.isOnline ?? defaultIsOnline;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  if (!fetchFn) return undefined; // no fetch available — inconclusive

  const head = await fetchWithTimeout(fetchFn, url, { method: "HEAD" }, timeoutMs);

  if (head && head.status !== 405) {
    return classifyStatus(head.status);
  }

  // HEAD threw/timed out, or was rejected with 405 — retry once with a
  // minimal ranged GET, which most servers accept even when HEAD is blocked.
  const get = await fetchWithTimeout(
    fetchFn,
    url,
    { method: "GET", headers: { Range: "bytes=0-0" } },
    timeoutMs
  );

  if (get) {
    return classifyStatus(get.status);
  }

  // Both attempts threw/timed out. Distinguish "definitely offline" (retry —
  // matches iOS's `.offline` -> retry mapping) from a genuinely inconclusive
  // probe (CORS block, transient DNS hiccup, etc.) that should fall back to
  // the MediaError-only mapping rather than guessing.
  return isOnline() ? undefined : AudioStreamErrorAction.retry();
}
