**Web: reader helpers and custom fonts now load in builds made with `--web-content-hash`.**
Flutter 3.50's `flutter build web --web-content-hash` renames every asset file, so the EPUB helper scripts and `ReaderFontFamily` fonts, which were fetched by their unhashed paths, returned 404. Their URLs now come from Flutter's asset manager and work with or without the flag.
