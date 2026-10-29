import Darwin
import Foundation

enum NoteKind: String, CaseIterable {
  case markdown = "md"
  case text = "txt"

  var title: String { self == .markdown ? "Markdown (.md)" : "텍스트 (.txt)" }
  var defaultBasename: String { "새 메모" }
}

enum NoteError: LocalizedError {
  case invalidDirectory, invalidName, invalidRequest, tooManyFiles
  var errorDescription: String? {
    switch self {
    case .invalidDirectory: return "파일을 만들 수 있는 폴더를 선택해 주세요."
    case .invalidName: return "파일 이름에는 /, :, 제어 문자나 너무 긴 이름을 사용할 수 없습니다."
    case .invalidRequest: return "올바르지 않은 파일 생성 요청입니다."
    case .tooManyFiles: return "같은 이름의 파일이 너무 많습니다. 다른 이름을 사용해 주세요."
    }
  }
}

enum NoteFiles {
  /// mkdir allocates atomically and never replaces an existing file, directory or symlink.
  static func createFolder(in directory: URL, basename: String = "새 폴더") throws -> URL {
    try validateBasename(basename)
    guard directory.isFileURL else { throw NoteError.invalidDirectory }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw NoteError.invalidDirectory }
    for index in 1...10_000 {
      let name = index == 1 ? basename : "\(basename) \(index)"
      let folder = directory.appendingPathComponent(name, isDirectory: true)
      let result = folder.withUnsafeFileSystemRepresentation { path in
        path.map { Darwin.mkdir($0, 0o777) } ?? -1
      }
      if result == 0 { return folder }
      let code = errno
      if code == EEXIST { continue }
      throw NSError(
        domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: folder.path])
    }
    throw NoteError.tooManyFiles
  }

  /// O_EXCL makes allocation atomic: existing files and symlinks are never replaced.
  static func create(in directory: URL, kind: NoteKind, basename: String? = nil) throws -> URL {
    let preset = FilePreset(
      id: kind.rawValue, name: kind.title, fileExtension: kind.rawValue,
      basename: (basename ?? kind.defaultBasename).trimmingCharacters(in: .whitespacesAndNewlines),
      template: "", isEnabled: true)
    return try create(in: directory, preset: preset)
  }

  static func validateBasename(_ name: String) throws {
    guard !name.isEmpty, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
      name != ".", name != "..", name.decomposedStringWithCanonicalMapping.utf8.count <= 230,
      name.rangeOfCharacter(from: .controlCharacters) == nil,
      name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil
    else {
      throw NoteError.invalidName
    }
  }

  static func create(in directory: URL, preset: FilePreset) throws -> URL {
    try preset.validate()
    return try createData(
      Data(preset.template.utf8), in: directory,
      basename: preset.basename, fileExtension: preset.fileExtension)
  }

  /// Shares the exclusive writer and inode-checked failure cleanup with text creation.
  static func createData(
    _ contents: Data, in directory: URL, basename: String, fileExtension: String
  ) throws -> URL {
    try FilePreset(
      id: "data", name: "파일", fileExtension: fileExtension,
      basename: basename, template: "", isEnabled: true
    ).validate()
    guard directory.isFileURL else { throw NoteError.invalidDirectory }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw NoteError.invalidDirectory }
    let name = basename

    for index in 1...10_000 {
      let suffix = index == 1 ? "" : " \(index)"
      let ext = fileExtension.isEmpty ? "" : ".\(fileExtension)"
      let file = directory.appendingPathComponent("\(name)\(suffix)\(ext)")
      let descriptor = file.withUnsafeFileSystemRepresentation { path in
        path.map { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644) } ?? -1
      }
      if descriptor >= 0 {
        var allocated = stat()
        let hasIdentity = fstat(descriptor, &allocated) == 0
        var isOpen = true
        do {
          try contents.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
              let written = Darwin.write(
                descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
              if written < 0 && errno == EINTR { continue }
              guard written > 0 else {
                throw NSError(
                  domain: NSPOSIXErrorDomain, code: Int(written == 0 ? EIO : errno),
                  userInfo: [NSFilePathErrorKey: file.path])
              }
              offset += written
            }
          }
          let closeResult = Darwin.close(descriptor)
          isOpen = false
          guard closeResult == 0 else {
            throw NSError(
              domain: NSPOSIXErrorDomain, code: Int(errno),
              userInfo: [NSFilePathErrorKey: file.path])
          }
          return file
        } catch {
          // Only remove the inode allocated by this request, never a replaced path.
          var current = stat()
          if isOpen { Darwin.close(descriptor) }
          if hasIdentity, lstat(file.path, &current) == 0,
            current.st_dev == allocated.st_dev, current.st_ino == allocated.st_ino
          {
            _ = unlink(file.path)
          }
          throw error
        }
      }
      let code = errno
      if code == EEXIST { continue }
      throw NSError(
        domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: file.path])
    }
    throw NoteError.tooManyFiles
  }
}

struct FolderCreateRequest {
  let directory: URL

  init(directory: URL) { self.directory = directory }

  init(url: URL) throws {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "newmemo", parts.host == "create-folder", parts.user == nil,
      parts.password == nil, parts.port == nil, parts.fragment == nil,
      parts.path.isEmpty || parts.path == "/",
      let items = parts.queryItems, items.count == 1, items[0].name == "directory",
      let path = items[0].value, path.hasPrefix("/"), !path.contains("\0")
    else { throw NoteError.invalidRequest }
    self.init(directory: URL(fileURLWithPath: path, isDirectory: true))
  }

  var url: URL {
    var parts = URLComponents()
    parts.scheme = "newmemo"
    parts.host = "create-folder"
    parts.queryItems = [URLQueryItem(name: "directory", value: directory.path)]
    return parts.url!
  }
}

struct CreateRequest {
  let directory: URL
  let kind: NoteKind

  init(directory: URL, kind: NoteKind) {
    self.directory = directory
    self.kind = kind
  }

  init(url: URL) throws {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "newmemo", parts.host == "create", parts.user == nil,
      parts.password == nil, parts.port == nil, parts.fragment == nil,
      parts.path.isEmpty || parts.path == "/",
      let items = parts.queryItems, items.count == 2,
      items.filter({ $0.name == "directory" }).count == 1,
      items.filter({ $0.name == "type" }).count == 1,
      let path = items.first(where: { $0.name == "directory" })?.value,
      path.hasPrefix("/"), !path.contains("\0"),
      let rawKind = items.first(where: { $0.name == "type" })?.value,
      let kind = NoteKind(rawValue: rawKind)
    else { throw NoteError.invalidRequest }
    self.init(directory: URL(fileURLWithPath: path, isDirectory: true), kind: kind)
  }

  var url: URL {
    var parts = URLComponents()
    parts.scheme = "newmemo"
    parts.host = "create"
    parts.queryItems = [
      URLQueryItem(name: "directory", value: directory.path),
      URLQueryItem(name: "type", value: kind.rawValue),
    ]
    return parts.url!
  }
}

struct PresetCreateRequest {
  let directory: URL
  let presetID: String

  init(directory: URL, presetID: String) {
    self.directory = directory
    self.presetID = presetID
  }

  init(url: URL) throws {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      parts.scheme == "newmemo", parts.host == "create", parts.user == nil,
      parts.password == nil, parts.port == nil, parts.fragment == nil,
      parts.path.isEmpty || parts.path == "/",
      let items = parts.queryItems, items.count == 2,
      items.filter({ $0.name == "directory" }).count == 1,
      items.filter({ $0.name == "preset" }).count == 1,
      let path = items.first(where: { $0.name == "directory" })?.value,
      path.hasPrefix("/"), !path.contains("\0"),
      let id = items.first(where: { $0.name == "preset" })?.value,
      !id.isEmpty, id.utf8.count <= 64,
      id.unicodeScalars.allSatisfy({
        CharacterSet(
          charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        ).contains($0)
      })
    else {
      throw NoteError.invalidRequest
    }
    self.init(directory: URL(fileURLWithPath: path, isDirectory: true), presetID: id)
  }

  var url: URL {
    var parts = URLComponents()
    parts.scheme = "newmemo"
    parts.host = "create"
    parts.queryItems = [
      URLQueryItem(name: "directory", value: directory.path),
      URLQueryItem(name: "preset", value: presetID),
    ]
    return parts.url!
  }
}
