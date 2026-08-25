import Foundation
import ReadiumShared

enum LinkTemplateResolutionError: Error, Equatable, CustomStringConvertible {
  case missingVariables([String])
  case invalidTemplate
  case invalidHref

  var description: String {
    switch self {
    case .missingVariables(let variables):
      return "missing variables: \(variables.joined(separator: ", "))"
    case .invalidTemplate:
      return "invalid URI template syntax"
    case .invalidHref:
      return "expanded href is not fetchable"
    }
  }
}

enum LinkTemplateResolver {
  private static let failureReporter = FailureReporter()

  static func resolve(
    _ link: Link,
    parameters: [String: String] = [:]
  ) -> Result<Link, LinkTemplateResolutionError> {
    guard link.templated else {
      return .success(link)
    }

    guard isValidTemplate(link.href) else {
      return .failure(.invalidTemplate)
    }

    let missing = link.templateParameters.filter { parameters[$0] == nil }.sorted()
    guard missing.isEmpty else {
      return .failure(.missingVariables(missing))
    }

    var resolved = link
    resolved.expandTemplate(with: parameters)
    guard !resolved.href.contains("{"), !resolved.href.contains("}") else {
      return .failure(.invalidTemplate)
    }
    guard !resolved.href.isEmpty else {
      return .failure(.invalidHref)
    }
    return .success(resolved)
  }

  static func shouldReport(
    _ link: Link,
    error: LinkTemplateResolutionError
  ) -> Bool {
    failureReporter.shouldReport("\(link.href)|\(error)")
  }

  static func parameters(
    for resourceLink: Link?,
    sidecarLink: Link? = nil
  ) -> [String: String] {
    guard let resourceLink else {
      return [:]
    }

    var parameters = [
      "ref": resourceLink.href,
      "resource": resourceLink.href,
    ]
    if let fragmentStart = resourceLink.href.firstIndex(of: "#") {
      let idStart = resourceLink.href.index(after: fragmentStart)
      if idStart < resourceLink.href.endIndex {
        parameters["id"] = String(resourceLink.href[idStart...])
      }
    }
    if let sidecarLink {
      parameters["mediaOverlay"] = sidecarLink.href
      parameters["media-overlay"] = sidecarLink.href
    }
    return parameters
  }

  private static func isValidTemplate(_ href: String) -> Bool {
    var cursor = href.startIndex

    while let open = href[cursor...].firstIndex(of: "{") {
      guard let close = href[open...].firstIndex(of: "}") else {
        return false
      }
      if href[open...].dropFirst().firstIndex(of: "{") != nil,
         href[open...].dropFirst().firstIndex(of: "{")! < close {
        return false
      }

      let bodyStart = href.index(after: open)
      let body = String(href[bodyStart..<close])
      let variables = body.hasPrefix("?") ? String(body.dropFirst()) : body
      guard !variables.isEmpty else {
        return false
      }
      guard body.hasPrefix("?") || !body.hasPrefix("#") else {
        return false
      }
      guard variables.split(separator: ",").allSatisfy({
        $0.range(of: #"^[A-Za-z][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
      }) else {
        return false
      }

      cursor = href.index(after: close)
      if cursor == href.endIndex {
        break
      }
    }

    return !href[cursor...].contains("}")
  }
}

private final class FailureReporter: @unchecked Sendable {
  private let lock = NSLock()
  private var reportedKeys = Set<String>()

  func shouldReport(_ key: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return reportedKeys.insert(key).inserted
  }
}
