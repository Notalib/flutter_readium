const path = require("path");

module.exports = {
  rootDir: __dirname,
  testEnvironment: "node",
  testMatch: ["<rootDir>/__tests__/**/*.test.ts"],
  moduleNameMapper: {
    "^@readium/shared$": "<rootDir>/../../node_modules/@readium/shared/dist/index.js",
    "^@readium/navigator$": "<rootDir>/../../node_modules/@readium/navigator/dist/index.js",
    "^@readium/navigator-html-injectables$": "<rootDir>/../../node_modules/@readium/navigator-html-injectables/dist/index.js",
    "^@readium/decorator$": "<rootDir>/../../node_modules/@readium/decorator/dist/index.js",
    "^@readium/helpers$": "<rootDir>/../../node_modules/@readium/helpers/dist/index.js",
    "^@readium/guided-navigation$": "<rootDir>/../../node_modules/@readium/guided-navigation/dist/index.js",
    "^@readium/shared/html$": "<rootDir>/../../node_modules/@readium/shared/dist/publication/html/index.js",
    // Its CommonJS build reads `self` at load time, which the node test environment lacks.
    "^css-selector-generator$": "<rootDir>/../../node_modules/css-selector-generator/esm/index.js",
    "\\.css$": "<rootDir>/__tests__/style.stub.js",
  },
  transform: {
    "^.+\\.ts$": [
      "ts-jest",
      { tsconfig: path.resolve(__dirname, "tsconfig.test.json") },
    ],
    "^.+\\.js$": [
      "babel-jest",
      {
        presets: [
          ["@babel/preset-env", { targets: { node: "current" } }],
        ],
      },
    ],
  },
  transformIgnorePatterns: [],
};
