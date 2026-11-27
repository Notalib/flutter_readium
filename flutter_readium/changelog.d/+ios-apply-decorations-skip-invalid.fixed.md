**iOS: one invalid decoration dropped its whole group.**
A decoration that failed to parse made the call fail with a `JSON mapping error`, so none of the group was shown. iOS now skips and logs that decoration and applies the rest, matching Android and web.
