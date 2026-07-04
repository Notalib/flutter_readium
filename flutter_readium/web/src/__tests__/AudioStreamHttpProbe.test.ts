/**
 * Unit tests for the HTTP diagnostic probe that upgrades web audio-streaming
 * error classification beyond the generic `MediaError` code (see
 * `AudioStreamErrorPolicy.test.ts` for the base classifier).
 *
 * `fetch` and `isOnline` are injected so these run under
 * `testEnvironment: "node"` with no browser globals.
 */

import { AudioStreamErrorAction } from "../navigators/AudioStreamErrorPolicy";
import { probeAudioStreamHttpStatus } from "../navigators/AudioStreamHttpProbe";

type FetchLike = (input: string, init?: any) => Promise<{ status: number; ok: boolean }>;

function okResponse(status: number): { status: number; ok: boolean } {
  return { status, ok: status >= 200 && status < 300 };
}

describe("probeAudioStreamHttpStatus", () => {
  it("HEAD 401 -> fail(AudioStreamAuthError) with httpStatus", async () => {
    const fetch: FetchLike = async () => okResponse(401);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamAuthError", 401));
  });

  it("HEAD 403 -> fail(AudioStreamAuthError) with httpStatus", async () => {
    const fetch: FetchLike = async () => okResponse(403);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamAuthError", 403));
  });

  it("HEAD other 4xx (404) -> fail(AudioStreamHTTPError) with httpStatus", async () => {
    const fetch: FetchLike = async () => okResponse(404);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", 404));
  });

  it("HEAD 5xx -> retry", async () => {
    const fetch: FetchLike = async () => okResponse(503);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.retry());
  });

  it("HEAD 2xx (resource reachable again) -> retry", async () => {
    const fetch: FetchLike = async () => okResponse(200);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.retry());
  });

  it("HEAD 206 (partial content reachable) -> retry", async () => {
    const fetch: FetchLike = async () => okResponse(206);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.retry());
  });

  it("HEAD 405 falls back to GET+Range, which then reports the real status (401)", async () => {
    const calls: Array<{ input: string; init?: any }> = [];
    const fetch: FetchLike = async (input, init) => {
      calls.push({ input, init });
      return init?.method === "GET" ? okResponse(401) : okResponse(405);
    };
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamAuthError", 401));
    expect(calls).toHaveLength(2);
    expect(calls[0].init?.method).toBe("HEAD");
    expect(calls[1].init?.method).toBe("GET");
    expect(calls[1].init?.headers?.Range).toBe("bytes=0-0");
  });

  it("HEAD network failure falls back to GET+Range, which succeeds (404)", async () => {
    let call = 0;
    const fetch: FetchLike = async (_input, init) => {
      call++;
      if (init?.method === "HEAD") throw new TypeError("network error");
      return okResponse(404);
    };
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", 404));
    expect(call).toBe(2);
  });

  it("both HEAD and GET throw, browser online -> inconclusive (undefined)", async () => {
    const fetch: FetchLike = async () => {
      throw new TypeError("network error");
    };
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", {
      fetch,
      isOnline: () => true,
    });
    expect(result).toBeUndefined();
  });

  it("both HEAD and GET throw, browser offline -> retry", async () => {
    const fetch: FetchLike = async () => {
      throw new TypeError("network error");
    };
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", {
      fetch,
      isOnline: () => false,
    });
    expect(result).toEqual(AudioStreamErrorAction.retry());
  });

  it(
    "timeout (fetch never resolves within the deadline) -> inconclusive (undefined)",
    async () => {
      // Mimics a real `fetch`: it never settles on its own, but rejects once
      // the AbortController (wired via `init.signal`) fires — matching real
      // fetch's `AbortError` behavior for an aborted request.
      const fetch: FetchLike = (_input, init) =>
        new Promise((_resolve, reject) => {
          init?.signal?.addEventListener("abort", () => reject(new Error("AbortError")));
        });
      const result = await probeAudioStreamHttpStatus("https://x/track.mp3", {
        fetch,
        timeoutMs: 5,
        isOnline: () => true,
      });
      expect(result).toBeUndefined();
    },
    1000
  );

  it("opaque response (status 0, e.g. no-cors fallback) -> inconclusive (undefined)", async () => {
    const fetch: FetchLike = async () => okResponse(0);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toBeUndefined();
  });

  it("passes the expected HEAD request options", async () => {
    let seenInit: any;
    const fetch: FetchLike = async (_input, init) => {
      seenInit = init;
      return okResponse(200);
    };
    await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(seenInit.method).toBe("HEAD");
    expect(seenInit.mode).toBe("cors");
    expect(seenInit.credentials).toBe("omit");
    expect(seenInit.cache).toBe("no-store");
    expect(seenInit.signal).toBeDefined();
  });
});
