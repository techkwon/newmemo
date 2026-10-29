import AppKit
import Foundation
import ImageIO

@main
enum UtilityTests {
  static var checks = 0
  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try condition() else {
      throw NSError(
        domain: "UtilityTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  static func rejects(_ block: () throws -> Void, _ message: String) throws {
    do { try block() } catch {
      checks += 1
      return
    }
    throw NSError(domain: "UtilityTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  static func main() throws {
    let paths = [URL(fileURLWithPath: "/tmp/한글 & # ? % 📁/메모.md")]
    for action in UtilityAction.allCases {
      let request = UtilityRequest(action: action, paths: paths)
      let decoded = try UtilityRequest(url: request.url!)
      try check(
        decoded.action == action && decoded.paths == paths,
        "유틸리티 URL 왕복: \(action)")
    }
    let multi = [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
    try check(
      try UtilityRequest(url: UtilityRequest(action: .copyPaths, paths: multi).url!).paths == multi,
      "여러 선택 순서 보존")
    try check(UtilityRequest(action: .copyPaths, paths: []).url == nil, "빈 선택 거부")
    try check(UtilityRequest(action: .terminal, paths: multi).url == nil, "디렉터리 작업은 하나만 허용")
    try check(
      UtilityRequest(action: .copyPaths, paths: Array(repeating: paths[0], count: 129)).url == nil,
      "선택 128개 제한")
    try check(
      UtilityRequest(
        action: .copyPaths,
        paths: [URL(fileURLWithPath: "/" + String(repeating: "x", count: 70_000))]
      ).url == nil,
      "요청 크기 제한")
    for raw in [
      "https://utility?action=terminal&path=/tmp", "newmemo://utility?action=evil&path=/tmp",
      "newmemo://utility?action=terminal&path=relative",
      "newmemo://utility?action=terminal&path=%00",
      "newmemo://utility?action=terminal&path=/tmp&command=ls",
      "newmemo://utility?action=terminal&action=copyPaths&path=/tmp",
      "newmemo://utility?action=terminal&path=/tmp&path=/tmp",
      "newmemo://utility?action=terminal&path=/tmp&preset=md",
      "newmemo://utility?action=namedFile&path=/tmp",
      "newmemo://utility?action=namedFolder&path=/tmp",
      "newmemo://utility?action=namedFile&path=/tmp&preset=../md",
      "newmemo://utility?action=namedFile&path=/tmp&preset=md&preset=txt",
      "newmemo://utility?action=namedFile&path=/tmp&preset",
      "newmemo://utility/path?action=terminal&path=/tmp",
      "newmemo://user@utility?action=terminal&path=/tmp",
      "newmemo://utility:123?action=terminal&path=/tmp",
      "newmemo://utility?action=terminal&path=/tmp#extra", "newmemo://utility?action=terminal",
    ] {
      try rejects({ _ = try UtilityRequest(url: URL(string: raw)!) }, "잘못된 유틸리티 요청 거부")
    }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    try UtilityActions.copy(multi, namesOnly: false, pasteboard: board)
    try check(board.string(forType: .string) == "/tmp/a\n/tmp/b", "전체 경로 목록 복사")
    try UtilityActions.copy(multi, namesOnly: true, pasteboard: board)
    try check(board.string(forType: .string) == "a\nb", "이름 목록 복사")
    board.clearContents()
    try rejects({ _ = try UtilityActions.clipboardText(pasteboard: board) }, "빈 클립보드 거부")
    board.setString("# 한글 📄\n본문", forType: .string)
    try check(try UtilityActions.clipboardText(pasteboard: board) == "# 한글 📄\n본문", "원문 보존")
    board.clearContents()
    board.setString(String(repeating: "x", count: 262_145), forType: .string)
    try rejects({ _ = try UtilityActions.clipboardText(pasteboard: board) }, "큰 클립보드 글 거부")
    try rejects({ _ = try UtilityActions.clipboardPNG(pasteboard: board) }, "글을 이미지로 처리하지 않음")
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    let png = bitmap.representation(using: .png, properties: [:])!
    board.clearContents()
    board.setData(png, forType: .png)
    try check(try UtilityActions.clipboardPNG(pasteboard: board) == png, "PNG는 재디코딩 없이 보존")
    board.clearContents()
    board.setData(bitmap.tiffRepresentation!, forType: .tiff)
    let converted = try UtilityActions.clipboardPNG(pasteboard: board)
    let source = CGImageSourceCreateWithData(converted as CFData, nil)!
    try check(CGImageSourceGetType(source) as String? == "public.png", "TIFF는 PNG로 변환")
    let wide = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 4097, pixelsHigh: 1, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)!
    board.clearContents()
    board.setData(wide.representation(using: .png, properties: [:])!, forType: .png)
    try rejects({ _ = try UtilityActions.clipboardPNG(pasteboard: board) }, "이미지 차원 제한")
    board.clearContents()
    board.setData(Data(repeating: 0, count: 16 * 1024 * 1024 + 1), forType: .png)
    try rejects({ _ = try UtilityActions.clipboardPNG(pasteboard: board) }, "이미지 바이트 제한")
    let domain = "kr.techkwon.NewMemo.UtilityTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    try check(DestinationFavorites.load(defaults: defaults).isEmpty, "즐겨찾기 기본 빈 목록")
    for index in 0..<10 {
      DestinationFavorites.add(URL(fileURLWithPath: "/tmp/\(index)"), defaults: defaults)
    }
    try check(DestinationFavorites.load(defaults: defaults).count == 8, "즐겨찾기 8개 제한")
    DestinationFavorites.add(URL(fileURLWithPath: "/tmp/8"), defaults: defaults)
    try check(
      DestinationFavorites.load(defaults: defaults).first?.path == "/tmp/8", "즐겨찾기 재선택 중복 제거")
    defaults.set(["relative", "/tmp/good", "/tmp/\0bad"], forKey: DestinationFavorites.key)
    try check(
      DestinationFavorites.load(defaults: defaults).map(\.path) == ["/tmp/good"], "손상된 즐겨찾기 거부")
    print("PASS: \(checks) utility checks")
  }
}
