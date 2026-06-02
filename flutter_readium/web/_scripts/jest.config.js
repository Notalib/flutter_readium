const path = require("path");

module.exports = {
  rootDir: __dirname,
  testEnvironment: "node",
  testMatch: ["<rootDir>/__tests__/**/*.test.ts"],
  transform: {
    "^.+\\.ts$": [
      "ts-jest",
      { tsconfig: path.resolve(__dirname, "tsconfig.test.json") },
    ],
  },
};
