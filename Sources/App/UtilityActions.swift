import AppKit
import ImageIO

enum UtilityActions {
  static func promptName(
    defaultName: String, fileExtension: String = "", directory: URL
  ) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "만들 이름을 입력하세요"
    let suffixDetail = fileExtension.isEmpty ? "" : ".\(fileExtension) 확장자는 자동으로 붙습니다."
    let detail = "저장 위치: \(directory.path)\n" + suffixDetail
    alert.informativeText = detail
    alert.addButton(withTitle: "만들기")
    alert.addButton(withTitle: "취소")
    let field = NSTextField(string: defaultName)
    field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
    field.setAccessibilityLabel("새 항목 이름")
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    while alert.runModal() == .alertFirstButtonReturn {
      let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      do {
        try NoteFiles.validateBasename(name)
        guard name.decomposedStringWithCanonicalMapping.utf8.count + fileExtension.utf8.count <= 230
        else { throw NoteError.invalidName }
        return name
      } catch { alert.informativeText = error.localizedDescription + "\n" + detail }
    }
    return nil
  }

  static func copy(_ urls: [URL], namesOnly: Bool, pasteboard: NSPasteboard = .general) throws {
    let text = urls.map { namesOnly ? $0.lastPathComponent : $0.path }.joined(separator: "\n")
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      throw SettingsError.invalid("클립보드에 복사하지 못했습니다.")
    }
  }

  static func clipboardText(pasteboard: NSPasteboard = .general) throws -> String {
    guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
      throw SettingsError.invalid("클립보드에 저장할 글이 없습니다. 먼저 글을 복사해 주세요.")
    }
    guard text.utf8.count <= 262_144 else {
      throw SettingsError.invalid("메모리 사용을 줄이기 위해 글은 UTF-8 256KB까지 저장할 수 있습니다.")
    }
    return text
  }

  static func clipboardPNG(pasteboard: NSPasteboard = .general) throws -> Data {
    // Inspect encoded image dimensions before decoding. Never instantiate an unbounded NSImage.
    guard let type = pasteboard.availableType(from: [.png, .tiff]),
      let data = pasteboard.data(forType: type), data.count <= 16 * 1024 * 1024,
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 4096, height <= 4096, width * height <= 4_194_304
    else {
      throw SettingsError.invalid("PNG·TIFF 이미지를 먼저 복사해 주세요. 최대 16MB, 4096px, 400만 화소까지 저장합니다.")
    }
    if CGImageSourceGetType(source) as String? == "public.png" { return data }
    guard
      let image = CGImageSourceCreateImageAtIndex(
        source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
      let output = CFDataCreateMutable(nil, 0),
      let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
    else { throw SettingsError.invalid("이미지를 PNG로 변환하지 못했습니다.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination), CFDataGetLength(output) <= 16 * 1024 * 1024
    else {
      throw SettingsError.invalid("변환된 이미지의 용량이 너무 큽니다.")
    }
    return output as Data
  }

  static func chooseDestination(moving: Bool, sources: [URL]) -> URL? {
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = moving ? "이동할 폴더 선택" : "복사할 폴더 선택"
    panel.prompt = moving ? "이동" : "복사"
    if let first = sources.first {
      panel.message =
        "선택한 \(sources.count)개 항목: \(first.lastPathComponent)\n원래 위치: \(first.deletingLastPathComponent().path)"
    }
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    let favorites = DestinationFavorites.load()
    let accessory = DestinationPicker(panel: panel, favorites: favorites)
    panel.accessoryView = accessory.view
    panel.isAccessoryViewDisclosed = true
    guard withExtendedLifetime(accessory, { panel.runModal() }) == .OK,
      let directory = panel.url
    else { return nil }
    if accessory.remember.state == .on { DestinationFavorites.add(directory) }
    return directory
  }
}

enum DestinationFavorites {
  static let key = "destinationFolders.v1"
  static func load(defaults: UserDefaults = .standard) -> [URL] {
    (defaults.stringArray(forKey: key) ?? []).prefix(8).compactMap {
      guard $0.hasPrefix("/"), !$0.contains("\0"), $0.utf8.count <= 4096 else { return nil }
      return URL(fileURLWithPath: $0, isDirectory: true)
    }
  }
  static func add(_ directory: URL, defaults: UserDefaults = .standard) {
    let paths =
      [directory.path] + load(defaults: defaults).map(\.path).filter { $0 != directory.path }
    defaults.set(Array(paths.prefix(8)), forKey: key)
  }
}

private final class DestinationPicker: NSObject {
  weak var panel: NSOpenPanel?
  let favorites: [URL]
  let popup = NSPopUpButton()
  let remember = NSButton(checkboxWithTitle: "이 폴더를 즐겨찾기에 추가", target: nil, action: nil)
  let view = NSStackView()

  init(panel: NSOpenPanel, favorites: [URL]) {
    self.panel = panel
    self.favorites = favorites
    super.init()
    popup.addItem(withTitle: "즐겨찾는 폴더…")
    for url in favorites {
      popup.menu?.addItem(NSMenuItem(title: url.path, action: nil, keyEquivalent: ""))
    }
    popup.target = self
    popup.action = #selector(selectFavorite)
    popup.setAccessibilityLabel("즐겨찾는 목적지 폴더")
    popup.isEnabled = !favorites.isEmpty
    view.orientation = .vertical
    view.alignment = .leading
    view.spacing = 8
    view.addArrangedSubview(popup)
    view.addArrangedSubview(remember)
    view.frame = NSRect(x: 0, y: 0, width: 420, height: 64)
  }

  @objc private func selectFavorite() {
    let index = popup.indexOfSelectedItem - 1
    guard favorites.indices.contains(index) else { return }
    panel?.directoryURL = favorites[index]
  }
}
