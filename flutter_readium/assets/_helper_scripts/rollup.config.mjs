import typescript from '@rollup/plugin-typescript';
import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import replace from '@rollup/plugin-replace';
import terser from '@rollup/plugin-terser';
import postcss from 'rollup-plugin-postcss';
import serve from 'rollup-plugin-serve';
import livereload from 'rollup-plugin-livereload';
import { visualizer } from 'rollup-plugin-visualizer';
import { defineConfig } from 'rollup';
import path from 'path';

const isServe = process.env.SERVE === 'true';
const isDev = process.env.BUILD === 'development';
const isProd = process.env.BUILD === 'production';
const writeStats = process.env.STATS === 'true';

const outDir = !isServe ? '../helpers' : 'dist';
const postcssSassOptions = {
  // rollup-plugin-postcss still uses Sass's legacy render API internally.
  // Silence that known deprecation until the plugin migrates upstream.
  use: {
    sass: {
      silenceDeprecations: ['legacy-js-api'],
    },
  },
};

function statsPlugins() {
  if (!writeStats) {
    return [];
  }

  const htmlOutputPath = path.resolve(outDir, 'stats.html');
  const jsonOutputPath = path.resolve(outDir, 'stats.json');

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

function sharedPlugins(sourcemap) {
  return [
    replace({
      preventAssignment: true,
      'process.env.SERVE': JSON.stringify(process.env.SERVE ?? 'false'),
      'process.env.IS_FLUTTER': JSON.stringify(process.env.IS_FLUTTER ?? 'false'),
    }),
    resolve({ browser: true }),
    commonjs(),
    typescript({
      tsconfig: './tsconfig.rollup.json',
      sourceMap: sourcemap,
      inlineSources: sourcemap,
      compilerOptions: { outDir: outDir },
    }),
  ];
}

function defineServeConfig() {
  return {
    input: 'src/index.ts',
    output: {
      dir: outDir,
      entryFileNames: '[name].js',
      format: 'iife',
      name: 'flutterReadiumTools',
      sourcemap: 'inline',
    },
    plugins: [
      ...sharedPlugins(true),
      postcss({ extract: false, ...postcssSassOptions }),
      serve({ contentBase: [outDir, 'public', 'node_modules/readium-css/css/dist'], port: 4200, open: true }),
      livereload(outDir),
      ...statsPlugins(),
    ],
  };
}

function defineFlutterReadiumToolsConfig(sourcemap, minimize) {
  return {
    input: 'src/FlutterReadiumTools.ts',
    output: {
      dir: outDir,
      entryFileNames: 'flutterReadiumTools.js',
      format: 'iife',
      name: 'flutterReadiumTools',
      sourcemap: sourcemap ? 'inline' : false,
    },
    plugins: [
      ...sharedPlugins(sourcemap),
      postcss({ extract: path.resolve(outDir, 'flutterReadiumTools.css'), minimize: minimize, ...postcssSassOptions }),
      minimize ? terser() : undefined,
      ...statsPlugins(),
    ],
  };
}

export default defineConfig(
  isServe
    ? [defineServeConfig(), defineFlutterReadiumToolsConfig(isProd, !isDev)]
    : [defineFlutterReadiumToolsConfig(isProd, !isDev)]
);
