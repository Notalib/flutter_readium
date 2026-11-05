**Android: app assets passed to `setCssInjections`/`setJavaScriptInjections` never loaded in EPUBs.**
The `<link>`/`<script>` tags were injected, but the navigator only served the plugin's own assets and font faces, so the WebView received a "not found" page instead. Injected app assets are now served as well; a path missing from the app bundle is skipped with a warning.
