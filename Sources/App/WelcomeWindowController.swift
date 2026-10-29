import AppKit
import FinderSync

final class WelcomeWindowController: NSWindowController {
  private var directory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)
    .first!
  private let createNote: (URL, String) -> Void
  private let createFolder: (URL) -> Void
  private let performUtility: (UtilityRequest) -> Void
  private let openNote: () -> Void
  private let openSettings: () -> Void
  private let presetPopup = NSPopUpButton()
  private let createButton = NSButton()
  private var presets: [FileMenuPreset] = []
  private let pathLabel = NSTextField(labelWithString: "")
  private let extensionLabel = NSTextField(wrappingLabelWithString: "")

  init(
    create: @escaping (URL, String) -> Void, folder: @escaping (URL) -> Void,
    utility: @escaping (UtilityRequest) -> Void,
    open: @escaping () -> Void,
    settings: @escaping () -> Void
  ) {
    createNote = create
    createFolder = folder
    performUtility = utility
    openNote = open
    openSettings = settings
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 490),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered, defer: false
    )
    window.title = "새 메모"
    window.center()
    window.isReleasedWhenClosed = false
    super.init(window: window)
    makeContent()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func makeContent() {
    guard let content = window?.contentView else { return }
    let icon = NSImageView(
      image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil)
        ?? NSImage())
    icon.contentTintColor = .controlAccentColor
    icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
    let title = NSTextField(labelWithString: "생각이 떠오르면, 새 메모")
    title.font = .systemFont(ofSize: 24, weight: .semibold)
    let subtitle = NSTextField(labelWithString: "원하는 형식과 템플릿으로 바로 적으세요.")
    subtitle.textColor = .secondaryLabelColor
    subtitle.font = .systemFont(ofSize: 14)
    let heading = NSStackView(views: [icon, title, subtitle])
    heading.orientation = .vertical
    heading.spacing = 10
    heading.alignment = .centerX

    presetPopup.setAccessibilityLabel("파일 형식")
    createButton.title = "파일 만들기"
    createButton.target = self
    createButton.action = #selector(createSelected)
    createButton.bezelStyle = .rounded
    createButton.controlSize = .large
    let folder = button(
      "새 폴더 만들기", action: #selector(createNewFolder), symbol: "folder.badge.plus")
    folder.controlSize = .large
    let buttons = NSStackView(views: [presetPopup, createButton, folder])
    buttons.spacing = 12
    buttons.distribution = .fillEqually

    pathLabel.stringValue = directory.path
    pathLabel.font = .systemFont(ofSize: 11)
    pathLabel.textColor = .secondaryLabelColor
    pathLabel.lineBreakMode = .byTruncatingMiddle
    pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    pathLabel.setAccessibilityLabel("저장할 폴더")
    let choose = button("폴더 선택…", action: #selector(chooseDirectory))
    choose.controlSize = .small
    let location = NSStackView(views: [pathLabel, choose])
    location.spacing = 12

    let separator = NSBox()
    separator.boxType = .separator
    extensionLabel.font = .systemFont(ofSize: 12)
    extensionLabel.textColor = .secondaryLabelColor
    let settings = button(
      "Finder 확장 설정 열기…", action: #selector(openExtensionSettings), symbol: "gearshape")
    let existing = button("기존 메모 열기…", action: #selector(openExisting), symbol: "folder")
    let customize = button(
      "파일 형식 및 템플릿…", action: #selector(customize), symbol: "slider.horizontal.3")
    let footer = NSStackView(views: [settings, existing])
    footer.distribution = .fillEqually
    footer.spacing = 12
    let tools = NSPopUpButton(frame: .zero, pullsDown: true)
    tools.addItem(withTitle: "클립보드를 파일로 저장…")
    for (title, action) in [
      ("텍스트 (.txt)…", UtilityAction.clipboardText),
      ("Markdown (.md)…", .clipboardMarkdown), ("이미지 (.png)…", .clipboardPNG),
    ] {
      let item = NSMenuItem(title: title, action: #selector(saveClipboard(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action.rawValue
      tools.menu?.addItem(item)
    }

    let stack = NSStackView(views: [
      heading, buttons, location, tools, customize, separator, extensionLabel, footer,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -36),
      stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
      buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
      location.widthAnchor.constraint(equalTo: stack.widthAnchor),
      separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
      extensionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
      footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    refreshExtensionStatus()
    refreshPresets()
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshExtensionStatus),
      name: NSApplication.didBecomeActiveNotification, object: nil)
  }

  private func button(_ title: String, action: Selector, symbol: String? = nil) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .rounded
    if let symbol {
      button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      button.imagePosition = .imageLeading
    }
    return button
  }

  @objc func refreshExtensionStatus() {
    extensionLabel.stringValue =
      FIFinderSyncController.isExtensionEnabled
      ? "Finder 확장이 켜져 있습니다. 우클릭 메뉴에서 파일 형식을 선택하세요. 도구 막대 사용자화에서도 ‘새 메모’를 추가할 수 있습니다."
      : "우클릭 메뉴를 사용하려면 Finder 확장 설정에서 ‘새 메모’를 한 번 켜 주세요."
  }

  @objc private func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.title = "새 메모를 만들 폴더 선택"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = directory
    panel.prompt = "선택"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    directory = url
    pathLabel.stringValue = url.path
    pathLabel.toolTip = url.path
  }

  func refreshPresets() {
    let selected = presetPopup.indexOfSelectedItem
    let previousID = presets.indices.contains(selected) ? presets[selected].id : nil
    presets = SettingsStore.loadMenu().presets.filter(\.isEnabled)
    presetPopup.removeAllItems()
    // NSPopUpButton.addItems(withTitles:) drops duplicate labels, breaking index mapping.
    for preset in presets {
      presetPopup.menu?.addItem(
        NSMenuItem(title: preset.name, action: nil, keyEquivalent: ""))
    }
    if let index = presets.firstIndex(where: { $0.id == previousID }) {
      presetPopup.selectItem(at: index)
    }
    if presets.isEmpty { presetPopup.addItem(withTitle: "설정에서 파일 형식을 켜 주세요") }
    createButton.isEnabled = !presets.isEmpty
  }

  @objc private func createSelected() {
    let index = presetPopup.indexOfSelectedItem
    guard presets.indices.contains(index) else { return }
    createNote(directory, presets[index].id)
  }
  @objc private func customize() { openSettings() }
  @objc private func createNewFolder() { createFolder(directory) }
  @objc private func saveClipboard(_ sender: NSMenuItem) {
    guard let raw = sender.representedObject as? String, let action = UtilityAction(rawValue: raw)
    else { return }
    performUtility(UtilityRequest(action: action, paths: [directory]))
  }
  @objc private func openExisting() { openNote() }
  @objc private func openExtensionSettings() {
    FIFinderSyncController.showExtensionManagementInterface()
  }
}
