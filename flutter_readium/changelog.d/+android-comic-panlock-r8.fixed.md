**Android: panning a zoomed comic page turned the page in minified release builds.**
The pan-lock looked up PhotoView classes by name, and R8 renamed them, so the lock silently switched itself off.
The plugin now calls PhotoView directly, so the lock works with or without minification and needs no keep rules.
