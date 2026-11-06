import globals from 'globals';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  {
    // Generated build artifacts may sit in the working tree and carry
    // eslint-disable comments for rules this config does not register.
    ignores: ['assets/helpers/**', 'assets/_helper_scripts/dist/**', 'build/**', 'example/build/**', 'lib/helpers/**'],
  },
  {
    files: ['web/src/**/*.ts'],
    // Tests shadow globals on purpose (mocked `fetch`), and they are not minified.
    ignores: ['web/src/__tests__/**'],
    languageOptions: {
      parser: tseslint.parser,
      globals: globals.browser,
    },
    // Sources carry disable comments for rules this config does not enable.
    linterOptions: { reportUnusedDisableDirectives: 'off' },
    plugins: { '@typescript-eslint': tseslint.plugin },
    rules: {
      // Terser can mangle a shadowing local and the global it shadows to the same name, so the
      // minified bundle reads the wrong variable (terser/terser#1698). `builtinGlobals` is needed
      // because the default setting ignores shadowed browser globals like `document`.
      '@typescript-eslint/no-shadow': ['error', { builtinGlobals: true }],
    },
  }
);
