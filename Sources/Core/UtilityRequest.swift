import Foundation

enum UtilityAction: String, CaseIterable {
  case clipboardText, clipboardMarkdown, clipboardPNG
  case copyPaths, copyNames, sendCopy, sendMove, terminal

  var usesSelection: Bool {
    [.copyPaths, .copyNames, .sendCopy, .sendMove].contains(self)
  }
}

struct UtilityRequest {
  let action: UtilityAction
  let paths: [URL]

  init(action: UtilityAction, paths: [URL]) {
    self.action = action
    self.paths = paths
  }

  private func validate() throws {
    guard !paths.isEmpty, paths.count <= (action.usesSelection ? 128 : 1),
      paths.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") && !$0.path.contains("\0") })
    else { throw NoteError.invalidRequest }

  }

  init(url: URL) throws {
    guard url.absoluteString.utf8.count <= 65_536,
      let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "newmemo", parts.host == "utility", parts.user == nil,
      parts.password == nil, parts.port == nil, parts.fragment == nil,
      parts.path.isEmpty || parts.path == "/", let items = parts.queryItems,
      items.allSatisfy({ ["action", "path"].contains($0.name) }),
      items.filter({ $0.name == "action" }).count == 1,
      let raw = items.first(where: { $0.name == "action" })?.value,
      let action = UtilityAction(rawValue: raw)
    else { throw NoteError.invalidRequest }
    let pathItems = items.filter { $0.name == "path" }
    guard
      pathItems.allSatisfy({
        $0.value?.hasPrefix("/") == true && $0.value?.contains("\0") == false
      })
    else { throw NoteError.invalidRequest }
    self.init(action: action, paths: pathItems.map { URL(fileURLWithPath: $0.value!) })
    try validate()
  }

  var url: URL? {
    guard (try? validate()) != nil else { return nil }
    var parts = URLComponents()
    parts.scheme = "newmemo"
    parts.host = "utility"
    parts.queryItems =
      [URLQueryItem(name: "action", value: action.rawValue)]
      + paths.map { URLQueryItem(name: "path", value: $0.path) }
    guard let url = parts.url, url.absoluteString.utf8.count <= 65_536 else { return nil }
    return url
  }
}
