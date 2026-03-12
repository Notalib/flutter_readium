import os

internal enum Log {
  static let readium = ReadiumPluginLogger()
  static let reader = ReadiumPluginLogger(category: "reader")
  static let navigator = ReadiumPluginLogger(category: "navigator")
  static let toc = ReadiumPluginLogger(category: "toc")
}

internal enum LogLevel: Int {
  case none = 0
  case error
  case warn
  case info
  case debug
}

internal class ReadiumPluginLogger {
  
  static var level: LogLevel = .info
  
  private let logger: Logger
  
  init(subsystem: String = "dk.nota.flutter_readium", category: String = "plugin") {
    self.logger = Logger(subsystem: subsystem, category: category)
  }
  
  private static let logger = Logger(
    subsystem: "dk.nota.flutter_readium",
    category: "plugin"
  )
  // MARK: - Error
  
  func error(
    _ message: @autoclosure @escaping () -> String,
    file: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
    guard Self.level.rawValue >= LogLevel.error.rawValue else { return }
    
    logger.error(
      "[\(file):\(line)] \(function) – \(message(), privacy: .public)"
    )
  }
  
  // MARK: - Warn
  
  func warn(
    _ message: @autoclosure @escaping () -> String,
    file: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
    guard Self.level.rawValue >= LogLevel.warn.rawValue else { return }
    
    logger.warning(
      "[\(file):\(line)] \(function) – \(message(), privacy: .public)"
    )
  }
  
  // MARK: - Info
  
  func info(
    _ message: @autoclosure @escaping () -> String,
    file: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
    guard Self.level.rawValue >= LogLevel.info.rawValue else { return }
    
    logger.info(
      "[\(file):\(line)] \(function) – \(message(), privacy: .public)"
    )
  }
  
  // MARK: - Debug
  
  func debug(
    _ message: @autoclosure @escaping () -> String,
    file: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
#if DEBUG
    guard Self.level.rawValue >= LogLevel.debug.rawValue else { return }
    
    logger.debug(
      "[\(file):\(line)] \(function) – \(message(), privacy: .public)"
    )
#endif
  }
}
