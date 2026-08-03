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
