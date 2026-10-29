import AppKit

@main
enum DocumentTests {
  static var checks = 0
  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try condition() else {
      throw NSError(
        domain: "DocumentTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  // NSDocument applies undo-manager change notifications on the main run loop.
  static func settle(until condition: () -> Bool) {
    let deadline = Date(timeIntervalSinceNow: 1)
    repeat {
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
    } while !condition() && Date() < deadline
  }
  static func main() throws {
    _ = NSApplication.shared
    let sample = "# 한글 메모\n공백 & 이모지 📝\r\n"
    let doc = PlainTextDocument()
    try doc.read(from: Data(sample.utf8), ofType: "public.plain-text")
    try check(try doc.data(ofType: "public.plain-text") == Data(sample.utf8), "UTF-8와 줄바꿈 보존")
    let utf16 = sample.data(using: .utf16)!
    try doc.read(from: utf16, ofType: "public.plain-text")
    try check(
      try String(data: doc.data(ofType: "public.plain-text"), encoding: .utf16) == sample,
      "UTF-16 한글 왕복")
    for data in [
      Data([0xFE, 0xFF]) + sample.data(using: .utf16BigEndian)!,
      Data([0xFF, 0xFE]) + sample.data(using: .utf16LittleEndian)!,
    ] {
      try doc.read(from: data, ofType: "public.plain-text")
      try check(
        try String(data: doc.data(ofType: "public.plain-text"), encoding: .utf16) == sample,
        "UTF-16 양쪽 바이트 순서와 BOM 읽기 및 원문 저장")
    }
    for invalid in [Data([0, 1, 2]), Data([0xFF, 0xFD, 0xFF])] {
      var rejected = false
      do { try doc.read(from: invalid, ofType: "public.plain-text") } catch { rejected = true }
      try check(rejected, "바이너리와 손상 인코딩 거부")
    }
    let editable = PlainTextDocument()
    try editable.read(from: Data(), ofType: "public.plain-text")
    editable.makeWindowControllers()
    let window = editable.windowControllers[0].window!
    let scroll = window.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!
    let editor = scroll.documentView as! NSTextView
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(editor)
    try check(editor.undoManager === editable.undoManager, "문서와 편집기의 실행 취소 공유")
    // One explicit group replaces AppKit's grouping by user event in this harness.
    editor.undoManager?.groupsByEvent = false
    editor.undoManager?.beginUndoGrouping()
    editor.insertText("검증", replacementRange: NSRange(location: 0, length: 0))
    editor.undoManager?.endUndoGrouping()
    settle { editable.isDocumentEdited }
    try check(editable.isDocumentEdited, "편집 후 변경 표시")
    try check(
      try String(data: editable.data(ofType: "public.plain-text"), encoding: .utf8) == "검증",
      "편집 내용 저장 대상")
    editor.undoManager?.undo()
    try check(try editable.data(ofType: "public.plain-text").isEmpty, "실행 취소 내용 복귀")
    settle { !editable.isDocumentEdited }
    try check(!editable.isDocumentEdited, "실행 취소 후 변경 표시 해제")
    editor.undoManager?.redo()
    settle { editable.isDocumentEdited }
    try check(
      try String(data: editable.data(ofType: "public.plain-text"), encoding: .utf8) == "검증",
      "다시 실행 내용 복귀")
    try check(editable.isDocumentEdited, "다시 실행 후 변경 표시")
    let savedURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NewMemo-Document-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: savedURL) }
    var finished = false
    var saveError: Error?
    editable.save(to: savedURL, ofType: "public.plain-text", for: .saveOperation) { error in
      saveError = error
      finished = true
    }
    settle { finished }
    try check(finished && saveError == nil, "NSDocument 저장 완료")
    try check(try String(contentsOf: savedURL, encoding: .utf8) == "검증", "디스크에 실제 편집 내용 저장")
    try check(!editable.isDocumentEdited, "저장 후 변경 표시 해제")
    let reopened = PlainTextDocument()
    try reopened.read(from: savedURL, ofType: "public.plain-text")
    try check(try reopened.data(ofType: "public.plain-text") == Data("검증".utf8), "저장 파일 재열기")
    editor.undoManager?.undo()
    settle { editable.isDocumentEdited }
    try check(
      try editable.data(ofType: "public.plain-text").isEmpty && editable.isDocumentEdited,
      "저장 이후 실행 취소 시 저장할 변경 유지")
    editable.updateChangeCount(.changeCleared)
    editable.close()
    try continuousTypingAcrossSaveChecks()
    try filenamePreservationChecks()
    try markdownPreviewChecks()
    try alwaysOnTopChecks()
    print("PASS: \(checks) document checks")
  }

  static func continuousTypingAcrossSaveChecks() throws {
    for operation: NSDocument.SaveOperationType in [.saveOperation, .autosaveInPlaceOperation] {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "NewMemo-Typing-\(UUID().uuidString).txt")
      try Data().write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }
      let document = try PlainTextDocument(contentsOf: url, ofType: "public.plain-text")
      document.makeWindowControllers()
      let window = document.windowControllers[0].window!
      let editor =
        (window.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!.documentView
          as! NSTextView)
      window.makeKeyAndOrderFront(nil)
      window.makeFirstResponder(editor)
      editor.insertText("abc", replacementRange: NSRange(location: 0, length: 0))
      settle { document.isDocumentEdited }
      try check(document.isDocumentEdited, "일반 입력 변경 표시")
      var finished = false
      var error: Error?
      document.save(to: url, ofType: "public.plain-text", for: operation) {
        error = $0
        finished = true
      }
      settle { finished }
      try check(finished && error == nil && !document.isDocumentEdited, "연속 입력 중 저장 완료")
      editor.insertText("def", replacementRange: NSRange(location: 3, length: 0))
      settle { document.isDocumentEdited }
      try check(document.isDocumentEdited, "저장 직후 계속 입력한 글의 변경 상태 유지")
      try check(try String(contentsOf: url, encoding: .utf8) == "abc", "아직 저장하지 않은 글 구분")
      try check(
        try document.data(ofType: "public.plain-text") == Data("abcdef".utf8), "저장 직후 입력 내용 유지")
      document.updateChangeCount(.changeCleared)
      document.close()
    }
  }

  static func alwaysOnTopChecks() throws {
    let first = PlainTextDocument()
    first.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NewMemo-Pin-\(UUID().uuidString).md")
    try first.read(from: Data("# 고정 메모\n원문".utf8), ofType: "public.plain-text")
    first.makeWindowControllers()
    let second = PlainTextDocument()
    second.makeWindowControllers()
    defer {
      first.updateChangeCount(.changeCleared)
      second.updateChangeCount(.changeCleared)
      first.close()
      second.close()
    }
    let window = first.windowControllers[0].window!
    let otherWindow = second.windowControllers[0].window!
    let pin = window.titlebarAccessoryViewControllers.compactMap { $0.view as? NSButton }.first!
    let menu = NSMenuItem(
      title: "메모 창 맨 위 고정", action: #selector(PlainTextDocument.toggleAlwaysOnTop(_:)),
      keyEquivalent: "")
    try check(
      window.level == .normal && otherWindow.level == .normal && pin.state == .off,
      "메모 창은 기본적으로 고정하지 않음")
    try check(first.validateUserInterfaceItem(menu) && menu.state == .off, "고정 메뉴의 초기 체크 해제")
    // Exercise the actual titlebar button action and document-targeted menu selector.
    pin.performClick(nil)
    try check(window.level == .floating && pin.state == .on, "제목 표시줄 버튼으로 창 고정")
    try check(first.validateUserInterfaceItem(menu) && menu.state == .on, "고정 메뉴 체크 상태 동기화")
    try check(otherWindow.level == .normal, "다른 메모 창은 독립적으로 고정 상태 유지")
    first.togglePreview(nil)
    try check(window.level == .floating && pin.state == .on, "Markdown 미리보기 전환 중에도 고정 유지")
    first.togglePreview(nil)
    try check(
      try window.level == .floating
        && first.data(ofType: "public.plain-text") == Data("# 고정 메모\n원문".utf8)
        && !first.isDocumentEdited,
      "편집 복귀 시 고정 유지 및 원문과 변경 상태 보존")
    first.toggleAlwaysOnTop(menu)
    try check(
      window.level == .normal && pin.state == .off
        && first.validateUserInterfaceItem(menu) && menu.state == .off,
      "메뉴 액션으로 창 고정 해제하고 버튼과 메뉴 동기화")
    second.toggleAlwaysOnTop(nil)
    try check(
      otherWindow.level == .floating && window.level == .normal,
      "두 번째 창을 고정해도 첫 번째 창에는 영향 없음")
    second.toggleAlwaysOnTop(nil)
    try check(otherWindow.level == .normal, "두 번째 창 고정도 정상 해제")
  }

  static func filenamePreservationChecks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NewMemo-Filenames-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["수업.toml", "수업.md", ".env", ".gitignore", "확장자없음", "types.d.ts"] {
      let url = root.appendingPathComponent(name)
      try Data("원래 내용".utf8).write(to: url)
      let document = try PlainTextDocument(contentsOf: url, ofType: "public.plain-text")
      try document.read(from: Data("저장한 내용".utf8), ofType: "public.plain-text")
      document.updateChangeCount(.changeDone)
      document.save(nil)
      settle { !document.isDocumentEdited }
      try check(!document.isDocumentEdited, "저장 액션 완료: \(name)")
      try check(
        document.fileURL?.lastPathComponent == url.lastPathComponent,
        "저장 액션 파일명 보존: \(name), 실제 \(document.fileURL?.lastPathComponent ?? "nil")")
      try check(try String(contentsOf: url, encoding: .utf8) == "저장한 내용", "원래 경로 내용 갱신: \(name)")
      try document.read(from: Data("자동저장 내용".utf8), ofType: "public.plain-text")
      document.updateChangeCount(.changeDone)
      var autosaved = false
      var autosaveError: Error?
      document.autosave(withImplicitCancellability: false) { error in
        autosaveError = error
        autosaved = true
      }
      settle { autosaved }
      try check(
        autosaved && autosaveError == nil
          && document.fileURL?.lastPathComponent == url.lastPathComponent,
        "자동저장 파일명 보존: \(name)")
      try check(try String(contentsOf: url, encoding: .utf8) == "자동저장 내용", "자동저장 원래 경로 갱신: \(name)")
      let panel = NSSavePanel()
      try check(
        document.prepareSavePanel(panel) && panel.allowedContentTypes.isEmpty
          && panel.allowsOtherFileTypes && !panel.isExtensionHidden
          && panel.nameFieldStringValue == url.lastPathComponent,
        "다른 이름 저장 패널이 사용자 파일명과 임의 확장자 허용: \(name)")
      let copyDirectory = root.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: copyDirectory, withIntermediateDirectories: true)
      let copyURL = copyDirectory.appendingPathComponent(name == ".env" ? ".설정" : "사본.custom")
      var copied = false
      var copyError: Error?
      document.save(to: copyURL, ofType: "public.plain-text", for: .saveAsOperation) { error in
        copyError = error
        copied = true
      }
      settle { copied }
      try check(
        copied && copyError == nil && document.fileURL?.path == copyURL.path,
        "다른 이름 저장의 지정 이름 보존: \(name)")
      try check(
        try String(contentsOf: copyURL, encoding: .utf8) == "자동저장 내용",
        "다른 이름 저장 내용 보존: \(name)")
      try document.read(from: Data("사본 수정".utf8), ofType: "public.plain-text")
      document.updateChangeCount(.changeDone)
      document.save(nil)
      settle { !document.isDocumentEdited }
      try check(
        document.fileURL?.path == copyURL.path
          && String(contentsOf: copyURL, encoding: .utf8) == "사본 수정",
        "다른 이름 저장 이후 저장 액션도 지정 이름 보존: \(name)")
      try check(
        try String(contentsOf: url, encoding: .utf8) == "자동저장 내용", "다른 이름 저장 후 원본 보존: \(name)")
      document.updateChangeCount(.changeCleared)
      document.close()
    }
  }

  static func markdownPreviewChecks() throws {
    struct WeakPreview { weak var value: NSTextView? }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NewMemo-Preview-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("미리보기.md")
    let original = "# 한글 제목\n\n**강조**와 `코드`\n\n- 항목\n"
    try Data(original.utf8).write(to: file)
    let document = try PlainTextDocument(contentsOf: file, ofType: "public.plain-text")
    document.makeWindowControllers()
    let window = document.windowControllers[0].window!
    let content = window.contentView!
    let sourceScroll = content.subviews.compactMap { $0 as? NSScrollView }.first!
    let source = sourceScroll.documentView as! NSTextView
    let picker = window.titlebarAccessoryViewControllers.compactMap {
      $0.view as? NSSegmentedControl
    }.first!
    func scrolls() -> [NSScrollView] { content.subviews.compactMap { $0 as? NSScrollView } }
    func preview() -> NSTextView? {
      scrolls().first { $0 !== sourceScroll }?.documentView as? NSTextView
    }
    window.makeKeyAndOrderFront(nil)
    try check(scrolls().count == 1 && !sourceScroll.isHidden, "미리보기는 요청 전 생성하지 않음")
    try check(picker.isEnabled && picker.selectedSegment == 0, "Markdown 문서 보기 선택 활성화")
    let releasedPreview = try autoreleasepool { () throws -> WeakPreview in
      document.togglePreview(nil)
      try check(
        scrolls().count == 2 && sourceScroll.isHidden && picker.selectedSegment == 1,
        "미리보기 전환 시 원문을 숨기고 렌더링 뷰 하나만 추가")
      try check(
        preview()?.isEditable == false && preview()?.isSelectable == true
          && preview()?.string.contains("한글 제목") == true
          && preview()?.string.contains("# 한글 제목") == false,
        "미리보기는 선택 가능한 읽기 전용 렌더링")
      try check(
        try source.string == original
          && document.data(ofType: "public.plain-text") == Data(original.utf8)
          && !document.isDocumentEdited,
        "미리보기는 원문과 저장 바이트 및 변경 상태를 보존")
      let reference = WeakPreview(value: preview())
      document.togglePreview(nil)
      return reference
    }
    try check(
      scrolls().count == 1 && !sourceScroll.isHidden && picker.selectedSegment == 0,
      "편집으로 돌아오면 미리보기 뷰 제거")
    settle { releasedPreview.value == nil }
    try check(releasedPreview.value == nil, "편집 전환 후 미리보기 텍스트 뷰 메모리 해제")
    var bounded = true
    var released = true
    for _ in 0..<20 {
      let transientPreview = autoreleasepool { () -> WeakPreview in
        document.togglePreview(nil)
        bounded = bounded && scrolls().count == 2
        let reference = WeakPreview(value: preview())
        document.togglePreview(nil)
        bounded = bounded && scrolls().count == 1 && !sourceScroll.isHidden
        return reference
      }
      settle { transientPreview.value == nil }
      released = released && transientPreview.value == nil
    }
    try check(bounded && released, "20회 전환해도 뷰가 쌓이지 않고 매번 미리보기 해제")
    let replacement = "## 바뀐 원문\n\n새로운 내용\n"
    let replacedPreview = try autoreleasepool { () throws -> WeakPreview in
      document.togglePreview(nil)
      let reference = WeakPreview(value: preview())
      try document.read(from: Data(replacement.utf8), ofType: "public.plain-text")
      return reference
    }
    settle { replacedPreview.value == nil }
    try check(
      scrolls().count == 2 && preview()?.string.contains("바뀐 원문") == true
        && preview()?.string.contains("한글 제목") == false && replacedPreview.value == nil,
      "문서 다시 읽기 시 미리보기를 최신 내용으로 교체하고 이전 뷰 해제")
    try check(
      try source.string == replacement
        && document.data(ofType: "public.plain-text") == Data(replacement.utf8),
      "미리보기 중 다시 읽은 원문과 저장 내용 일치")
    document.fileURL = root.appendingPathComponent("변경.txt")
    try check(
      !picker.isEnabled && picker.selectedSegment == 0 && scrolls().count == 1
        && !sourceScroll.isHidden,
      "Markdown에서 txt로 파일명 변경 시 미리보기 해제 및 전환 비활성화")
    document.togglePreview(nil)
    try check(scrolls().count == 1 && !sourceScroll.isHidden, "일반 텍스트는 미리보기 요청 무시")
    document.fileURL = file
    try check(picker.isEnabled, "txt에서 Markdown으로 파일명 변경 시 미리보기 활성화")
    document.togglePreview(nil)
    try check(scrolls().count == 2, "Markdown 복귀 후 미리보기 다시 생성")
    let oversized = String(repeating: "a", count: PlainTextDocument.previewByteLimit + 1)
    try document.read(from: Data(oversized.utf8), ofType: "public.plain-text")
    try check(
      scrolls().count == 1 && !sourceScroll.isHidden && picker.selectedSegment == 0,
      "미리보기 중 용량 제한 초과 내용 읽으면 편집으로 복귀하고 미리보기 해제")
    if let sheet = window.attachedSheet {
      window.endSheet(sheet)
      sheet.orderOut(nil)
    }
    document.togglePreview(nil)
    try check(
      try scrolls().count == 1 && !sourceScroll.isHidden
        && document.data(ofType: "public.plain-text") == Data(oversized.utf8),
      "256KB 초과 미리보기는 원문을 보존하고 렌더링 뷰를 생성하지 않음")
    if let sheet = window.attachedSheet {
      window.endSheet(sheet)
      sheet.orderOut(nil)
    }
    let tooManyLines = String(repeating: "\n", count: PlainTextDocument.previewLineLimit)
    try document.read(from: Data(tooManyLines.utf8), ofType: "public.plain-text")
    document.togglePreview(nil)
    try check(
      try tooManyLines.utf8.count < PlainTextDocument.previewByteLimit
        && scrolls().count == 1 && !sourceScroll.isHidden
        && document.data(ofType: "public.plain-text") == Data(tooManyLines.utf8),
      "문서가 256KB 이하여도 10,000줄 초과 시 미리보기 생성하지 않음")
    if let sheet = window.attachedSheet {
      window.endSheet(sheet)
      sheet.orderOut(nil)
    }
    document.fileURL = root.appendingPathComponent("대문자.MARKDOWN")
    try check(picker.isEnabled, "대문자 Markdown 확장자도 보기 선택 지원")
    document.updateChangeCount(.changeCleared)
    document.close()
  }

}
