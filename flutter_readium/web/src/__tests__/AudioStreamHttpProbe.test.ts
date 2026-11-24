/**
 * Unit tests for the HTTP diagnostic probe that upgrades web audio-streaming
 * error classification beyond the generic `MediaError` code (see
 * `AudioStreamErrorPolicy.test.ts` for the base classifier).
 *
 * `fetch` and `isOnline` are injected so these run under
 * `testEnvironment: "node"` with no browser globals.
 */

import { AudioStreamErrorAction } from "../navigators/AudioStreamErrorPolicy";
import { probeAudioStreamHttpStatus, ProbeResponse } from "../navigators/AudioStreamHttpProbe";

type FetchLike = (input: string, init?: any) => Promise<ProbeResponse>;

function okResponse(status: number, contentLength?: string): ProbeResponse {
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: { get: (name) => (name === "Content-Length" ? contentLength ?? null : null) },
  };
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

  it.each([404, 410])("HEAD %i -> HTTP error, reason missing", async (status) => {
    const fetch: FetchLike = async () => okResponse(status);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", status, "missing"));
  });

  it("HEAD 416 -> reason empty", async () => {
    const fetch: FetchLike = async () => okResponse(416);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", 416, "empty"));
  });

  it.each([400, 408, 429])("HEAD %i (not a proven defect) -> fail(AudioStreamHTTPError)", async (status) => {
    const fetch: FetchLike = async () => okResponse(status);
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", status));
  });

  it("HEAD 200 with Content-Length 0 is confirmed by a ranged GET answering 416 -> reason empty", async () => {
    const methods: string[] = [];
    const fetch: FetchLike = async (_input, init) => {
      methods.push(init?.method);
      return init?.method === "HEAD" ? okResponse(200, "0") : okResponse(416);
    };
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", 416, "empty"));
    expect(methods).toEqual(["HEAD", "GET"]);
  });

  it("HEAD and GET both 200 with Content-Length 0 -> reason empty", async () => {
    const fetch: FetchLike = async () => okResponse(200, "0");
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamError", 200, "empty"));
  });

  it("an empty HEAD contradicted by a ranged GET with content -> retry", async () => {
    const fetch: FetchLike = async (_input, init) =>
      init?.method === "HEAD" ? okResponse(200, "0") : okResponse(206, "1");
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.retry());
  });

  it("an empty HEAD with an unreachable GET is inconclusive, never a defect", async () => {
    const fetch: FetchLike = async (_input, init) => {
      if (init?.method === "GET") throw new TypeError("network error");
      return okResponse(200, "0");
    };
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch, isOnline: () => true });
    expect(result).toBeUndefined();
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

  describe("after a decode error", () => {
    function served(status: number, contentType: string): FetchLike {
      return async () => ({
        status,
        ok: status >= 200 && status < 300,
        headers: { get: (name) => (name === "Content-Type" ? contentType : null) },
      });
    }

    it("2xx served as audio -> reason undecodable", async () => {
      const fetch = served(200, "audio/mpeg; charset=binary");
      const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch, decodeError: true });
      expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamError", 200, "undecodable"));
    });

    it("2xx served as HTML (captive portal) -> fatal without a reason", async () => {
      const fetch = served(200, "text/html");
      const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch, decodeError: true });
      expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamError", 200));
    });

    it("2xx served as generic binary (application/octet-stream) -> fatal without a reason", async () => {
      const fetch = served(200, "application/octet-stream");
      const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch, decodeError: true });
      expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamError", 200));
    });

    it("404 -> reason missing", async () => {
      const fetch = served(404, "text/html");
      const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch, decodeError: true });
      expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", 404, "missing"));
    });
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

  it("HEAD network failure falls back to GET+Range, which reports 404", async () => {
    let call = 0;
    const fetch: FetchLike = async (_input, init) => {
      call++;
      if (init?.method === "HEAD") throw new TypeError("network error");
      return okResponse(404);
    };
    const result = await probeAudioStreamHttpStatus("https://x/track.mp3", { fetch });
    expect(result).toEqual(AudioStreamErrorAction.fail("AudioStreamHTTPError", 404, "missing"));
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
