import AppKit
import FinderSync

@main
enum Main {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
  }
}

final class NoteDocumentController: NSDocumentController {
  private(set) var hasRequestedOpen = false
  private(set) var openingCount = 0

  override func openDocument(
    withContentsOf url: URL, display: Bool,
    completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
  ) {
    hasRequestedOpen = true
    openingCount += 1
    super.openDocument(withContentsOf: url, display: display) {
      [weak self] document, wasOpen, error in
      self?.openingCount -= 1
      completionHandler(document, wasOpen, error)
    }
  }

  override func typeForContents(of url: URL) throws -> String { "public.plain-text" }

  override func documentClass(forType typeName: String) -> AnyClass? {
    PlainTextDocument.self
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let documents = NoteDocumentController()
  private var welcome: WelcomeWindowController?
  private var settings: SettingsWindowController?
  private var handledOpen = false
  private var isReady = false
  private var pendingURLs: [URL] = []
  private var activeUtilities = 0
  private var activeTransfers = 0
  private var terminateAfterTransfers = false
  private var idleTermination: DispatchWorkItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    try? SettingsStore.publishMenu()
    do { try RequestAuthorization.prepare() } catch { present(error) }
    buildMenu()
    isReady = true
    if !pendingURLs.isEmpty {
      let urls = pendingURLs
      pendingURLs.removeAll()
      handleOpen(urls)
    } else if !handledOpen && !documents.hasRequestedOpen {
      showWelcome(nil)
    }
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    activeUtilities == 0
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard activeTransfers > 0 else { return .terminateNow }
    terminateAfterTransfers = true
    return .terminateLater
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag && isReady && pendingURLs.isEmpty && documents.openingCount == 0 {
      if let document = documents.documents.first {
        document.showWindows()
      } else {
        showWelcome(nil)
      }
    }
    return true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    idleTermination?.cancel()
    idleTermination = nil
    handledOpen = true
    guard isReady else {
      pendingURLs.append(contentsOf: urls)
      return
    }
    handleOpen(urls)
  }

  private func handleOpen(_ urls: [URL]) {
    for incomingURL in urls {
      if incomingURL.isFileURL {
        openDocument(incomingURL)
      } else {
        do {
          let url = try RequestAuthorization.verify(incomingURL)
          if url.absoluteString == "newmemo://settings" {
            showSettings(nil)
          } else if let request = try? UtilityRequest(url: url) {
            performUtility(request)
          } else if let request = try? FolderCreateRequest(url: url) {
            createFolder(in: request.directory)
          } else if let request = try? PresetCreateRequest(url: url) {
            create(in: request.directory, presetID: request.presetID)
          } else {
            let request = try CreateRequest(url: url)
            create(in: request.directory, kind: request.kind)
          }
        } catch { present(error) }
      }
    }
  }

  @objc func showWelcome(_ sender: Any?) {
    if welcome == nil {
      welcome = WelcomeWindowController(
        create: { [weak self] directory, presetID in self?.create(in: directory, presetID: presetID)
        },
        folder: { [weak self] directory in self?.createFolder(in: directory) },
        utility: { [weak self] request in self?.performUtility(request) },
        open: { [weak self] in self?.openExisting(nil) },
        settings: { [weak self] in self?.showSettings(nil) }
      )
    }
    welcome?.refreshExtensionStatus()
    welcome?.refreshPresets()
    welcome?.showWindow(nil)
    welcome?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc func showSettings(_ sender: Any?) {
    if settings == nil {
      settings = SettingsWindowController(
        onSave: { [weak self] in
          self?.welcome?.refreshPresets()
        },
        onClose: { [weak self] in
          DispatchQueue.main.async { self?.settings = nil }
        })
    }
    settings?.showWindow(nil)
    settings?.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  @objc func openExisting(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.title = "메모 열기"
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    panel.urls.forEach(openDocument)
  }

  private func create(in directory: URL, kind: NoteKind) {
    do {
      let settings = try SettingsStore.loadForCreation()
      let preset =
        settings.presets.first { $0.id == kind.rawValue }
        ?? AppSettings.defaults.presets.first { $0.id == kind.rawValue }!
      create(in: directory, preset: preset)
    } catch { present(error) }
  }

  private func create(in directory: URL, presetID: String) {
    do {
      let settings = try SettingsStore.loadForCreation()
      guard let preset = settings.presets.first(where: { $0.id == presetID && $0.isEnabled }) else {
        throw NoteError.invalidRequest
      }
      create(in: directory, preset: preset)
    } catch { present(error) }
  }

  private func create(in directory: URL, preset: FilePreset) {
    do {
      revealInFinder(try NoteFiles.create(in: directory, preset: preset))
    } catch { present(error) }
  }

  private func createFolder(in directory: URL) {
    do {
      let basename = try SettingsStore.loadForCreation().folderBasename
      revealInFinder(try NoteFiles.createFolder(in: directory, basename: basename))
    } catch { present(error) }
  }

  private func revealInFinder(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
    terminateIfIdle()
  }

  private func terminateIfIdle() {
    idleTermination?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      if self.documents.documents.isEmpty, self.documents.openingCount == 0,
        self.pendingURLs.isEmpty, self.activeUtilities == 0, self.settings == nil,
        !NSApp.windows.contains(where: { $0.isVisible || $0.isMiniaturized })
      {
        NSApp.terminate(nil)
      }
    }
    idleTermination = work
    // A single grace period lets Launch Services deliver adjacent Finder requests.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
  }

  private func performUtility(_ request: UtilityRequest) {
    activeUtilities += 1
    defer {
      activeUtilities -= 1
      terminateIfIdle()
    }
    do {
      let directory = request.paths[0]
      switch request.action {
      case .clipboardText, .clipboardMarkdown:
        let text = try UtilityActions.clipboardText()
        let ext = request.action == .clipboardMarkdown ? "md" : "txt"
        guard
          let name = UtilityActions.promptName(
            defaultName: "클립보드", fileExtension: ext, directory: directory)
        else {
          return
        }
        let preset = FilePreset(
          id: "clipboard", name: "클립보드", fileExtension: ext, basename: name,
          template: text, isEnabled: true)
        revealInFinder(try NoteFiles.create(in: directory, preset: preset))
      case .clipboardPNG:
        try autoreleasepool {
          let data = try UtilityActions.clipboardPNG()
          guard
            let name = UtilityActions.promptName(
              defaultName: "클립보드", fileExtension: "png", directory: directory)
          else { return }
          revealInFinder(
            try FileActions.saveClipboardData(
              data, in: directory, basename: name, fileExtension: "png"))
        }
      case .copyPaths, .copyNames:
        try UtilityActions.copy(request.paths, namesOnly: request.action == .copyNames)
      case .sendCopy, .sendMove:
        let moving = request.action == .sendMove
        guard
          let destination = UtilityActions.chooseDestination(moving: moving, sources: request.paths)
        else { return }
        transfer(request.paths, to: destination, moving: moving)
      case .terminal:
        guard (try directory.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true,
          let terminal = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal")
        else { throw NoteError.invalidDirectory }
        activeUtilities += 1
        NSWorkspace.shared.open(
          [directory], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
          DispatchQueue.main.async {
            guard let self else { return }
            self.activeUtilities -= 1
            if let error { self.present(error) }
            self.terminateIfIdle()
          }
        }
      }
    } catch { present(error) }
  }

  private func transfer(_ paths: [URL], to directory: URL, moving: Bool) {
    activeUtilities += 1
    activeTransfers += 1
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 64), styleMask: [.titled],
      backing: .buffered, defer: false)
    panel.title = moving ? "파일을 이동하고 있습니다…" : "파일을 복사하고 있습니다…"
    let progress = NSProgressIndicator(frame: NSRect(x: 24, y: 24, width: 312, height: 16))
    progress.isIndeterminate = true
    progress.startAnimation(nil)
    panel.contentView?.addSubview(progress)
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let result: Result<[URL], Error> = autoreleasepool {
        Result {
          try moving
            ? FileActions.moveItems(paths, to: directory)
            : FileActions.copyItems(paths, to: directory)
        }
      }
      DispatchQueue.main.async {
        guard let self else { return }
        progress.stopAnimation(nil)
        self.activeUtilities -= 1
        self.activeTransfers -= 1
        // Keep this last window alive until errors/reveal are handled.
        switch result {
        case .success(let urls): NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .failure(let error): self.present(error)
        }
        panel.close()
        if self.terminateAfterTransfers && self.activeTransfers == 0 {
          NSApp.reply(toApplicationShouldTerminate: true)
        } else {
          self.terminateIfIdle()
        }
      }
    }
  }

  private func openDocument(_ url: URL) {
    documents.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
      if let error { self?.present(error) } else { NSApp.activate(ignoringOtherApps: true) }
    }
  }

  private func present(_ error: Error) {
    defer { terminateIfIdle() }
    NSApp.activate(ignoringOtherApps: true)
    NSAlert(error: error).runModal()
  }

  private func item(
    _ title: String, _ action: Selector?, _ key: String = "", target: AnyObject? = nil
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = target
    return item
  }

  private func buildMenu() {
    let main = NSMenu()
    func add(_ title: String, items: [NSMenuItem]) -> NSMenu {
      let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      let menu = NSMenu(title: title)
      items.forEach(menu.addItem)
      root.submenu = menu
      main.addItem(root)
      return menu
    }
    _ = add(
      "새 메모",
      items: [
        item("새 메모에 관하여", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
        .separator(),
        item("파일 형식 및 템플릿…", #selector(showSettings(_:)), ",", target: self),
        .separator(),
        item("새 메모 가리기", #selector(NSApplication.hide(_:)), "h"),
        .separator(),
        item("새 메모 종료", #selector(NSApplication.terminate(_:)), "q"),
      ])
    let saveAs = item("다른 이름으로 저장…", #selector(NSDocument.saveAs(_:)), "s")
    saveAs.keyEquivalentModifierMask = [.command, .option, .shift]
    _ = add(
      "파일",
      items: [
        item("새 메모…", #selector(showWelcome(_:)), "n", target: self),
        item("열기…", #selector(openExisting(_:)), "o", target: self),
        .separator(),
        item("닫기", #selector(NSWindow.performClose(_:)), "w"),
        item("저장", #selector(NSDocument.save(_:)), "s"),
        saveAs,
      ])
    let find = item("찾기…", #selector(NSTextView.performFindPanelAction(_:)), "f")
    find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
    let findNext = item("다음 찾기", #selector(NSTextView.performFindPanelAction(_:)), "g")
    findNext.tag = Int(NSFindPanelAction.next.rawValue)
    _ = add(
      "편집",
      items: [
        item("실행 취소", Selector(("undo:")), "z"),
        item("다시 실행", Selector(("redo:")), "Z"),
        .separator(),
        item("잘라내기", #selector(NSText.cut(_:)), "x"),
        item("복사", #selector(NSText.copy(_:)), "c"),
        item("붙여넣기", #selector(NSText.paste(_:)), "v"),
        item("모두 선택", #selector(NSText.selectAll(_:)), "a"),
        .separator(), find, findNext,
      ])
    let preview = item("Markdown 편집 / 미리보기", #selector(PlainTextDocument.togglePreview(_:)), "p")
    preview.keyEquivalentModifierMask = [.command, .shift]
    _ = add(
      "보기",
      items: [
        preview, item("메모 창 맨 위 고정", #selector(PlainTextDocument.toggleAlwaysOnTop(_:))),
      ])
    let windowMenu = add(
      "윈도우",
      items: [
        item("최소화", #selector(NSWindow.performMiniaturize(_:)), "m"),
        item("확대/축소", #selector(NSWindow.performZoom(_:))),
        .separator(),
        item("모두 앞으로 가져오기", #selector(NSApplication.arrangeInFront(_:))),
      ])
    NSApp.windowsMenu = windowMenu
    NSApp.mainMenu = main
  }
}
