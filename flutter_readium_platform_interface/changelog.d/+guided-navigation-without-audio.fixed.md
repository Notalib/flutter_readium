**`isAudioBook` no longer reports text-only Guided Navigation as audio.**
Publications from Readium's publication server were flagged as audiobooks because the server links a text-only Guided Navigation document to every publication. `containsGuidedNavigation` now also requires audio files in the manifest.
