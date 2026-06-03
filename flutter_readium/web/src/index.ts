/**
 * Webpack entry point.
 *
 * Imports ReadiumReader.ts which:
 *  - registers globalThis.ReadiumReader (the Dart↔JS contract)
 *  - installs the style.css
 */
export * from "./ReadiumReader";
