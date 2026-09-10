/**
 * Regression tests for the logger's debug sink.
 *
 * `flutter drive` hardcodes the chromedriver browser log level to INFO, so
 * console.debug output is dropped before the test driver captures it and a
 * debug line looks like code that never ran. Under WebDriver the logger must
 * fall back to console.log; everywhere else it must keep console.debug so the
 * lines stay under DevTools' "Verbose" filter.
 */

/** Re-imports the logger with `navigator.webdriver` already set. */
function loadLogger(webdriver: boolean): typeof import("../utils/ReadiumPluginLogger") {
  jest.resetModules();
  Object.defineProperty(globalThis, "navigator", {
    value: { webdriver },
    configurable: true,
    writable: true,
  });
  return require("../utils/ReadiumPluginLogger");
}

describe("logger debug sink", () => {
  const savedNavigator = Object.getOwnPropertyDescriptor(globalThis, "navigator");

  afterEach(() => {
    jest.restoreAllMocks();
    if (savedNavigator) Object.defineProperty(globalThis, "navigator", savedNavigator);
    else delete (globalThis as { navigator?: unknown }).navigator;
  });

  it("routes debug through console.log under WebDriver", () => {
    const logger = loadLogger(true);
    logger.setLogLevel(logger.LogLevel.debug);
    const consoleLog = jest.spyOn(console, "log").mockImplementation(() => {});
    const consoleDebug = jest.spyOn(console, "debug").mockImplementation(() => {});

    logger.createLogger("Test").debug("hello");

    expect(consoleDebug).not.toHaveBeenCalled();
    expect(consoleLog).toHaveBeenCalledTimes(1);
    expect(consoleLog.mock.calls[0][0]).toContain("DEBUG [Readium/Test] hello");
  });

  it("keeps console.debug in a normal browser", () => {
    const logger = loadLogger(false);
    logger.setLogLevel(logger.LogLevel.debug);
    const consoleLog = jest.spyOn(console, "log").mockImplementation(() => {});
    const consoleDebug = jest.spyOn(console, "debug").mockImplementation(() => {});

    logger.createLogger("Test").debug("hello");

    expect(consoleLog).not.toHaveBeenCalled();
    expect(consoleDebug).toHaveBeenCalledTimes(1);
    expect(consoleDebug.mock.calls[0][0]).toContain("DEBUG [Readium/Test] hello");
  });

  it("stays silent below debug level", () => {
    const logger = loadLogger(true);
    logger.setLogLevel(logger.LogLevel.info);
    const consoleLog = jest.spyOn(console, "log").mockImplementation(() => {});

    logger.createLogger("Test").debug("hello");

    expect(consoleLog).not.toHaveBeenCalled();
  });
});
