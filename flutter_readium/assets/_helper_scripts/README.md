# JavaScript helpers for Readium publication rendering

## Getting started

Make sure to have NodeJs already installed.

### Install all dependencies

This package is an npm workspace member of `flutter_readium/` (the workspace
root, which owns the single `package-lock.json` and hoisted `node_modules`).
Install from the workspace root, never here:

```bash
cd ../.. && npm install
```

### Start developing and serve your app

```bash
npm run serve
```

### Build your application

```bash
npm run build
```

### Build in development mode

```bash
npm run build:dev
```

### Build with dependency size reports

```bash
npm run build:stats
```

This generates bundle analysis reports in `../helpers/`:

- `stats.html` (interactive treemap)
- `stats.json` (raw data)
