/**
 * Typed error carried across the JS↔Dart method-call boundary.
 *
 * `js_publication_channel.dart`'s `_platformExceptionForJsError` reads `.code`
 * (and `.details`) directly off the thrown/rejected JS object, so callers no
 * longer need to string-match `.message`. Wire values must match
 * `flutter_readium_platform_interface`'s `ReadiumErrorCode` (case-insensitive)
 * — or `InvalidArgument`, which is caller-misuse and passed through raw by the
 * Dart wrapper. See `docs/api-reference/error-codes.md`.
 */
export class ReadiumWebError extends Error {
  readonly code: string;
  readonly details?: Record<string, unknown>;

  constructor(message: string, code: string, details?: Record<string, unknown>) {
    super(message);
    this.name = "ReadiumWebError";
    this.code = code;
    this.details = details;
  }
}

/** Wire vocabulary this module emits. Keep in sync with `ReadiumErrorCode` + `InvalidArgument`. */
export const ReadiumWebErrorCode = {
  /** Caller misuse (bad locator JSON, unknown href, invalid preference payload). Not in the shared vocabulary — passed through raw. */
  invalidArgument: "InvalidArgument",
  /** No navigator/publication is open for an operation that requires one. */
  noPublication: "NoPublication",
  /** A publication resource failed to load/resolve. Pair with `details.reason`. */
  resourceReadError: "ResourceReadError",
  voiceNotFound: "VoiceNotFound",
  audioStreamNetworkError: "AudioStreamNetworkError",
} as const;

/**
 * `details.reason` values this module sets alongside `resourceReadError`.
 * Producer-specific hint, not a strict cross-platform enum (see
 * `docs/api-reference/error-codes.md#detailsreason`) — kept as constants
 * purely so call sites aren't raw string literals a typo could slip past.
 */
export const ResourceReadErrorReason = {
  /** No manifest entry matches the requested href. */
  notFound: "notFound",
  /** The matched link's href didn't resolve to an absolute served URL. */
  urlResolution: "urlResolution",
  /** `goLink` reported the navigation as unsuccessful. */
  navigation: "navigation",
  /** `Manifest.deserialize` returned null for a Media Overlay manifest. */
  manifestDeserialization: "manifestDeserialization",
} as const;
