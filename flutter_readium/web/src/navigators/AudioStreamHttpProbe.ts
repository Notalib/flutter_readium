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
) => Promise<ProbeResponse>;

/**
 * The parts of a fetch `Response` the probe reads. `Content-Length` and `Content-Type` are
 * CORS-safelisted.
 */
export interface ProbeResponse {
  status: number;
  ok: boolean;
  headers?: { get(name: string): string | null };
}

export interface ProbeOptions {
  /** Injectable `fetch` — defaults to the global. */
  fetch?: ProbeFetch;
  /** Injectable online check — defaults to `navigator.onLine`. */
  isOnline?: () => boolean;
  /** Hard timeout per HTTP attempt (HEAD, then GET fallback), in ms. */
  timeoutMs?: number;
  /**
   * The browser reported `MEDIA_ERR_DECODE`. A 2xx answer then ends playback instead of
   * retrying, and carries reason `undecodable` only when the server labels the track as audio.
   */
  decodeError?: boolean;
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
): Promise<ProbeResponse | undefined> {
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

function isEmptyBody(response: ProbeResponse): boolean {
  return response.ok && response.headers?.get("Content-Length")?.trim() === "0";
}

/**
 * A captive portal or login page answers 2xx with HTML, which the browser also fails to decode,
 * so only an audio `Content-Type` makes an undecodable track a defect in the publication.
 */
function isServedAsAudio(response: ProbeResponse): boolean {
  const type = response.headers?.get("Content-Type")?.split(";")[0].trim().toLowerCase() ?? "";
  return type.startsWith("audio/") || type === "application/octet-stream";
}

/**
 * Maps a resolved HTTP status to a classification, or `undefined` if inconclusive (opaque/0).
 * Answers that prove the track itself is broken (gone, or served empty) carry a defect `reason`.
 */
function classifyStatus(
  response: ProbeResponse,
  decodeError: boolean
): AudioStreamErrorAction | undefined {
  const httpStatus = response.status;
  if (httpStatus <= 0) return undefined; // opaque response — no real status visible
  if (httpStatus === 401 || httpStatus === 403)
    return AudioStreamErrorAction.fail("AudioStreamAuthError", httpStatus);
  if (httpStatus === 404 || httpStatus === 410)
    return AudioStreamErrorAction.fail("AudioStreamHTTPError", httpStatus, "missing");
  // An empty file has no byte 0, so the browser's ranged GET gets 416.
  if (httpStatus === 416)
    return AudioStreamErrorAction.fail("AudioStreamHTTPError", httpStatus, "empty");
  if (isEmptyBody(response))
    return AudioStreamErrorAction.fail("AudioStreamError", httpStatus, "empty");
  if (httpStatus >= 400 && httpStatus < 500)
    return AudioStreamErrorAction.fail("AudioStreamHTTPError", httpStatus);
  if (httpStatus >= 500) return AudioStreamErrorAction.retry();
  if (decodeError) {
    return isServedAsAudio(response)
      ? AudioStreamErrorAction.fail("AudioStreamError", httpStatus, "undecodable")
      : AudioStreamErrorAction.fail("AudioStreamError", httpStatus);
  }
  return AudioStreamErrorAction.retry(); // 2xx/3xx: resource reachable again
}

/**
 * Probes `url` (the resolved absolute URL of the failing audio resource) to
 * determine the real HTTP status behind a `MediaError`.
 *
 * Sequence: HEAD first; if that fails outright, returns 405 (method not
 * allowed — some static hosts/proxies reject HEAD), or reports an empty body,
 * retries once with `GET` + `Range: bytes=0-0` (fetches at most one byte).
 * Some servers answer HEAD with `Content-Length: 0` for a real file, so an empty
 * HEAD alone never fails a track.
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
  const decodeError = options.decodeError ?? false;

  if (!fetchFn) return undefined; // no fetch available — inconclusive

  const head = await fetchWithTimeout(fetchFn, url, { method: "HEAD" }, timeoutMs);

  if (head && head.status !== 405 && !isEmptyBody(head)) {
    return classifyStatus(head, decodeError);
  }

  // HEAD threw/timed out, was rejected with 405, or claimed an empty body — retry once with a
  // minimal ranged GET, which most servers accept even when HEAD is blocked.
  const get = await fetchWithTimeout(
    fetchFn,
    url,
    { method: "GET", headers: { Range: "bytes=0-0" } },
    timeoutMs
  );

  if (get) {
    return classifyStatus(get, decodeError);
  }

  // Both attempts threw/timed out. Distinguish "definitely offline" (retry —
  // matches iOS's `.offline` -> retry mapping) from a genuinely inconclusive
  // probe (CORS block, transient DNS hiccup, etc.) that should fall back to
  // the MediaError-only mapping rather than guessing.
  return isOnline() ? undefined : AudioStreamErrorAction.retry();
}
