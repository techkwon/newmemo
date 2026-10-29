import AppKit

@objc(PlainTextDocument)
final class PlainTextDocument: NSDocument, NSTextStorageDelegate {
  private var contents = ""
  private var encoding = String.Encoding.utf8
  private var editor: NSTextView?
  private weak var countLabel: NSTextField?
  private weak var editorScroll: NSScrollView?
  private var previewScroll: NSScrollView?
  private weak var viewPicker: NSSegmentedControl?
  private weak var pinButton: NSButton?
  private var textContent: String { editor?.string ?? contents }
  private var isMarkdown: Bool {
    ["md", "markdown"].contains(fileURL?.pathExtension.lowercased() ?? "")
  }
  static let previewByteLimit = 262_144
  static let previewLineLimit = 10_000

  override var fileURL: URL? {
    didSet {
      if !isMarkdown { showPreview(false) }
      viewPicker?.isEnabled = isMarkdown
    }
  }

  override class var autosavesInPlace: Bool { true }

  override func save(
    to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
    completionHandler: @escaping (Error?) -> Void
  ) {
    // A save point must end the typing undo group or later typing can remain marked clean.
    editor?.breakUndoCoalescing()
    super.save(to: url, ofType: typeName, for: saveOperation, completionHandler: completionHandler)
  }

  override func fileNameExtension(
    forType typeName: String, saveOperation: NSDocument.SaveOperationType
  ) -> String? {
    // All supported files share one text representation. Saving must not convert
    // their chosen names to the plain-text UTI's preferred .txt extension.
    if let url = fileURL {
      return url.pathExtension.isEmpty ? nil : url.pathExtension
    }
    return super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
  }

  override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
    guard super.prepareSavePanel(savePanel) else { return false }
    // A template may use any text suffix (or none), including dotfiles.
    savePanel.allowedContentTypes = []
    savePanel.allowsOtherFileTypes = true
    savePanel.isExtensionHidden = false
    if let url = fileURL { savePanel.nameFieldStringValue = url.lastPathComponent }
    return true
  }

  override func makeWindowControllers() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false
    )
    window.minSize = NSSize(width: 420, height: 300)
    window.center()
    window.setFrameAutosaveName("NoteEditor")
    do {
      let picker = NSSegmentedControl(
        labels: ["편집", "미리보기"], trackingMode: .selectOne,
        target: self, action: #selector(changeView(_:)))
      picker.selectedSegment = 0
      picker.isEnabled = isMarkdown
      picker.setAccessibilityLabel("Markdown 보기 방식")
      picker.frame = NSRect(x: 0, y: 0, width: 164, height: 28)
      let accessory = NSTitlebarAccessoryViewController()
      accessory.view = picker
      accessory.layoutAttribute = .right
      window.addTitlebarAccessoryViewController(accessory)
      viewPicker = picker
    }
    do {
      let pin = NSButton(
        image: NSImage(systemSymbolName: "pin", accessibilityDescription: nil) ?? NSImage(),
        target: self, action: #selector(toggleAlwaysOnTop(_:)))
      pin.setButtonType(.pushOnPushOff)
      pin.bezelStyle = .texturedRounded
      pin.imagePosition = .imageOnly
      pin.alternateImage = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
      pin.setAccessibilityLabel("메모 창 맨 위 고정")
      pin.toolTip = "메모 창 맨 위 고정"
      pin.frame = NSRect(x: 0, y: 0, width: 28, height: 28)
      let accessory = NSTitlebarAccessoryViewController()
      accessory.view = pin
      accessory.layoutAttribute = .right
      window.addTitlebarAccessoryViewController(accessory)
      pinButton = pin
    }
    let root = NSView()
    window.contentView = root
    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 500))
    text.isRichText = false
    text.importsGraphics = false
    text.allowsUndo = true
    undoManager?.levelsOfUndo = 50
    text.usesFindBar = true
    text.isIncrementalSearchingEnabled = true
    text.isAutomaticQuoteSubstitutionEnabled = false
    text.isAutomaticDashSubstitutionEnabled = false
    text.isAutomaticTextReplacementEnabled = false
    text.isAutomaticSpellingCorrectionEnabled = false
    text.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
    text.textContainerInset = NSSize(width: 24, height: 24)
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.minSize = NSSize(width: 0, height: 0)
    text.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    text.textContainer?.widthTracksTextView = true
    text.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
    text.string = contents
    contents = ""
    text.textStorage?.delegate = self
    text.setAccessibilityLabel("메모 내용")
    scroll.documentView = text
    let status = NSTextField(labelWithString: "")
    status.translatesAutoresizingMaskIntoConstraints = false
    status.font = .systemFont(ofSize: 11)
    status.textColor = .secondaryLabelColor
    root.addSubview(scroll)
    root.addSubview(status)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: root.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -7),
      status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
    ])
    editor = text
    editorScroll = scroll
    countLabel = status
    updateStatus()
    let controller = NSWindowController(window: window)
    addWindowController(controller)
    window.initialFirstResponder = text
  }

  func textStorage(
    _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange, changeInLength delta: Int
  ) {
    guard editedMask.contains(.editedCharacters) else { return }
    // Storage notifications include undo/redo; NSDocument tracks dirty state via its undo manager.
    updateStatus()
  }

  private func updateStatus() {
    let label = encoding == .utf8 ? "UTF-8" : "UTF-16"
    let text = textContent
    let lines = text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
    countLabel?.stringValue = "\(label)   ·   \(text.count)자   ·   \(lines)줄"
  }

  @objc private func changeView(_ sender: NSSegmentedControl) {
    showPreview(sender.selectedSegment == 1)
  }

  @objc func togglePreview(_ sender: Any?) { showPreview(previewScroll == nil) }

  @objc func toggleAlwaysOnTop(_ sender: Any?) {
    guard let window = (sender as? NSButton)?.window ?? windowControllers.first?.window else {
      return
    }
    let pinned = window.level != .floating
    window.level = pinned ? .floating : .normal
    pinButton?.state = pinned ? .on : .off
    pinButton?.toolTip = pinned ? "메모 창 맨 위 고정 해제" : "메모 창 맨 위 고정"
  }

  override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(togglePreview(_:)) { return isMarkdown }
    if item.action == #selector(toggleAlwaysOnTop(_:)) {
      let window = windowControllers.first?.window
      (item as? NSMenuItem)?.state = window?.level == .floating ? .on : .off
      return window != nil
    }
    return super.validateUserInterfaceItem(item)
  }

  private func showPreview(_ enabled: Bool) {
    guard let sourceScroll = editorScroll, let root = sourceScroll.superview else { return }
    if !enabled {
      previewScroll?.removeFromSuperview()
      previewScroll = nil
      sourceScroll.isHidden = false
      viewPicker?.selectedSegment = 0
      windowControllers.first?.window?.makeFirstResponder(editor)
      return
    }
    guard isMarkdown else { return }
    let source = textContent
    guard source.utf8.count <= Self.previewByteLimit,
      source.utf8.reduce(1, { $1 == 10 ? $0 + 1 : $0 }) <= Self.previewLineLimit
    else {
      showPreview(false)
      let alert = NSAlert()
      alert.messageText = "미리보기 용량을 초과했습니다."
      alert.informativeText =
        "메모리 사용을 줄이기 위해 Markdown 미리보기는 256KB, 10,000줄 이하 문서에 제공합니다. 원문 편집과 저장은 계속 사용할 수 있습니다."
      if let window = windowControllers.first?.window { alert.beginSheetModal(for: window) }
      return
    }
    let scroll = NSScrollView()
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    let preview = NSTextView(frame: sourceScroll.bounds)
    preview.isEditable = false
    preview.isSelectable = true
    preview.isRichText = true
    preview.allowsUndo = false
    preview.importsGraphics = false
    preview.isAutomaticLinkDetectionEnabled = false
    preview.textContainerInset = NSSize(width: 24, height: 24)
    preview.isVerticallyResizable = true
    preview.isHorizontallyResizable = false
    preview.autoresizingMask = [.width]
    preview.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    preview.textContainer?.widthTracksTextView = true
    preview.textStorage?.setAttributedString(MarkdownRenderer.render(source))
    preview.setAccessibilityLabel("Markdown 미리보기")
    scroll.documentView = preview
    previewScroll?.removeFromSuperview()
    root.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: sourceScroll.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: sourceScroll.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: sourceScroll.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: sourceScroll.bottomAnchor),
    ])
    previewScroll = scroll
    sourceScroll.isHidden = true
    viewPicker?.selectedSegment = 1
    windowControllers.first?.window?.makeFirstResponder(preview)
  }

  override func read(from data: Data, ofType typeName: String) throws {
    let bytes = Array(data.prefix(2))
    let detected: String.Encoding
    if bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF] {
      detected = .utf16
    } else {
      detected = .utf8
    }
    guard let string = String(data: data, encoding: detected),
      !string.unicodeScalars.contains(where: {
        $0.value == 0 || ($0.value < 32 && ![9, 10, 13].contains($0.value))
      })
    else {
      throw NSError(
        domain: "NewMemo.Text", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "이 파일을 텍스트로 열 수 없습니다.",
          NSLocalizedRecoverySuggestionErrorKey: "UTF-8 또는 UTF-16으로 저장된 Markdown·텍스트 파일을 선택해 주세요.",
        ])
    }
    encoding = detected
    if let editor { editor.string = string } else { contents = string }
    if previewScroll != nil { showPreview(true) }
    updateStatus()
  }

  override func data(ofType typeName: String) throws -> Data {
    guard let data = textContent.data(using: encoding) else {
      throw NSError(
        domain: "NewMemo.Text", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: "텍스트를 저장할 수 없습니다."
        ])
    }
    return data
  }
}
