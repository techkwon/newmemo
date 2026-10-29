import Foundation

@main
enum FinderTargetTests {
  static var checks = 0
  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try condition() else {
      throw NSError(
        domain: "FinderTargetTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }

  static func main() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("NewMemoFinder-\(UUID())")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let folder = root.appendingPathComponent("일반 폴더", isDirectory: true)
    try fm.createDirectory(at: folder, withIntermediateDirectories: false)
    let file = root.appendingPathComponent("메모.md")
    try Data("# 메모".utf8).write(to: file)
    var packages: [URL] = []
    for suffix in ["app", "rtfd", "key"] {
      let package = root.appendingPathComponent("검증.\(suffix)", isDirectory: true)
      try fm.createDirectory(at: package, withIntermediateDirectories: false)
      try check(
        try package.resourceValues(forKeys: [.isPackageKey]).isPackage == true,
        "실제 macOS 패키지 속성: \(suffix)")
      packages.append(package)
    }
    for context in [FinderMenuContext.items, .sidebar] {
      let ordinary = FinderTarget(context: context, target: root, selection: [folder])
      try check(ordinary.creationDirectory?.path == folder.path, "일반 폴더 선택은 내부 생성")
      try check(ordinary.selectedPaths == [folder], "선택 폴더 경로 복사 유지")
      let note = FinderTarget(context: context, target: root, selection: [file])
      try check(note.creationDirectory?.path == root.path, "파일 선택은 부모 폴더에 생성")
      try check(note.selectedPaths == [file], "선택 파일 경로 복사 유지")
      for package in packages {
        let selected = FinderTarget(context: context, target: root, selection: [package])
        try check(
          selected.creationDirectory?.path == root.path, "패키지 선택은 부모에 생성: \(package.pathExtension)")
        try check(selected.selectedPaths == [package], "패키지 경로 자체 복사 유지")
        let fallback = FinderTarget(context: context, target: package, selection: [])
        try check(fallback.creationDirectory?.path == root.path, "선택 누락 시 패키지 대상도 부모로 처리")
        try check(fallback.selectedPaths == [package], "선택 누락 시 패키지 경로 복사 유지")
      }
      let multiple = FinderTarget(context: context, target: root, selection: [file, folder])
      try check(multiple.creationDirectory == nil, "다중 선택은 생성 위치를 추정하지 않음")
      try check(multiple.selectedPaths == [file, folder], "다중 선택 경로와 순서 보존")
      let fallback = FinderTarget(context: context, target: folder, selection: [])
      try check(fallback.creationDirectory?.path == folder.path, "선택 누락 시 대상 폴더 사용")
      try check(fallback.selectedPaths == [folder], "선택 누락 시 대상 경로 사용")
      let missing = FinderTarget(context: context, target: nil, selection: [])
      try check(missing.creationDirectory == nil && missing.selectedPaths.isEmpty, "대상 없는 메뉴")
    }
    let background = FinderTarget(context: .background, target: root, selection: [file])
    try check(background.creationDirectory?.path == root.path, "배경 메뉴는 현재 폴더에 생성")
    try check(background.selectedPaths.isEmpty, "배경 경로 복사는 잔여 선택 무시")
    let toolbar = FinderTarget(context: .toolbar, target: root, selection: packages)
    try check(toolbar.creationDirectory?.path == root.path, "도구 막대 생성은 현재 폴더")
    try check(toolbar.selectedPaths == packages, "도구 막대 경로 복사는 선택 유지")
    let emptyToolbar = FinderTarget(context: .toolbar, target: root, selection: [])
    try check(
      emptyToolbar.creationDirectory?.path == root.path && emptyToolbar.selectedPaths.isEmpty,
      "선택 없는 도구 막대는 현재 폴더 경로")
    print("PASS: \(checks) Finder target checks")
  }
}
