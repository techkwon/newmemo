import Darwin
import Foundation

@main
enum ActionTests {
  static var checks = 0
  static let fm = FileManager.default

  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try condition() else {
      throw NSError(
        domain: "ActionTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }

  static func rejects(_ message: String, _ action: () throws -> Void) throws {
    do { try action() } catch {
      checks += 1
      return
    }
    throw NSError(domain: "ActionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  static func main() throws {
    let root = fm.temporaryDirectory.appendingPathComponent(
      "NewMemoActions-\(UUID())", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = try folder(root, "원본")
    let destination = try folder(root, "도착")
    let data = Data("보존할 한글 📄".utf8)
    let file = source.appendingPathComponent("수업.md")
    try data.write(to: file)
    let copied = try FileActions.copyItems([file], to: destination)[0]
    try check(copied.lastPathComponent == "수업.md", "복사 이름 유지")
    try check(
      try Data(contentsOf: copied) == data && Data(contentsOf: file) == data, "복사 내용과 원본 보존")
    let copiedAgain = try FileActions.copyItems([file], to: destination)[0]
    try check(copiedAgain.lastPathComponent == "수업 2.md", "파일 충돌 확장자 앞 번호")
    try check(try Data(contentsOf: copied) == data, "충돌 원본 보존")
    let sameFolder = try FileActions.copyItems([file], to: source)[0]
    try check(sameFolder.lastPathComponent == "수업 2.md", "같은 폴더 복사 번호")
    let moved = try FileActions.moveItems([file], to: destination)[0]
    try check(moved.lastPathComponent == "수업 3.md", "이동 충돌 번호")
    try check(!fm.fileExists(atPath: file.path), "이동 뒤 원본 없음")
    try check(try Data(contentsOf: moved) == data, "이동 내용 유지")
    let dotfile = source.appendingPathComponent(".env")
    try data.write(to: dotfile)
    _ = try FileActions.copyItems([dotfile], to: destination)
    let dotCopy = try FileActions.copyItems([dotfile], to: destination)[0]
    try check(dotCopy.lastPathComponent == ".env 2", "점 파일 번호")
    let dotDirectory = try folder(source, "폴더.v1")
    try data.write(to: dotDirectory.appendingPathComponent("내용.txt"))
    _ = try FileActions.copyItems([dotDirectory], to: destination)
    let folderCopy = try FileActions.copyItems([dotDirectory], to: destination)[0]
    try check(folderCopy.lastPathComponent == "폴더.v1 2", "점 포함 폴더 이름 뒤 번호")
    try check(try Data(contentsOf: folderCopy.appendingPathComponent("내용.txt")) == data, "하위 내용 복사")
    let link = source.appendingPathComponent("링크.txt")
    try fm.createSymbolicLink(at: link, withDestinationURL: moved)
    let copiedLink = try FileActions.copyItems([link], to: destination)[0]
    try check(try fm.destinationOfSymbolicLink(atPath: copiedLink.path) == moved.path, "링크 자체 복사")
    try check(try Data(contentsOf: moved) == data, "링크 대상 보존")
    let broken = destination.appendingPathComponent("수업 4.md")
    try fm.createSymbolicLink(atPath: broken.path, withDestinationPath: "/missing-\(UUID())")
    let afterBrokenLink = try FileActions.copyItems([sameFolder], to: destination)[0]
    try check(afterBrokenLink.lastPathComponent == "수업 2 2.md", "원본 기본 이름 유지")
    let brokenSource = source.appendingPathComponent("끊긴 링크")
    try fm.createSymbolicLink(atPath: brokenSource.path, withDestinationPath: "/missing-\(UUID())")
    let brokenCopied = try FileActions.copyItems([brokenSource], to: destination)[0]
    try check(
      try fm.destinationOfSymbolicLink(atPath: brokenCopied.path).hasPrefix("/missing-"),
      "끊긴 링크 자체 복사")
    try rejects("파일 부모 거부") { _ = try FileActions.copyItems([dotfile], to: moved) }
    try rejects("없는 부모 거부") {
      _ = try FileActions.copyItems([dotfile], to: root.appendingPathComponent("없음"))
    }
    try rejects("원격 부모 거부") {
      _ = try FileActions.copyItems([dotfile], to: URL(string: "https://example.com")!)
    }
    try rejects("빈 선택 거부") { _ = try FileActions.copyItems([], to: destination) }
    try rejects("중복 선택 거부") { _ = try FileActions.moveItems([dotfile, dotfile], to: destination) }
    try check(fm.fileExists(atPath: dotfile.path), "잘못된 선택 사전 거부로 원본 보존")
    try rejects("같은 부모 이동 거부") { _ = try FileActions.moveItems([dotfile], to: source) }
    try rejects("자기 내부 복사 거부") { _ = try FileActions.copyItems([source], to: dotDirectory) }
    try rejects("자기 내부 이동 거부") { _ = try FileActions.moveItems([source], to: dotDirectory) }
    try rejects("자기 자신 복사 거부") { _ = try FileActions.copyItems([source], to: source) }
    let alias = root.appendingPathComponent("목적지 링크")
    try fm.createSymbolicLink(at: alias, withDestinationURL: dotDirectory)
    try rejects("링크를 통한 자기 내부 거부") { _ = try FileActions.copyItems([source], to: alias) }
    try rejects("부모와 자식 중첩 이동 거부") {
      _ = try FileActions.moveItems([source, dotfile], to: destination)
    }
    try rejects("없는 원본 포함 요청 사전 거부") {
      _ = try FileActions.moveItems([dotfile, root.appendingPathComponent("없음")], to: destination)
    }
    try check(fm.fileExists(atPath: dotfile.path), "사전 검사 실패 전 이동하지 않음")
    let directoryMoved = try FileActions.moveItems([dotDirectory], to: destination)[0]
    try check(directoryMoved.lastPathComponent == "폴더.v1 3", "폴더 이동 번호")
    try check(!fm.fileExists(atPath: dotDirectory.path), "폴더 이동 뒤 원본 없음")
    try check(
      try Data(contentsOf: directoryMoved.appendingPathComponent("내용.txt")) == data, "폴더 이동 내용 유지")
    try transferEdgeChecks(root: root, data: data)
    try clipboardChecks(root: root, data: data)
    try folderNameChecks(root: root)
    print("PASS: \(checks) file action checks")
  }

  static func transferEdgeChecks(root: URL, data: Data) throws {
    let source = try folder(root, "TransferSource")
    let destination = try folder(root, "TransferDestination")
    let file = source.appendingPathComponent("same.txt")
    try data.write(to: file)
    let blocked = destination.appendingPathComponent("same.txt")
    try fm.createSymbolicLink(atPath: blocked.path, withDestinationPath: "/missing-\(UUID())")
    let copied = try FileActions.copyItems([file], to: destination)[0]
    try check(copied.lastPathComponent == "same 2.txt", "파일 복사가 끊긴 목적지 링크 보존")
    try check(
      try fm.destinationOfSymbolicLink(atPath: blocked.path).hasPrefix("/missing-"), "목적지 링크 변경 없음")
    let lock = NSLock()
    var paths = Set<URL>()
    var failures = [String]()
    DispatchQueue.concurrentPerform(iterations: 20) { _ in
      do {
        let copied = try FileActions.copyItems([file], to: destination)[0]
        lock.lock()
        paths.insert(copied)
        lock.unlock()
      } catch {
        lock.lock()
        failures.append(error.localizedDescription)
        lock.unlock()
      }
    }
    try check(failures.isEmpty && paths.count == 20, "동시 복사 20개 고유 경로")
    try check(try paths.allSatisfy { try Data(contentsOf: $0) == data }, "동시 복사 데이터 보존")
    var moveSources = [URL]()
    for index in 0..<20 {
      let parent = try folder(root, "이동 원본 \(index)")
      let item = parent.appendingPathComponent("경합.txt")
      try Data("원본 \(index)".utf8).write(to: item)
      moveSources.append(item)
    }
    let existing = destination.appendingPathComponent("경합.txt")
    try data.write(to: existing)
    paths.removeAll()
    failures.removeAll()
    DispatchQueue.concurrentPerform(iterations: 20) { index in
      do {
        let moved = try FileActions.moveItems([moveSources[index]], to: destination)[0]
        lock.lock()
        paths.insert(moved)
        lock.unlock()
      } catch {
        lock.lock()
        failures.append(error.localizedDescription)
        lock.unlock()
      }
    }
    try check(
      failures.isEmpty && paths.count == 20,
      "동시 이동 20개 고유 목적지: paths=\(paths.count), failures=\(failures)")
    try check(try Data(contentsOf: existing) == data, "동시 이동이 기존 목적지를 덮어쓰지 않음")
    let movedContents = try Set(paths.map { try String(contentsOf: $0, encoding: .utf8) })
    try check(movedContents == Set((0..<20).map { "원본 \($0)" }), "동시 이동 모든 원본 내용 보존")
    try check(moveSources.allSatisfy { !fm.fileExists(atPath: $0.path) }, "동시 이동 원본 경로 정리")
    let child = try folder(source, "Child")
    let alternateCase = source.deletingLastPathComponent().appendingPathComponent("transfersource")
    if fm.fileExists(atPath: alternateCase.path) {
      try rejects("대소문자 다른 같은 부모 이동 거부") {
        _ = try FileActions.moveItems([file], to: alternateCase)
      }
      try rejects("대소문자 다른 자기 내부 복사 거부") {
        _ = try FileActions.copyItems([alternateCase], to: child)
      }
    }
    let longName = String(repeating: "x", count: 255)
    let longFile = source.appendingPathComponent(longName)
    try data.write(to: longFile)
    try data.write(to: destination.appendingPathComponent(longName))
    do {
      _ = try FileActions.copyItems([file, longFile], to: destination)
      throw NSError(
        domain: "ActionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "부분 실패 누락"])
    } catch FileActionError.transferFailed(let failed, _, let completed, let underlying) {
      try check(failed == longFile && completed.count == 1, "부분 실패 완료 경로 제공")
      try check(try Data(contentsOf: completed[0]) == data, "부분 실패 이전 완료 항목 보존")
      let error = FileActionError.transferFailed(
        source: failed, destination: destination, completed: completed, underlying: underlying)
      try check(error.localizedDescription.contains(completed[0].path), "오류에 완료한 위치 표시")
    }
    try check(try Data(contentsOf: longFile) == data, "실패한 원본 보존")
  }

  static func clipboardChecks(root: URL, data: Data) throws {
    let directory = try folder(root, "클립보드")
    let saved = try FileActions.saveClipboardData(
      data, in: directory, basename: "이미지", fileExtension: "png")
    try check(saved.lastPathComponent == "이미지.png", "클립보드 파일 이름")
    try check(try Data(contentsOf: saved) == data, "클립보드 바이트 보존")
    let link = directory.appendingPathComponent("이미지 2.png")
    try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "/missing-\(UUID())")
    let next = try FileActions.saveClipboardData(
      data, in: directory, basename: "이미지", fileExtension: "png")
    try check(next.lastPathComponent == "이미지 3.png", "클립보드 끊긴 링크 건너뜀")
    try check(try Data(contentsOf: saved) == data, "클립보드 충돌 원본 보존")
    for name in ["../escape", "", "..", "이름/경로", "a:b"] {
      try rejects("잘못된 클립보드 파일 이름") {
        _ = try FileActions.saveClipboardData(
          data, in: directory, basename: name, fileExtension: "png")
      }
    }
    try rejects("잘못된 클립보드 확장자") {
      _ = try FileActions.saveClipboardData(
        data, in: directory, basename: "이미지", fileExtension: "../png")
    }
    try rejects("클립보드 크기 제한") {
      _ = try FileActions.saveClipboardData(
        Data(count: FileActions.clipboardByteLimit + 1), in: directory, basename: "큰 이미지",
        fileExtension: "png")
    }
    try rejects("클립보드 부모 파일 거부") {
      _ = try FileActions.saveClipboardData(data, in: saved, basename: "이미지", fileExtension: "png")
    }
    let lock = NSLock()
    var paths = Set<URL>()
    var failures = [String]()
    DispatchQueue.concurrentPerform(iterations: 20) { _ in
      do {
        let saved = try FileActions.saveClipboardData(
          data, in: directory, basename: "동시 이미지", fileExtension: "png")
        lock.lock()
        paths.insert(saved)
        lock.unlock()
      } catch {
        lock.lock()
        failures.append(error.localizedDescription)
        lock.unlock()
      }
    }
    try check(failures.isEmpty && paths.count == 20, "클립보드 동시 저장 고유 경로")
    try check(try paths.allSatisfy { try Data(contentsOf: $0) == data }, "클립보드 동시 저장 데이터 보존")
  }

  static func folderNameChecks(root: URL) throws {
    let parent = try folder(root, "이름 지정 폴더")
    let first = try NoteFiles.createFolder(in: parent, basename: "수업 자료")
    let second = try NoteFiles.createFolder(in: parent, basename: "수업 자료")
    try check(
      first.lastPathComponent == "수업 자료" && second.lastPathComponent == "수업 자료 2",
      "사용자 지정 폴더 이름과 번호")
    for name in ["../escape", "..", "", "줄\n바꿈"] {
      try rejects("잘못된 폴더 이름") { _ = try NoteFiles.createFolder(in: parent, basename: name) }
    }
  }

  static func folder(_ parent: URL, _ name: String) throws -> URL {
    let result = parent.appendingPathComponent(name, isDirectory: true)
    try fm.createDirectory(at: result, withIntermediateDirectories: false)
    return result
  }
}
