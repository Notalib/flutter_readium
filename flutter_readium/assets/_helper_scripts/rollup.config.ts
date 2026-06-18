import typescript from '@rollup/plugin-typescript';
import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import replace from '@rollup/plugin-replace';
import terser from '@rollup/plugin-terser';
import postcss from 'rollup-plugin-postcss';
import serve from 'rollup-plugin-serve';
import livereload from 'rollup-plugin-livereload';
import { defineConfig } from 'rollup';
import path from 'path';

const isFlutter = process.env.IS_FLUTTER === '1';
const isDev = process.env.NODE_ENV === 'development';
const outDir = isFlutter ? '../helpers' : 'dist';

function sharedPlugins(sourcemap) {
  return [
    replace({
      preventAssignment: true,
      'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV ?? 'production'),
      'process.env.IS_FLUTTER': JSON.stringify(process.env.IS_FLUTTER ?? '0'),
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

export default defineConfig(
  isDev
    ? [
        // 1. Demo UI shell (index.ts → dist/index.js) — hosts serve + livereload.
        {
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
            postcss({ extract: false }),
            serve({ contentBase: [outDir, 'public', 'node_modules/readium-css/css/dist'], port: 4200, open: true }),
            livereload(outDir),
          ],
        },
        // 2. Flutter helper script (FlutterReadiumTools.ts → dist/flutterReadiumTools.js)
        //    so that the iframe's `/flutterReadiumTools.js` request always gets a freshly
        //    built file and livereload fires on every source change.
        {
          input: 'src/FlutterReadiumTools.ts',
          output: {
            dir: outDir,
            entryFileNames: 'flutterReadiumTools.js',
            format: 'iife',
            name: 'flutterReadiumTools',
            sourcemap: 'inline',
          },
          plugins: [
            ...sharedPlugins(true),
            postcss({ extract: path.resolve(outDir, 'flutterReadiumTools.css'), minimize: false }),
          ],
        },
      ]
    : // Production / Flutter build: single bundle.
      {
        input: 'src/FlutterReadiumTools.ts',
        output: {
          dir: outDir,
          entryFileNames: 'flutterReadiumTools.js',
          format: 'iife',
          name: 'flutterReadiumTools',
          sourcemap: false,
        },
        plugins: [
          ...sharedPlugins(false),
          postcss({ extract: path.resolve(outDir, 'flutterReadiumTools.css'), minimize: true }),
          terser(),
        ],
      },
);
