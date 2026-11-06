import terser from '@rollup/plugin-terser';
import postcss from 'rollup-plugin-postcss';
import serve from 'rollup-plugin-serve';
import livereload from 'rollup-plugin-livereload';
import { basePlugins, statsPlugins } from '../../rollup.shared.mjs';
import { defineConfig } from 'rollup';
import path from 'path';

const isServe = process.env.SERVE === 'true';
const isDev = process.env.BUILD === 'development';
const isProd = process.env.BUILD === 'production';

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

function sharedPlugins(sourcemap) {
  return basePlugins({
    replacements: {
      'process.env.SERVE': JSON.stringify(process.env.SERVE ?? 'false'),
      'process.env.IS_FLUTTER': JSON.stringify(process.env.IS_FLUTTER ?? 'false'),
    },
    tsconfigPath: './tsconfig.rollup.json',
    sourcemap,
    compilerOptions: { outDir: outDir },
  });
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
      serve({ contentBase: [outDir, 'public', 'node_modules/@readium/css/css/dist', '../../node_modules/@readium/css/css/dist'], port: 4200, open: true }),
      livereload(outDir),
      ...statsPlugins(outDir),
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
      ...statsPlugins(outDir),
    ],
  };
}

export default defineConfig(
  isServe
    ? [defineServeConfig(), defineFlutterReadiumToolsConfig(isProd, !isDev)]
    : [defineFlutterReadiumToolsConfig(isProd, !isDev)]
);
