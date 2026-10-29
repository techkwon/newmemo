import CoreFoundation
import Foundation

struct FilePreset: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var fileExtension: String
  var basename: String
  var template: String
  var isEnabled: Bool

  func validate() throws {
    try validatePresetMetadata(id: id, name: name)
    try NoteFiles.validateBasename(basename)
    let extensionCharacters = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    guard fileExtension.utf8.count <= 32,
      !fileExtension.hasPrefix("."), !fileExtension.hasSuffix("."),
      !fileExtension.contains(".."),
      fileExtension.unicodeScalars.allSatisfy({ extensionCharacters.contains($0) })
    else {
      throw SettingsError.invalid("확장자는 앞의 점 없이 영문, 숫자, 점, -, _로 입력해 주세요.")
    }
    // Reserve room for the collision suffix and extension on filesystems with NAME_MAX=255.
    guard basename.decomposedStringWithCanonicalMapping.utf8.count + fileExtension.utf8.count <= 230
    else {
      throw SettingsError.invalid("기본 파일 이름과 확장자가 너무 깁니다.")
    }
    guard template.utf8.count <= 262_144,
      !template.unicodeScalars.contains(where: {
        $0.value < 32 && ![9, 10, 13].contains($0.value)
      })
    else {
      throw SettingsError.invalid("시작 내용은 제어 문자 없이 256KB 이내로 입력해 주세요. 탭과 줄바꿈은 사용할 수 있습니다.")
    }
  }
}

private func validatePresetMetadata(id: String, name: String) throws {
  let identifierCharacters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
  guard !id.isEmpty, id.utf8.count <= 64,
    id.unicodeScalars.allSatisfy({ identifierCharacters.contains($0) })
  else {
    throw SettingsError.invalid("파일 형식의 식별자가 올바르지 않습니다.")
  }
  guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    name.utf8.count <= 120,
    name.rangeOfCharacter(from: .controlCharacters) == nil
  else {
    throw SettingsError.invalid("메뉴 이름은 줄바꿈 없이 120바이트 이내로 입력해 주세요.")
  }
}

struct FileMenuPreset: Codable, Equatable, Identifiable {
  var id: String
  var name: String
  var isEnabled: Bool

  func validate() throws { try validatePresetMetadata(id: id, name: name) }
}

struct MenuSettings: Codable, Equatable {
  var presets: [FileMenuPreset]
  var useSubmenu: Bool

  init(presets: [FileMenuPreset], useSubmenu: Bool) {
    self.presets = presets
    self.useSubmenu = useSubmenu
  }

  init(settings: AppSettings) {
    presets = settings.presets.map {
      FileMenuPreset(id: $0.id, name: $0.name, isEnabled: $0.isEnabled)
    }
    useSubmenu = settings.useSubmenu
  }

  static let defaults = MenuSettings(settings: .defaults)

  func validate() throws {
    guard presets.count <= 64, Set(presets.map(\.id)).count == presets.count else {
      throw SettingsError.invalid("메뉴의 파일 형식 목록이 올바르지 않습니다.")
    }
    for preset in presets { try preset.validate() }
  }
}

struct AppSettings: Codable, Equatable {
  var presets: [FilePreset]
  var useSubmenu: Bool
  var folderBasename: String

  init(presets: [FilePreset], useSubmenu: Bool, folderBasename: String = "새 폴더") {
    self.presets = presets
    self.useSubmenu = useSubmenu
    self.folderBasename = folderBasename
  }

  private enum CodingKeys: String, CodingKey {
    case presets, useSubmenu, folderBasename
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    presets = try values.decode([FilePreset].self, forKey: .presets)
    useSubmenu = try values.decode(Bool.self, forKey: .useSubmenu)
    // Older settings have no folder name; retain their file names and templates.
    folderBasename = try values.decodeIfPresent(String.self, forKey: .folderBasename) ?? "새 폴더"
  }

  static let defaults = AppSettings(
    presets: [
      FilePreset(
        id: "md", name: "Markdown", fileExtension: "md", basename: "새 메모", template: "",
        isEnabled: true),
      FilePreset(
        id: "txt", name: "텍스트", fileExtension: "txt", basename: "새 메모", template: "",
        isEnabled: true),
      FilePreset(
        id: "json", name: "JSON", fileExtension: "json", basename: "새 파일", template: "{\n  \n}\n",
        isEnabled: false),
      FilePreset(
        id: "yaml", name: "YAML", fileExtension: "yml", basename: "새 파일", template: "",
        isEnabled: false),
      FilePreset(
        id: "html", name: "HTML", fileExtension: "html", basename: "새 파일",
        template:
          "<!doctype html>\n<html lang=\"ko\">\n<head>\n  <meta charset=\"utf-8\">\n  <title>새 문서</title>\n</head>\n<body>\n\n</body>\n</html>\n",
        isEnabled: false),
      FilePreset(
        id: "csv", name: "CSV", fileExtension: "csv", basename: "새 파일", template: "",
        isEnabled: false),
      FilePreset(
        id: "shell", name: "Shell", fileExtension: "sh", basename: "새 스크립트",
        template: "#!/bin/sh\n\n", isEnabled: false),
      FilePreset(
        id: "env", name: "환경 변수", fileExtension: "", basename: ".env", template: "",
        isEnabled: false),
      FilePreset(
        id: "gitignore", name: "Git 제외 목록", fileExtension: "", basename: ".gitignore",
        template: ".DS_Store\n", isEnabled: false),
    ], useSubmenu: false)

  func validate() throws {
    try NoteFiles.validateBasename(folderBasename)
    guard presets.count <= 64 else {
      throw SettingsError.invalid("파일 형식은 최대 64개까지 추가할 수 있습니다.")
    }
    guard Set(presets.map(\.id)).count == presets.count else {
      throw SettingsError.invalid("같은 식별자의 파일 형식이 중복되어 있습니다.")
    }
    for preset in presets { try preset.validate() }
  }
}

enum SettingsError: LocalizedError {
  case invalid(String)
  case saveFailed
  case damagedSettings
  case recoveryFailed
  case recoveryAlreadyExists

  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    case .saveFailed: return "설정을 저장하지 못했습니다. 다시 시도해 주세요."
    case .damagedSettings:
      return "파일 형식 설정을 읽지 못해 생성하지 않았습니다. ‘파일 형식 및 템플릿’에서 설정을 확인하고 저장해 복구해 주세요."
    case .recoveryFailed: return "손상된 설정의 복구 백업을 저장하지 못해 새 설정을 저장하지 않았습니다. 다시 시도해 주세요."
    case .recoveryAlreadyExists:
      return "이전 복구 백업이 있어 손상된 설정을 덮어쓰지 않았습니다. 이전 백업과 현재 설정을 별도로 보관한 후 다시 저장해 주세요."
    }
  }
}

struct SettingsLoadResult {
  let settings: AppSettings
  let usedRecoveryDefaults: Bool
}

enum SettingsStore {
  static let domain = "kr.techkwon.NewMemo"
  static let key = "filePresetSettings.v1"
  static let recoveryKey = "\(key).recovery"
  static let menuKey = "fileMenuSettings.v1"

  static func menuDomain(for domain: String) -> String { "\(domain).Menu" }
  private static let menuByteLimit = 32_768

  static func load() -> AppSettings { load(domain: domain) }

  static func loadResult() -> SettingsLoadResult { loadResult(domain: domain) }

  static func loadForCreation(domain: String = SettingsStore.domain) throws -> AppSettings {
    let loaded = loadResult(domain: domain)
    guard !loaded.usedRecoveryDefaults else { throw SettingsError.damagedSettings }
    return loaded.settings
  }

  static func save(_ settings: AppSettings) throws { try save(settings, domain: domain) }

  static func loadMenu() -> MenuSettings { loadMenu(domain: domain) }

  /// Called by the host once on launch to migrate settings saved before the menu manifest existed.
  static func publishMenu() throws { try publishMenu(domain: domain) }

  static func publishMenu(domain: String) throws {
    // Normal launches inspect only the small manifest. The full template settings
    // are needed once, when upgrading from a version without a valid manifest.
    guard readMenu(domain: domain) == nil else { return }
    let menu = MenuSettings(settings: load(domain: domain))
    let data = try encodedMenu(menu)
    CFPreferencesSetValue(
      menuKey as CFString, data as CFData, menuDomain(for: domain) as CFString,
      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    try synchronize(domains: [menuDomain(for: domain)])
  }

  static func loadMenu(domain: String) -> MenuSettings {
    readMenu(domain: domain) ?? .defaults
  }

  private static func readMenu(domain: String) -> MenuSettings? {
    // Use a physically separate preference domain so Finder's preference cache
    // cannot retain the host's large templates or private starter text.
    let application = menuDomain(for: domain) as CFString
    _ = CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    // Finder never fetches or decodes the potentially multi-megabyte template payload.
    guard
      let data = CFPreferencesCopyValue(
        menuKey as CFString, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        as? Data,
      data.count <= menuByteLimit,
      let menu = try? JSONDecoder().decode(MenuSettings.self, from: data),
      (try? menu.validate()) != nil
    else { return nil }
    return menu
  }

  static func load(domain: String) -> AppSettings {
    loadResult(domain: domain).settings
  }

  static func loadResult(domain: String) -> SettingsLoadResult {
    let application = domain as CFString
    // Host-only: refresh the complete editor and template settings.
    _ = CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    let original = CFPreferencesCopyValue(
      key as CFString, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    if let settings = decodedSettings(original) {
      return SettingsLoadResult(settings: settings, usedRecoveryDefaults: false)
    }
    return SettingsLoadResult(settings: .defaults, usedRecoveryDefaults: original != nil)
  }

  private static func decodedSettings(_ original: CFPropertyList?) -> AppSettings? {
    guard
      let data = original as? Data,
      data.count <= 18_000_000,
      let settings = try? JSONDecoder().decode(AppSettings.self, from: data),
      (try? settings.validate()) != nil
    else { return nil }
    return settings
  }

  static func save(_ settings: AppSettings, domain: String) throws {
    try settings.validate()
    let data = try JSONEncoder().encode(settings)
    guard data.count <= 18_000_000 else {
      throw SettingsError.invalid("템플릿의 전체 용량이 너무 큽니다.")
    }
    let menuData = try encodedMenu(MenuSettings(settings: settings))
    try preserveDamagedSettings(domain: domain)
    let application = domain as CFString
    CFPreferencesSetValue(
      key as CFString, data as CFData, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
    )
    CFPreferencesSetValue(
      menuKey as CFString, menuData as CFData, menuDomain(for: domain) as CFString,
      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    try synchronize(domains: [domain, menuDomain(for: domain)])
  }

  private static func preserveDamagedSettings(domain: String) throws {
    let application = domain as CFString
    try synchronize(domains: [domain])
    guard
      let original = CFPreferencesCopyValue(
        key as CFString, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
      decodedSettings(original) == nil
    else { return }
    if let backup = CFPreferencesCopyValue(
      recoveryKey as CFString, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    {
      // A single permanent backup avoids unbounded retention of private templates.
      // Repeating the same failed recovery is safe; a different original must be preserved too.
      guard CFEqual(backup, original) else { throw SettingsError.recoveryAlreadyExists }
      return
    }
    CFPreferencesSetValue(
      recoveryKey as CFString, original, application,
      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    guard
      CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
      let backup = CFPreferencesCopyValue(
        recoveryKey as CFString, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
      CFEqual(backup, original)
    else { throw SettingsError.recoveryFailed }
  }

  private static func encodedMenu(_ menu: MenuSettings) throws -> Data {
    try menu.validate()
    let data = try JSONEncoder().encode(menu)
    guard data.count <= menuByteLimit else {
      throw SettingsError.invalid("메뉴 설정의 전체 용량이 너무 큽니다.")
    }
    return data
  }

  private static func synchronize(domains: [String]) throws {
    var succeeded = true
    for domain in domains {
      let result = CFPreferencesSynchronize(
        domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      succeeded = result && succeeded
    }
    guard succeeded else { throw SettingsError.saveFailed }
  }
}
