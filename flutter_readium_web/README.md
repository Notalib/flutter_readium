# flutter_readium_web

A web extension for FlutterReadium.

## Getting Started

To use this plugin, follow these steps to ensure everything works correctly:

### 1. Copy the JavaScript File

To use the JavaScript file from the plugin in your Flutter web app, run the following command in your terminal from the root directory of your app:

```bash
dart run flutter_readium_web:copy_js_file <destination_directory>
```

It is recommended to place the destination directory within the `web` directory or a subdirectory of it. Avoid saving it outside the `web` directory.

### 2. Add Scripts to `index.html`

After copying the JavaScript file to your app, add Flutter's initialization JS code and the plugin JS to the `head` section of your `index.html` file:

```html
<!-- Flutter initialization JS code -->
<script src="flutter.js" defer></script>

<!-- Plugin JS code -->
<script src="readiumReader.js"></script>
```

If the plugin's JS file is not saved in the same directory as `index.html`, update the source path accordingly.

## Editing the Plugin

When making changes to the TypeScript files, convert the main TypeScript file (`ReadiumReader.ts`) to JavaScript using:

```bash
npm run build
```

Run this command from the root of the plugin.

To test the changes, follow the installation instructions in the example app directory.
