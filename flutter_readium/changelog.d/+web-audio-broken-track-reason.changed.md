**Web: a fatal audio error for a track that is broken in the publication now carries `details.reason`.**
`reason` is `missing` (404/410), `empty` (416, or an empty body) or `undecodable` (decode error), so an app can report the content defect, for example to Sentry.
An empty 2xx body, previously retried until recovery gave up, now fails at once as `AudioStreamError`. A 5xx or unreachable server is still retried.
