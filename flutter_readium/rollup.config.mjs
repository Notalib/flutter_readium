import typescript from '@rollup/plugin-typescript';
import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import replace from '@rollup/plugin-replace';
import terser from '@rollup/plugin-terser';
import postcss from 'rollup-plugin-postcss';
import { visualizer } from 'rollup-plugin-visualizer';

const isDev = process.env.NODE_ENV === 'development';
const writeStats = process.env.STATS === '1';

function statsPlugins() {
  if (!writeStats) {
    return [];
  }

  return [
    visualizer({
      filename: 'build/rollup-stats.html',
      template: 'treemap',
      gzipSize: true,
      brotliSize: true,
      projectRoot: process.cwd(),
    }),
    visualizer({
      filename: 'build/rollup-stats.json',
      template: 'raw-data',
      gzipSize: true,
      brotliSize: true,
      projectRoot: process.cwd(),
    }),
  ];
}

export default {
  input: 'web/src/index.ts',
  output: {
    file: 'lib/helpers/readiumReader.js',
    format: 'iife',
    name: 'flutterReadiumBundle',
    sourcemap: isDev ? 'inline' : false,
    // Inline all dynamic imports (e.g. ReadiumCSS variants in @readium/navigator)
    // into the single bundle rather than emitting separate chunk files.
    inlineDynamicImports: true,
  },
  plugins: [
    replace({
      preventAssignment: true,
      'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV ?? 'production'),
    }),
    resolve({ browser: true }),
    commonjs(),
    typescript({
      tsconfig: './web/src/tsconfig.rollup.json',
      sourceMap: isDev,
      inlineSources: isDev,
    }),
    // Inject CSS into the bundle at runtime (equivalent to webpack's style-loader).
    // The webview loads only readiumReader.js, so CSS must not be extracted to a
    // separate file.
    postcss({ inject: true, minimize: !isDev }),
    ...(isDev
      ? []
      : [
          terser({
            compress: {
              pure_funcs: ['console.log'],
            },
          }),
        ]),
    ...statsPlugins(),
  ],
};
