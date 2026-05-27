# Custom HTTP Headers

Use `setCustomHeaders` to attach extra HTTP headers to every request the plugin makes against publication manifests and resources (chapter HTML, audio tracks, cover images, media-overlay JSON, etc.).

This is the standard way to authenticate against a private content server or to pass tenant / device identifiers.

```dart
await FlutterReadium().setCustomHeaders({
  'Authorization': 'Bearer $accessToken',
  'X-Tenant-Id': tenantId,
});
```

## Scope and lifecycle

- Headers are applied globally on the platform's Readium HTTP client — they affect **all** subsequent fetches, not just the next `openPublication` call.
- Headers persist for the lifetime of the plugin singleton. Call `setCustomHeaders` again with the new map to update; pass an empty map to clear:
  ```dart
  await FlutterReadium().setCustomHeaders({});
  ```
- Call `setCustomHeaders` **before** `openPublication` if the publication URL itself is gated by auth. Headers set after a publication is open will still apply to subsequent resource fetches, but the manifest request will already have completed.

## Refreshing an expiring token

If your server issues short-lived tokens, call `setCustomHeaders` again whenever the token rotates — typically from a refresh callback in your auth layer. There is no automatic refresh hook in the plugin.

## Platform support

| Platform | Support |
|----------|---------|
| iOS | Supported (via `setAdditionalHeaders` on the Readium HTTP client) |
| Android | Supported (via `setDefaultHttpHeaders`) |
| Web | **Not supported** — calling `setCustomHeaders` throws `UnimplementedError`. The browser fetches publication resources directly; use cookies, URL-signed tokens, or a same-origin proxy instead. |

## Common pitfalls

- **Per-publication headers**: not supported. The header set is global. If you need different auth for two publications opened back-to-back, change headers between calls.
- **CORS on Web**: Web-platform fetches are subject to browser CORS rules. Configure your content server to allow the app's origin and credentials.
