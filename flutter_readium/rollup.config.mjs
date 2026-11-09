import terser from '@rollup/plugin-terser';
import postcss from 'rollup-plugin-postcss';
import { basePlugins, statsPlugins } from './rollup.shared.mjs';

const isDev = process.env.BUILD === 'development';
const isProd = process.env.BUILD === 'production';

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
    ...basePlugins({
      replacements: {
        'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV ?? 'production'),
      },
      tsconfigPath: './web/src/tsconfig.rollup.json',
      sourcemap: isDev,
    }),
    // Inject CSS into the bundle at runtime (equivalent to webpack's style-loader).
    // The webview loads only readiumReader.js, so CSS must not be extracted to a
    // separate file.
    postcss({ inject: true, minimize: !isDev }),
    isProd ? terser({
      compress: {
        pure_funcs: ['console.log'],
      },
    }) : null,
    ...statsPlugins('build', 'rollup-stats'),
  ],
};
