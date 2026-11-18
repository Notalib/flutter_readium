**Audio recovery waits longer and recovers from a loading timeout by default.**
`AudioRecoveryPolicy` now defaults to `stallTimeoutSeconds: 30` (was 20), `connectionTimeoutSeconds: 20` (was 10) and `recoverOnResourceLoadingTimeout: true` (was `false`), on iOS, Android and web.
A chapter that has not started playing after 30 seconds now rebuilds the player instead of only reporting `loading`. Pass `recoverOnResourceLoadingTimeout: false` to `setAudioRecoveryPolicy` to keep the old behaviour.
