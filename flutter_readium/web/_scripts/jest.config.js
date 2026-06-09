const path = require("path");

module.exports = {
  rootDir: __dirname,
  testEnvironment: "node",
  testMatch: ["<rootDir>/__tests__/**/*.test.ts"],
  // CSS side-effect imports (e.g. `import "./style.css"` in ReadiumReader.ts)
  // have no runtime meaning under ts-jest — map them to an empty stub.
  moduleNameMapper: {
    "\\.css$": "<rootDir>/__tests__/style.stub.js",
  },
  transform: {
    "^.+\\.ts$": [
      "ts-jest",
      { tsconfig: path.resolve(__dirname, "tsconfig.test.json") },
    ],
  },
};
