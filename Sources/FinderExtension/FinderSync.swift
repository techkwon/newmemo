import AppKit
import FinderSync

@objc(NewMemoFinderSync)
final class NewMemoFinderSync: FIFinderSync {
  private var requests: [Int: URL] = [:]
  private var nextTag = 1

  override init() {
    super.init()
    FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
  }

  override var toolbarItemName: String { "새 메모" }
  override var toolbarItemToolTip: String { "이 폴더에 새 파일 또는 폴더 만들기" }
  override var toolbarItemImage: NSImage {
    NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "새 메모") ?? NSImage()
  }

  override func menu(for menuKind: FIMenuKind) -> NSMenu? {
    let controller = FIFinderSyncController.default()
    let target = controller.targetedURL()
    let selection = controller.selectedItemURLs() ?? []
    let context: FinderMenuContext
    switch menuKind {
    case .contextualMenuForItems: context = .items
    case .contextualMenuForSidebar: context = .sidebar
    case .toolbarItemMenu: context = .toolbar
    default: context = .background
    }
    let snapshot = FinderTarget(context: context, target: target, selection: selection)
    let candidate = snapshot.creationDirectory
    guard candidate?.isFileURL == true || menuKind == .toolbarItemMenu || !selection.isEmpty else {
      return nil
    }
    let selectedPaths = snapshot.selectedPaths
    let settings = SettingsStore.loadMenu()
    let menu = NSMenu(title: "새 메모")
    let contents = NSMenu(title: "새 파일 만들기")
    menu.autoenablesItems = false
    contents.autoenablesItems = false
    // Only the currently displayed menu needs its destination snapshot. In particular,
    // do not retain repeated multi-selection URLs across hundreds of old menu items.
    requests.removeAll(keepingCapacity: true)
    let folder = makeItem(
      "새 폴더 만들기", url: candidate.map { FolderCreateRequest(directory: $0).url })
    folder.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
    menu.addItem(folder)
    for preset in settings.presets where preset.isEnabled {
      let item = makeItem(
        "새 \(preset.name) 파일",
        url: candidate.map {
          PresetCreateRequest(directory: $0, presetID: preset.id).url
        })
      item.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
      contents.addItem(item)
    }
    if contents.items.isEmpty {
      let empty = NSMenuItem(title: "활성화된 파일 형식이 없습니다", action: nil, keyEquivalent: "")
      contents.addItem(empty)
    }
    if settings.useSubmenu && menuKind != .toolbarItemMenu {
      let parent = NSMenuItem(title: "새 파일 만들기", action: nil, keyEquivalent: "")
      parent.submenu = contents
      menu.addItem(parent)
    } else {
      for item in contents.items {
        contents.removeItem(item)
        menu.addItem(item)
      }
    }
    let pathTargets = selectedPaths.isEmpty ? candidate.map { [$0] } ?? [] : selectedPaths
    menu.addItem(
      makeItem(
        selectedPaths.isEmpty ? "현재 폴더 경로 복사" : "전체 경로 복사",
        url: UtilityRequest(action: .copyPaths, paths: pathTargets).url))
    let clipboard = NSMenu(title: "클립보드를 파일로 저장")
    clipboard.autoenablesItems = false
    for (title, action) in [
      ("텍스트 (.txt)…", UtilityAction.clipboardText),
      ("Markdown (.md)…", .clipboardMarkdown), ("이미지 (.png)…", .clipboardPNG),
    ] {
      clipboard.addItem(
        makeItem(
          title, url: candidate.flatMap { UtilityRequest(action: action, paths: [$0]).url }))
    }
    addSubmenu(clipboard, to: menu)
    if !selectedPaths.isEmpty {
      let actions = NSMenu(title: "파일 작업")
      actions.autoenablesItems = false
      for (title, action) in [
        ("파일 이름·목록 복사", UtilityAction.copyNames),
        ("폴더로 복사…", .sendCopy), ("폴더로 이동…", .sendMove),
      ] {
        actions.addItem(
          makeItem(title, url: UtilityRequest(action: action, paths: selectedPaths).url))
      }
      addSubmenu(actions, to: menu)
    }
    menu.addItem(
      makeItem(
        "여기서 터미널 열기", url: candidate.flatMap { UtilityRequest(action: .terminal, paths: [$0]).url })
    )
    menu.addItem(.separator())
    menu.addItem(makeItem("파일 형식 및 템플릿…", url: URL(string: "newmemo://settings")))
    return menu
  }

  private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
    let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
    item.submenu = submenu
    menu.addItem(item)
  }

  private func makeItem(_ title: String, url: URL?) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(openRequest(_:)), keyEquivalent: "")
    item.target = self
    item.isEnabled = url != nil
    // Finder serializes menu items across XPC; representedObject is not preserved.
    item.tag = nextTag
    if let url { requests[nextTag] = url }
    nextTag += 1
    return item
  }

  @objc private func openRequest(_ sender: NSMenuItem) {
    guard let request = requests[sender.tag] else { return }
    // The host initializes this small capability on first launch. If preferences
    // were reset, open its settings once, without executing the unauthenticated action.
    let url = (try? RequestAuthorization.authorize(request)) ?? URL(string: "newmemo://settings")!
    let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.open(
      [url], withApplicationAt: appURL, configuration: configuration
    ) { _, error in
      if let error {
        let failure = error as NSError
        // Do not log the request URL: it carries the local authorization capability.
        NSLog("새 메모 열기 실패 (%@: %ld)", failure.domain, failure.code)
      }
    }
  }
}
