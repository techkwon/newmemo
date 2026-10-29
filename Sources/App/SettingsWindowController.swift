import AppKit

final class SettingsWindowController: NSWindowController, NSTableViewDataSource,
  NSTableViewDelegate, NSWindowDelegate, NSTextFieldDelegate
{
  private var draft = AppSettings.defaults
  private var selectedIndex = -1
  private var updatingSelection = false
  private let onSave: () -> Void
  private let onClose: () -> Void
  private let table = NSTableView()
  private let nameField = NSTextField()
  private let extensionField = NSTextField()
  private let basenameField = NSTextField()
  private let folderBasenameField = NSTextField()
  private let subtitle = NSTextField(wrappingLabelWithString: "")
  private let enabledButton = NSButton(checkboxWithTitle: "Finder 메뉴에 표시", target: nil, action: nil)
  private let templateView = NSTextView()
  private let submenuButton = NSButton(
    checkboxWithTitle: "우클릭 메뉴를 ‘새 파일’ 하위 메뉴로 모으기", target: nil, action: nil)
  private var removeButton: NSButton!
  private var upButton: NSButton!
  private var downButton: NSButton!

  init(onSave: @escaping () -> Void, onClose: @escaping () -> Void = {}) {
    self.onSave = onSave
    self.onClose = onClose
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 820, height: 630),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    window.title = "파일 형식 및 템플릿"
    window.minSize = NSSize(width: 800, height: 610)
    window.isReleasedWhenClosed = false
    window.center()
    super.init(window: window)
    window.delegate = self
    makeContent()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func windowWillClose(_ notification: Notification) { onClose() }

  override func showWindow(_ sender: Any?) {
    if window?.isVisible != true {
      let loaded = SettingsStore.loadResult()
      draft = loaded.settings
      subtitle.stringValue =
        loaded.usedRecoveryDefaults
        ? "저장된 설정을 읽지 못해 기본값을 표시합니다. 저장하면 원래 설정을 복구용으로 보관합니다."
        : "파일 형식마다 이름과 시작 내용을 지정하세요. 변경한 설정은 저장 후 적용됩니다."
      subtitle.textColor = loaded.usedRecoveryDefaults ? .systemOrange : .secondaryLabelColor
      submenuButton.state = draft.useSubmenu ? .on : .off
      folderBasenameField.stringValue = draft.folderBasename
      selectRow(draft.presets.isEmpty ? -1 : 0)
    }
    super.showWindow(sender)
    window?.makeKeyAndOrderFront(sender)
  }

  private func makeContent() {
    guard let content = window?.contentView else { return }
    let title = NSTextField(labelWithString: "자주 만드는 파일을 원하는 순서로")
    title.font = .systemFont(ofSize: 20, weight: .semibold)
    subtitle.textColor = .secondaryLabelColor

    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("preset"))
    column.title = "파일 형식"
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 35
    table.style = .inset
    table.allowsEmptySelection = false
    table.dataSource = self
    table.delegate = self
    table.setAccessibilityLabel("파일 형식 목록")
    let listScroll = NSScrollView()
    listScroll.documentView = table
    listScroll.hasVerticalScroller = true
    listScroll.borderType = .bezelBorder

    let add = button("추가", #selector(addPreset))
    removeButton = button("삭제", #selector(removePreset))
    upButton = button("↑", #selector(movePresetUp))
    downButton = button("↓", #selector(movePresetDown))
    upButton.setAccessibilityLabel("위로 이동")
    downButton.setAccessibilityLabel("아래로 이동")
    let listButtons = NSStackView(views: [add, removeButton, upButton, downButton])
    listButtons.spacing = 5
    listButtons.distribution = .fillEqually
    let list = vertical([listScroll, listButtons], spacing: 8)

    nameField.placeholderString = "예: 수업 메모"
    extensionField.placeholderString = "예: md (점 제외)"
    basenameField.placeholderString = "예: 새 메모"
    nameField.setAccessibilityLabel("메뉴 표시명")
    extensionField.setAccessibilityLabel("파일 확장자")
    basenameField.setAccessibilityLabel("기본 파일 이름")
    for field in [nameField, extensionField, basenameField] { field.delegate = self }
    enabledButton.target = self
    enabledButton.action = #selector(updatePresetRow)
    let grid = NSGridView(views: [
      [NSTextField(labelWithString: "메뉴 표시명"), nameField],
      [NSTextField(labelWithString: "확장자"), extensionField],
      [NSTextField(labelWithString: "기본 파일 이름"), basenameField],
    ])
    grid.rowSpacing = 12
    grid.columnSpacing = 16
    grid.column(at: 0).xPlacement = .trailing
    grid.column(at: 1).xPlacement = .fill
    grid.yPlacement = .center
    let filenameHelp = NSTextField(
      wrappingLabelWithString:
        "이 형식을 만들 때 사용할 기본 이름입니다. 확장자는 점 없이 입력하세요. .env 파일은 확장자를 비우고 기본 이름에 .env를 입력하세요.")
    filenameHelp.font = .systemFont(ofSize: 11)
    filenameHelp.textColor = .secondaryLabelColor

    let templateLabel = NSTextField(labelWithString: "시작 템플릿")
    templateLabel.font = .systemFont(ofSize: 13, weight: .medium)
    templateView.isRichText = false
    templateView.importsGraphics = false
    templateView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    templateView.isAutomaticQuoteSubstitutionEnabled = false
    templateView.isAutomaticDashSubstitutionEnabled = false
    templateView.isAutomaticTextReplacementEnabled = false
    templateView.allowsUndo = true
    templateView.textContainerInset = NSSize(width: 8, height: 8)
    templateView.isVerticallyResizable = true
    templateView.isHorizontallyResizable = false
    templateView.minSize = NSSize(width: 0, height: 0)
    templateView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    templateView.frame = NSRect(x: 0, y: 0, width: 400, height: 150)
    templateView.autoresizingMask = [.width]
    templateView.textContainer?.widthTracksTextView = true
    templateView.setAccessibilityLabel("시작 템플릿 내용")
    let templateScroll = NSScrollView()
    templateScroll.documentView = templateView
    templateScroll.hasVerticalScroller = true
    templateScroll.borderType = .bezelBorder
    let templateHelp = NSTextField(labelWithString: "비워 두면 빈 파일을 만듭니다. 내용은 UTF-8 텍스트로 저장됩니다.")
    templateHelp.font = .systemFont(ofSize: 11)
    templateHelp.textColor = .secondaryLabelColor
    let details = vertical(
      [enabledButton, grid, filenameHelp, templateLabel, templateScroll, templateHelp], spacing: 10)
    let body = NSStackView(views: [list, details])
    body.orientation = .horizontal
    body.alignment = .top
    body.spacing = 20

    let separator = NSBox()
    separator.boxType = .separator
    folderBasenameField.placeholderString = "예: 수업 자료"
    folderBasenameField.setAccessibilityLabel("기본 폴더 이름")
    let folderName = NSStackView(views: [
      NSTextField(labelWithString: "기본 폴더 이름"), folderBasenameField,
    ])
    folderName.spacing = 12
    let behaviorHelp = NSTextField(
      labelWithString: "파일과 폴더는 위 기본 이름으로 생성하고 Finder에서 선택합니다. 파일은 직접 열어 주세요.")
    behaviorHelp.textColor = .secondaryLabelColor
    behaviorHelp.font = .systemFont(ofSize: 11)
    let options = vertical([submenuButton, folderName, behaviorHelp], spacing: 7)
    let cancel = button("취소", #selector(cancelChanges))
    cancel.keyEquivalent = "\u{1b}"
    let save = button("저장", #selector(saveChanges))
    save.keyEquivalent = "\r"
    let spacer = NSView()
    let footer = NSStackView(views: [spacer, cancel, save])
    footer.spacing = 8
    let stack = vertical([title, subtitle, body, separator, options, footer], spacing: 14)
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
      subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
      body.widthAnchor.constraint(equalTo: stack.widthAnchor),
      body.heightAnchor.constraint(greaterThanOrEqualToConstant: 310),
      list.widthAnchor.constraint(equalToConstant: 220),
      list.heightAnchor.constraint(equalTo: body.heightAnchor),
      details.heightAnchor.constraint(equalTo: body.heightAnchor),
      listScroll.widthAnchor.constraint(equalTo: list.widthAnchor),
      listButtons.widthAnchor.constraint(equalTo: list.widthAnchor),
      grid.widthAnchor.constraint(equalTo: details.widthAnchor),
      filenameHelp.widthAnchor.constraint(equalTo: details.widthAnchor),
      templateScroll.widthAnchor.constraint(equalTo: details.widthAnchor),
      templateScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
      separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
      options.widthAnchor.constraint(equalTo: stack.widthAnchor),
      folderName.widthAnchor.constraint(equalTo: options.widthAnchor),
      footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
      cancel.widthAnchor.constraint(equalToConstant: 80),
      save.widthAnchor.constraint(equalToConstant: 80),
    ])
  }

  private func vertical(_ views: [NSView], spacing: CGFloat) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
  }

  private func button(_ title: String, _ action: Selector) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .rounded
    return button
  }

  func numberOfRows(in tableView: NSTableView) -> Int { draft.presets.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let preset = draft.presets[row]
    let suffix = preset.fileExtension.isEmpty ? "" : " (.\(preset.fileExtension))"
    let label = NSTextField(
      labelWithString: "\(preset.isEnabled ? "✓" : "–")  \(preset.name)\(suffix)")
    label.lineBreakMode = .byTruncatingTail
    label.textColor = preset.isEnabled ? .labelColor : .secondaryLabelColor
    return label
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !updatingSelection else { return }
    flushFields()
    reloadPresetRow()
    selectedIndex = table.selectedRow
    loadFields()
  }

  func controlTextDidChange(_ notification: Notification) { updatePresetRow() }

  @objc private func updatePresetRow() {
    flushFields()
    reloadPresetRow()
  }

  private func reloadPresetRow() {
    guard draft.presets.indices.contains(selectedIndex) else { return }
    table.reloadData(
      forRowIndexes: IndexSet(integer: selectedIndex), columnIndexes: IndexSet(integer: 0))
  }

  private func flushFields() {
    guard draft.presets.indices.contains(selectedIndex) else { return }
    draft.presets[selectedIndex].name = nameField.stringValue.trimmingCharacters(
      in: .whitespacesAndNewlines)
    draft.presets[selectedIndex].fileExtension = extensionField.stringValue.trimmingCharacters(
      in: .whitespacesAndNewlines)
    draft.presets[selectedIndex].basename = basenameField.stringValue.trimmingCharacters(
      in: .whitespacesAndNewlines)
    draft.presets[selectedIndex].template = templateView.string
    draft.presets[selectedIndex].isEnabled = enabledButton.state == .on
  }

  private func loadFields() {
    let hasSelection = draft.presets.indices.contains(selectedIndex)
    let preset = hasSelection ? draft.presets[selectedIndex] : nil
    nameField.stringValue = preset?.name ?? ""
    extensionField.stringValue = preset?.fileExtension ?? ""
    basenameField.stringValue = preset?.basename ?? ""
    templateView.string = preset?.template ?? ""
    templateView.undoManager?.removeAllActions()
    enabledButton.state = preset?.isEnabled == true ? .on : .off
    for field in [nameField, extensionField, basenameField] { field.isEnabled = hasSelection }
    enabledButton.isEnabled = hasSelection
    templateView.isEditable = hasSelection
    removeButton.isEnabled = hasSelection
    upButton.isEnabled = hasSelection && selectedIndex > 0
    downButton.isEnabled = hasSelection && selectedIndex < draft.presets.count - 1
  }

  private func selectRow(_ index: Int) {
    updatingSelection = true
    selectedIndex = index
    table.reloadData()
    if draft.presets.indices.contains(index) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
      table.scrollRowToVisible(index)
    } else {
      table.deselectAll(nil)
    }
    updatingSelection = false
    loadFields()
  }

  @objc private func addPreset() {
    guard draft.presets.count < 64 else {
      NSSound.beep()
      return
    }
    flushFields()
    draft.presets.append(
      FilePreset(
        id: UUID().uuidString, name: "새 형식", fileExtension: "txt", basename: "새 파일", template: "",
        isEnabled: true))
    selectRow(draft.presets.count - 1)
    window?.makeFirstResponder(nameField)
    nameField.selectText(nil)
  }

  @objc private func removePreset() {
    guard draft.presets.indices.contains(selectedIndex) else { return }
    draft.presets.remove(at: selectedIndex)
    selectRow(draft.presets.isEmpty ? -1 : min(selectedIndex, draft.presets.count - 1))
  }

  @objc private func movePresetUp() { move(by: -1) }
  @objc private func movePresetDown() { move(by: 1) }

  private func move(by offset: Int) {
    let destination = selectedIndex + offset
    guard draft.presets.indices.contains(selectedIndex), draft.presets.indices.contains(destination)
    else { return }
    flushFields()
    draft.presets.swapAt(selectedIndex, destination)
    selectRow(destination)
  }

  @objc private func cancelChanges() { close() }

  @objc private func saveChanges() {
    window?.makeFirstResponder(nil)
    flushFields()
    draft.useSubmenu = submenuButton.state == .on
    draft.folderBasename = folderBasenameField.stringValue
    do {
      try SettingsStore.save(draft)
      onSave()
      close()
    } catch {
      let alert = NSAlert(error: error)
      if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
  }
}
