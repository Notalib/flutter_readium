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
const isProd = !isDev;
const outDir = isFlutter ? '../helpers' : 'dist';

export default defineConfig({
  input: isDev ? 'src/index.ts' : 'src/FlutterReadiumTools.ts',
  output: {
    dir: outDir,
    entryFileNames: isDev ? '[name].js' : 'flutterReadiumTools.js',
    format: 'iife',
    name: 'flutterReadiumTools',
    sourcemap: isDev ? 'inline' : false,
  },
  plugins: [
    replace({
      preventAssignment: true,
      'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV ?? 'production'),
      'process.env.IS_FLUTTER': JSON.stringify(process.env.IS_FLUTTER ?? '0'),
    }),
    postcss({
      extract: isProd ? path.resolve(outDir, 'flutterReadiumTools.css') : false,
      minimize: isProd,
    }),
    resolve({ browser: true }),
    commonjs(),
    typescript({
      tsconfig: './tsconfig.rollup.json',
      sourceMap: isDev,
      inlineSources: isDev,
      compilerOptions: { outDir: outDir },
    }),
    ...(isProd ? [terser()] : []),
    ...(isDev
      ? [serve({ contentBase: [outDir, 'public'], port: 4200, open: true }), livereload(outDir)]
      : []),
  ],
});
