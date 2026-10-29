import Darwin
import Foundation

enum FileActionError: LocalizedError {
  case invalidSelection
  case unsafeDestination
  case tooLarge
  case differentVolume
  case transferFailed(source: URL, destination: URL, completed: [URL], underlying: Error)

  var errorDescription: String? {
    switch self {
    case .invalidSelection:
      return "존재하는 파일이나 폴더를 선택해 주세요. 중복되거나 서로 포함된 항목은 이동할 수 없습니다."
    case .unsafeDestination:
      return "같은 위치로 이동하거나 폴더를 자기 자신 안으로 보낼 수 없습니다. 다른 폴더를 선택해 주세요."
    case .tooLarge:
      return "클립보드 파일은 16MB 이내로 저장할 수 있습니다."
    case .differentVolume:
      return "다른 디스크로의 이동은 지원하지 않습니다. 원본 보호를 위해 ‘복사’로 보낸 뒤 내용을 확인해 주세요."
    case .transferFailed(let source, let destination, let completed, let underlying):
      let progress =
        completed.isEmpty
        ? "완료된 항목은 없습니다."
        : "이미 완료한 위치:\n" + completed.map(\.path).joined(separator: "\n")
      return
        "‘\(source.lastPathComponent)’ 처리에 실패했습니다.\n대상: \(destination.path)\n\(underlying.localizedDescription)\n\n\(progress)"
    }
  }
}

enum FileActions {
  static let clipboardByteLimit = 16 * 1_024 * 1_024

  static func copyItems(_ sources: [URL], to directory: URL) throws -> [URL] {
    try transfer(sources, to: directory, moving: false)
  }

  static func moveItems(_ sources: [URL], to directory: URL) throws -> [URL] {
    try transfer(sources, to: directory, moving: true)
  }

  static func saveClipboardData(
    _ data: Data, in directory: URL, basename: String, fileExtension: String
  ) throws -> URL {
    guard data.count <= clipboardByteLimit else { throw FileActionError.tooLarge }
    return try NoteFiles.createData(
      data, in: directory, basename: basename, fileExtension: fileExtension)
  }

  private static func transfer(_ sources: [URL], to directory: URL, moving: Bool) throws -> [URL] {
    try validateDirectory(directory)
    guard !sources.isEmpty, sources.count <= 128 else { throw FileActionError.invalidSelection }
    var seen = Set<String>()
    var directories = [URL]()
    for source in sources {
      var info = stat()
      guard source.isFileURL, source.path != "/", lstat(source.path, &info) == 0,
        seen.insert(source.standardizedFileURL.path.precomposedStringWithCanonicalMapping).inserted
      else { throw FileActionError.invalidSelection }
      if moving && sameDirectory(source.deletingLastPathComponent(), directory) {
        throw FileActionError.unsafeDestination
      }
      if info.st_mode & S_IFMT == S_IFDIR {
        guard !isWithin(directory, directory: source) else {
          throw FileActionError.unsafeDestination
        }
        directories.append(source)
      }
    }
    if moving {
      for source in sources {
        let parent = source.deletingLastPathComponent()
        if directories.contains(where: { isWithin(parent, directory: $0) }) {
          throw FileActionError.invalidSelection
        }
      }
    }
    var completed = [URL]()
    for source in sources {
      let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      let name = source.lastPathComponent
      let ext = isDirectory || name.hasPrefix(".") ? "" : source.pathExtension
      let basename = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
      var destination = directory.appendingPathComponent(name)
      do {
        var succeeded = false
        for index in 1...10_000 {
          destination = directory.appendingPathComponent(
            candidateName(basename: basename, fileExtension: ext, index: index))
          do {
            if moving {
              try moveExclusively(source, to: destination)
            } else {
              try FileManager.default.copyItem(at: source, to: destination)
            }
            completed.append(destination)
            succeeded = true
            break
          } catch {
            if isCollision(error) { continue }
            throw error
          }
        }
        if !succeeded { throw NoteError.tooManyFiles }
      } catch {
        throw FileActionError.transferFailed(
          source: source, destination: destination, completed: completed, underlying: error)
      }
    }
    return completed
  }

  private static func validateDirectory(_ directory: URL) throws {
    var isDirectory: ObjCBool = false
    guard directory.isFileURL,
      FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw NoteError.invalidDirectory }
  }

  private static func moveExclusively(_ source: URL, to destination: URL) throws {
    // FileManager.moveItem can overwrite a racing destination between its existence
    // check and rename. The kernel must enforce exclusive destination allocation.
    let result = source.withUnsafeFileSystemRepresentation { sourcePath in
      destination.withUnsafeFileSystemRepresentation { destinationPath in
        guard let sourcePath, let destinationPath else { return Int32(-1) }
        return renamex_np(sourcePath, destinationPath, UInt32(RENAME_EXCL))
      }
    }
    if result == 0 { return }
    let code = errno
    if code == EXDEV { throw FileActionError.differentVolume }
    throw NSError(
      domain: NSPOSIXErrorDomain, code: Int(code),
      userInfo: [NSFilePathErrorKey: destination.path])
  }

  private static func candidateName(basename: String, fileExtension: String, index: Int) -> String {
    let suffix = index == 1 ? "" : " \(index)"
    let ext = fileExtension.isEmpty ? "" : ".\(fileExtension)"
    return "\(basename)\(suffix)\(ext)"
  }

  private static func sameDirectory(_ first: URL, _ second: URL) -> Bool {
    var lhs = stat()
    var rhs = stat()
    return stat(first.path, &lhs) == 0 && stat(second.path, &rhs) == 0
      && lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
  }

  private static func isWithin(_ url: URL, directory: URL) -> Bool {
    // Compare filesystem identities, including case-insensitive and Unicode-equivalent paths.
    var ancestor = stat()
    guard stat(directory.path, &ancestor) == 0 else { return false }
    var current = url.resolvingSymlinksInPath().standardizedFileURL.path
    while true {
      var info = stat()
      if stat(current, &info) == 0,
        info.st_dev == ancestor.st_dev && info.st_ino == ancestor.st_ino
      {
        return true
      }
      if current == "/" { return false }
      let parent = (current as NSString).deletingLastPathComponent
      if parent.isEmpty || parent == current { return false }
      current = parent
    }
  }

  private static func isCollision(_ error: Error) -> Bool {
    let error = error as NSError
    return
      (error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteFileExists.rawValue)
      || (error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST))
  }
}
