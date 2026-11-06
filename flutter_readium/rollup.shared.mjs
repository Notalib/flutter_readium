// Rollup plugin plumbing shared by the web bundle config (rollup.config.mjs)
// and the webview helper config (assets/_helper_scripts/rollup.config.mjs).
import typescript from '@rollup/plugin-typescript';
import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import replace from '@rollup/plugin-replace';
import { visualizer } from 'rollup-plugin-visualizer';
import * as path from 'path';

const writeStats = process.env.STATS === 'true';

export function basePlugins({ replacements, tsconfigPath, sourcemap, ...extra }) {
  return [
    replace({
      preventAssignment: true,
      ...replacements,
    }),
    resolve({ browser: true }),
    commonjs(),
    typescript({
      tsconfig: tsconfigPath,
      sourceMap: sourcemap,
      inlineSources: sourcemap,
      ...extra,
    }),
  ];
}

export function statsPlugins(outDir, basename = 'stats') {
  if (!writeStats) {
    return [];
  }

  const htmlOutputPath = path.resolve(outDir, `${basename}.html`);
  const jsonOutputPath = path.resolve(outDir, `${basename}.json`);

  console.log(`Writing rollup stats to ${htmlOutputPath} and ${jsonOutputPath}`);

  return [
    visualizer({
      filename: htmlOutputPath,
      template: 'treemap',
      gzipSize: true,
      brotliSize: true,
      projectRoot: process.cwd(),
    }),
    visualizer({
      filename: jsonOutputPath,
      template: 'raw-data',
      gzipSize: true,
      brotliSize: true,
      projectRoot: process.cwd(),
    }),
  ];
}
