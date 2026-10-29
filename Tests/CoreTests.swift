import CoreFoundation
import Darwin
import Foundation

@main
enum CoreTests {
  static var checks = 0
  static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try condition() else {
      throw NSError(
        domain: "CoreTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  static func rejects(_ block: () throws -> Void, _ message: String) throws {
    do { try block() } catch {
      checks += 1
      return
    }
    throw NSError(domain: "CoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  static func main() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(
      "NewMemoTests-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let first = try NoteFiles.create(in: root, kind: .markdown)
    try check(first.lastPathComponent == "새 메모.md", "기본 Markdown 이름")
    try check(Data(contentsOf: first).isEmpty, "새 파일은 0바이트")
    try Data("보존해야 할 내용".utf8).write(to: first)
    let second = try NoteFiles.create(in: root, kind: .markdown)
    try check(second.lastPathComponent == "새 메모 2.md", "중복 번호")
    try check(String(contentsOf: first, encoding: .utf8) == "보존해야 할 내용", "원본 보존")
    let text = try NoteFiles.create(in: root, kind: .text)
    try check(text.pathExtension == "txt", "텍스트 형식")
    try check(Data(contentsOf: text).isEmpty, "텍스트 0바이트")
    let nested = root.appendingPathComponent("한글 공백 & # % ? + 이모지📁", isDirectory: true)
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    let request = CreateRequest(directory: nested, kind: .text)
    let decoded = try CreateRequest(url: request.url)
    try check(decoded.directory.path == nested.path && decoded.kind == .text, "특수문자 URL 왕복")
    for raw in [
      "https://create?directory=/tmp&type=md", "newmemo://create?directory=relative&type=md",
      "newmemo://create?directory=/tmp&type=sh", "newmemo://create?directory=/tmp&type=md&type=txt",
      "newmemo://create?directory=/tmp&type=md&evil=1", "newmemo://create/x?directory=/tmp&type=md",
    ] {
      try rejects({ _ = try CreateRequest(url: URL(string: raw)!) }, "잘못된 요청 거부: \(raw)")
    }
    for name in ["../escape", "", "..", "a:b", "line\nbreak"] {
      try rejects({ _ = try NoteFiles.create(in: root, kind: .text, basename: name) }, "잘못된 이름 거부")
    }
    try rejects({ _ = try NoteFiles.create(in: first, kind: .text) }, "파일을 폴더로 사용하지 않음")
    try rejects(
      { _ = try NoteFiles.create(in: root.appendingPathComponent("missing"), kind: .text) },
      "없는 폴더 거부")
    let link = root.appendingPathComponent("링크.md")
    try fm.createSymbolicLink(at: link, withDestinationURL: first)
    let afterLink = try NoteFiles.create(in: root, kind: .markdown, basename: "링크")
    try check(afterLink.lastPathComponent == "링크 2.md", "기존 심볼릭 링크 보존")
    let lock = NSLock()
    var paths = Set<String>()
    var failures = [String]()
    DispatchQueue.concurrentPerform(iterations: 40) { _ in
      do {
        let file = try NoteFiles.create(in: nested, kind: .text)
        lock.lock()
        paths.insert(file.path)
        lock.unlock()
      } catch {
        lock.lock()
        failures.append(error.localizedDescription)
        lock.unlock()
      }
    }
    try check(failures.isEmpty && paths.count == 40, "동시 요청 이름 충돌 없이 40개 생성")
    try settingsAndPresetChecks(root: root, nested: nested)
    try settingsRecoveryChecks()
    try menuManifestChecks()
    try folderChecks(root: root, nested: nested, existingFile: first)
    print("PASS: \(checks) checks (including 40 concurrent creations)")
  }

  static func settingsRecoveryChecks() throws {
    let domain = "kr.techkwon.NewMemo.Tests.\(UUID().uuidString)"
    let application = domain as CFString
    let recoveryKey = SettingsStore.recoveryKey
    func read(_ key: String) -> CFPropertyList? {
      CFPreferencesCopyValue(
        key as CFString, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    func set(_ original: CFPropertyList) {
      CFPreferencesSetValue(
        SettingsStore.key as CFString, original, application,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      _ = CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    defer {
      for key in [SettingsStore.key, recoveryKey] {
        CFPreferencesSetValue(
          key as CFString, nil, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      }
      _ = CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      let menuApplication = SettingsStore.menuDomain(for: domain) as CFString
      CFPreferencesSetValue(
        SettingsStore.menuKey as CFString, nil, menuApplication,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      _ = CFPreferencesSynchronize(
        menuApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    try check(!SettingsStore.loadResult(domain: domain).usedRecoveryDefaults, "설정이 없으면 정상 기본값 표시")
    try check(
      try SettingsStore.loadForCreation(domain: domain) == .defaults, "설정이 없으면 기본 형식으로 생성 허용")
    let original = Data("{\"private-template\":\"보존할 전체 원본\"".utf8)
    set(original as CFData)
    try check(SettingsStore.load(domain: domain) == .defaults, "손상된 설정은 기본값 표시")
    try check(SettingsStore.loadResult(domain: domain).usedRecoveryDefaults, "손상된 설정의 복구 안내 상태")
    try rejects({ _ = try SettingsStore.loadForCreation(domain: domain) }, "설정이 손상되면 기본값으로 생성하지 않음")
    try check(read(SettingsStore.key) as? Data == original, "손상된 설정으로 생성 거부 시 원본 보존")
    try check(read(recoveryKey) == nil, "읽기만 할 때 복구 백업을 기록하지 않음")
    var invalid = AppSettings.defaults
    invalid.folderBasename = "../invalid"
    try rejects({ try SettingsStore.save(invalid, domain: domain) }, "잘못된 새 설정은 복구 전에 거부")
    try check(read(recoveryKey) == nil, "실패한 새 설정 검증은 백업을 기록하지 않음")
    try check(read(SettingsStore.key) as? Data == original, "실패한 새 설정 검증은 원본 보존")
    try SettingsStore.save(.defaults, domain: domain)
    try check(read(recoveryKey) as? Data == original, "설정 저장 전에 손상된 전체 원본 백업")
    try check(!SettingsStore.loadResult(domain: domain).usedRecoveryDefaults, "저장된 정상 설정은 복구 안내 해제")
    var customized = AppSettings.defaults
    customized.presets[0].template = "# 보존된 템플릿"
    customized.folderBasename = "수업 자료"
    try SettingsStore.save(customized, domain: domain)
    try check(SettingsStore.load(domain: domain) == customized, "복구 이후 사용자 템플릿과 폴더 이름 저장")
    try check(try SettingsStore.loadForCreation(domain: domain) == customized, "정상 사용자 설정은 생성에 사용")
    try check(read(recoveryKey) as? Data == original, "정상 설정 재저장도 기존 복구 백업 보존")
    set(original as CFData)
    try SettingsStore.save(customized, domain: domain)
    try check(read(recoveryKey) as? Data == original, "동일한 손상 원본의 복구 재시도 허용")

    let menuApplication = SettingsStore.menuDomain(for: domain) as CFString
    let menuBefore =
      CFPreferencesCopyValue(
        SettingsStore.menuKey as CFString, menuApplication,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Data
    let anotherOriginal = Data("두 번째 손상 원본".utf8)
    set(anotherOriginal as CFData)
    try rejects({ try SettingsStore.save(.defaults, domain: domain) }, "다른 복구 백업이 있으면 덮어쓰기 거부")
    try check(read(SettingsStore.key) as? Data == anotherOriginal, "거부 시 현재 손상 원본 보존")
    try check(read(recoveryKey) as? Data == original, "거부 시 이전 복구 백업 보존")
    try check(
      CFPreferencesCopyValue(
        SettingsStore.menuKey as CFString, menuApplication,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Data == menuBefore,
      "복구 거부 시 Finder 메뉴 설정 보존")
    try check(
      CFPreferencesCopyValue(
        recoveryKey as CFString, menuApplication,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) == nil,
      "복구 원본은 Finder 메뉴 도메인에 노출하지 않음")

    // Each isolated corruption below begins after explicitly archiving/removing the previous backup.
    var invalidObject =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(customized))
      as! [String: Any]
    invalidObject["folderBasename"] = "../invalid"
    invalidObject["unknownPrivateField"] = "디코딩으로 누락되면 안 되는 원본"
    let invalidData = try JSONSerialization.data(withJSONObject: invalidObject)
    let damagedValues: [CFPropertyList] = [
      invalidData as CFData, "잘못된 저장 형식" as CFString, Data() as CFData,
    ]
    for damaged in damagedValues {
      CFPreferencesSetValue(
        recoveryKey as CFString, nil, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      set(damaged)
      try check(SettingsStore.loadResult(domain: domain).usedRecoveryDefaults, "다양한 손상 원본의 복구 안내")
      try check(read(recoveryKey) == nil, "손상 원본 읽기는 백업을 만들지 않음")
      try SettingsStore.save(customized, domain: domain)
      let backup = read(recoveryKey)
      try check(backup != nil && CFEqual(backup, damaged), "검증 실패 JSON과 잘못된 저장 형식도 전체 보존")
      try check(SettingsStore.load(domain: domain) == customized, "다양한 손상 원본 복구 후 정상 설정 저장")
    }
  }

  static func folderChecks(root: URL, nested: URL, existingFile: URL) throws {
    let fm = FileManager.default
    let first = try NoteFiles.createFolder(in: nested)
    try check(first.lastPathComponent == "새 폴더", "기본 폴더 이름")
    try check(try first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true, "폴더 생성")
    try check(try fm.contentsOfDirectory(atPath: first.path).isEmpty, "새 폴더는 비어 있음")
    let second = try NoteFiles.createFolder(in: nested)
    try check(second.lastPathComponent == "새 폴더 2", "폴더 충돌 번호")
    try Data("보존".utf8).write(to: root.appendingPathComponent("새 폴더"))
    try fm.createSymbolicLink(
      at: root.appendingPathComponent("새 폴더 2"), withDestinationURL: existingFile)
    let third = try NoteFiles.createFolder(in: root)
    try check(third.lastPathComponent == "새 폴더 3", "기존 파일과 심볼릭 링크 건너뜀")
    try check(
      String(contentsOf: root.appendingPathComponent("새 폴더"), encoding: .utf8) == "보존",
      "이름이 같은 원본 파일 보존")
    try check(
      fm.destinationOfSymbolicLink(atPath: root.appendingPathComponent("새 폴더 2").path)
        == existingFile.path, "심볼릭 링크 보존")
    try rejects({ _ = try NoteFiles.createFolder(in: existingFile) }, "부모가 파일이면 거부")
    try rejects(
      { _ = try NoteFiles.createFolder(in: root.appendingPathComponent("missing")) },
      "없는 부모 거부")
    try rejects(
      { _ = try NoteFiles.createFolder(in: URL(string: "https://example.com")!) },
      "원격 URL 거부")
    let request = FolderCreateRequest(directory: nested)
    try check(
      FolderCreateRequest(url: request.url).directory.path == nested.path, "폴더 요청 특수문자 왕복")
    for raw in [
      "https://create-folder?directory=/tmp", "newmemo://create-folder?directory=relative",
      "newmemo://create-folder?directory=/tmp&directory=/tmp",
      "newmemo://create-folder?directory=/tmp&name=other",
      "newmemo://create-folder/path?directory=/tmp", "newmemo://user@create-folder?directory=/tmp",
      "newmemo://create-folder?directory=/tmp#extra", "newmemo://create-folder?directory=%00",
      "newmemo://create-folder", "newmemo://create-folder?directory",
      "newmemo://create-folder:123?directory=/tmp",
    ] {
      try rejects({ _ = try FolderCreateRequest(url: URL(string: raw)!) }, "잘못된 폴더 요청 거부")
    }
    let lock = NSLock()
    var paths = Set<String>()
    var failures = [String]()
    DispatchQueue.concurrentPerform(iterations: 20) { _ in
      do {
        let folder = try NoteFiles.createFolder(in: nested)
        lock.lock()
        paths.insert(folder.path)
        lock.unlock()
      } catch {
        lock.lock()
        failures.append(error.localizedDescription)
        lock.unlock()
      }
    }
    try check(failures.isEmpty && paths.count == 20, "동시 폴더 20개를 고유 이름으로 생성")
  }

  static func settingsAndPresetChecks(root: URL, nested: URL) throws {
    try AppSettings.defaults.validate()
    try check(
      AppSettings.defaults.presets.filter(\.isEnabled).map(\.fileExtension) == ["md", "txt"],
      "기본 활성 유형 보존")
    let template = "# 한글 제목\n\n- 첫 항목 📄\n"
    var preset = FilePreset(
      id: "custom", name: "수업 기록", fileExtension: "md", basename: "수업", template: template,
      isEnabled: true)
    let created = try NoteFiles.create(in: root, preset: preset)
    try check(String(contentsOf: created, encoding: .utf8) == template, "UTF-8 템플릿 바이트 보존")
    let duplicate = try NoteFiles.create(in: root, preset: preset)
    try check(
      duplicate.lastPathComponent == "수업 2.md"
        && String(contentsOf: created, encoding: .utf8) == template, "템플릿 중복 번호와 원본 보존")
    preset.basename = ".env"
    preset.fileExtension = ""
    let dotfile = try NoteFiles.create(in: root, preset: preset)
    let dotduplicate = try NoteFiles.create(in: root, preset: preset)
    try check(
      dotfile.lastPathComponent == ".env" && dotduplicate.lastPathComponent == ".env 2",
      "점 파일과 중복 번호")
    for ext in [".md", "../txt", "a/b", "a:b", "a\nb", "a..b", "md."] {
      var invalid = preset
      invalid.fileExtension = ext
      try rejects({ try invalid.validate() }, "잘못된 확장자 거부")
    }
    for name in ["../escape", "..", ".", "", " a ", "a\tb", String(repeating: "한", count: 80)] {
      var invalid = preset
      invalid.basename = name
      try rejects({ _ = try NoteFiles.create(in: root, preset: invalid) }, "잘못된 기본 이름 거부")
    }
    var invalid = preset
    invalid.template = String(repeating: "x", count: 262_145)
    try rejects({ try invalid.validate() }, "큰 템플릿 거부")
    for control in [0, 1, 8, 11, 12, 31] {
      invalid.template = "a" + String(UnicodeScalar(control)!) + "b"
      try rejects({ try invalid.validate() }, "바이너리 제어문자 템플릿 거부")
    }
    invalid.template = "정상\t탭\r\n줄바꿈"
    try invalid.validate()
    var longName = preset
    longName.basename = String(repeating: "한", count: 25)
    longName.fileExtension = "md"
    let longFirst = try NoteFiles.create(in: root, preset: longName)
    let longSecond = try NoteFiles.create(in: root, preset: longName)
    try check(
      longFirst.lastPathComponent.utf8.count <= 255
        && longSecond.lastPathComponent.utf8.count <= 255,
      "한글 최대 길이 이름도 중복 번호 포함 255바이트 이하")
    var settings = AppSettings(presets: [preset], useSubmenu: true, folderBasename: "수업 자료")
    let domain = "kr.techkwon.NewMemo.Tests.\(UUID().uuidString)"
    defer {
      for (key, targetDomain) in [
        (SettingsStore.key, domain), (SettingsStore.menuKey, SettingsStore.menuDomain(for: domain)),
      ] {
        CFPreferencesSetValue(
          key as CFString, nil, targetDomain as CFString, kCFPreferencesCurrentUser,
          kCFPreferencesAnyHost)
        _ = CFPreferencesSynchronize(
          targetDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      }
    }
    try check(SettingsStore.load(domain: domain) == .defaults, "설정 없으면 기본값")
    var legacy =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
      as! [String: Any]
    legacy.removeValue(forKey: "folderBasename")
    legacy["revealAfterCreation"] = false
    CFPreferencesSetValue(
      SettingsStore.key as CFString,
      try JSONSerialization.data(withJSONObject: legacy) as CFData,
      domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    _ = CFPreferencesSynchronize(
      domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    let migrated = SettingsStore.load(domain: domain)
    try check(migrated.folderBasename == "새 폴더", "이전 설정은 기본 폴더 이름 보충")
    try check(
      migrated.presets == settings.presets && migrated.useSubmenu == settings.useSubmenu,
      "이전 자동 열기 설정과 관계없이 사용자 파일 이름·템플릿 보존")
    try SettingsStore.save(settings, domain: domain)
    try check(SettingsStore.load(domain: domain) == settings, "템플릿과 메뉴 설정 저장 왕복")
    let customFolder = try NoteFiles.createFolder(
      in: root, basename: SettingsStore.load(domain: domain).folderBasename)
    try check(customFolder.lastPathComponent == "수업 자료", "저장한 기본 폴더 이름으로 생성")
    let customFolder2 = try NoteFiles.createFolder(
      in: root, basename: SettingsStore.load(domain: domain).folderBasename)
    try check(customFolder2.lastPathComponent == "수업 자료 2", "사용자 기본 폴더 이름 충돌 번호")
    for name in ["", "../escape", "줄\n바꿈", "앞뒤 ", String(repeating: "한", count: 100)] {
      var invalidFolder = settings
      invalidFolder.folderBasename = name
      try rejects({ try SettingsStore.save(invalidFolder, domain: domain) }, "잘못된 기본 폴더 이름 거부")
      try check(SettingsStore.load(domain: domain) == settings, "잘못된 폴더 이름은 기존 설정 보존")
    }
    let encoded = String(data: try JSONEncoder().encode(settings), encoding: .utf8)!
    try check(!encoded.contains("revealAfterCreation"), "삭제한 자동 열기 설정은 다시 저장하지 않음")
    settings.presets.append(preset)
    try rejects({ try SettingsStore.save(settings, domain: domain) }, "중복 식별자 거부")
    try check(SettingsStore.load(domain: domain).presets.count == 1, "잘못된 설정 저장 시 기존 설정 보존")
    settings.presets = (0..<65).map { index in
      var entry = preset
      entry.id = "preset-\(index)"
      return entry
    }
    try rejects({ try settings.validate() }, "유형 수 제한")
    CFPreferencesSetValue(
      SettingsStore.key as CFString, Data("corrupted".utf8) as CFData, domain as CFString,
      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    _ = CFPreferencesSynchronize(
      domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    try check(SettingsStore.load(domain: domain) == .defaults, "손상된 설정 안전 복구")
    let request = PresetCreateRequest(directory: nested, presetID: "custom-123")
    let decoded = try PresetCreateRequest(url: request.url)
    try check(
      decoded.directory.path == nested.path && decoded.presetID == request.presetID,
      "사용자 유형 요청 URL 왕복")
    for raw in [
      "newmemo://create?directory=/tmp&preset=", "newmemo://create?directory=/tmp&preset=../x",
      "newmemo://create?directory=relative&preset=x",
      "newmemo://create?directory=/tmp&preset=x&preset=y",
      "newmemo://create?directory=/tmp&preset=x&type=md",
      "newmemo://create/path?directory=/tmp&preset=x",
      "newmemo://user@create?directory=/tmp&preset=x",
      "newmemo://create?directory=/tmp&preset=x#extra",
      "newmemo://create?directory=/tmp&preset=x&template=evil",
    ] {
      try rejects({ _ = try PresetCreateRequest(url: URL(string: raw)!) }, "유형 요청 경계 검증")
    }
    preset.basename = "동시 템플릿"
    preset.fileExtension = "json"
    preset.template = String(repeating: "한글\n", count: 12_000)
    let concurrentPreset = preset
    let lock = NSLock()
    var contentsCorrect = true
    var paths = Set<String>()
    DispatchQueue.concurrentPerform(iterations: 20) { _ in
      do {
        let url = try NoteFiles.create(in: nested, preset: concurrentPreset)
        let data = try Data(contentsOf: url)
        lock.lock()
        paths.insert(url.path)
        contentsCorrect = contentsCorrect && data == Data(concurrentPreset.template.utf8)
        lock.unlock()
      } catch {
        lock.lock()
        contentsCorrect = false
        lock.unlock()
      }
    }
    try check(contentsCorrect && paths.count == 20, "동시 생성 템플릿 20개 완전 쓰기")
    let scriptPreset = AppSettings.defaults.presets.first { $0.id == "shell" }!
    let script = try NoteFiles.create(in: root, preset: scriptPreset)
    let permissions =
      try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? NSNumber
    try check((permissions?.intValue ?? 0) & 0o111 == 0, "스크립트를 실행 권한 없이 생성")
  }

  static func menuManifestChecks() throws {
    let domain = "kr.techkwon.NewMemo.MenuTests.\(UUID().uuidString)"
    let menuDomain = SettingsStore.menuDomain(for: domain)
    func setMenu(_ data: Data?) {
      CFPreferencesSetValue(
        SettingsStore.menuKey as CFString, data as CFData?, menuDomain as CFString,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      _ = CFPreferencesSynchronize(
        menuDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    defer {
      for (key, targetDomain) in [
        (SettingsStore.key, domain), (SettingsStore.menuKey, SettingsStore.menuDomain(for: domain)),
      ] {
        CFPreferencesSetValue(
          key as CFString, nil, targetDomain as CFString, kCFPreferencesCurrentUser,
          kCFPreferencesAnyHost)
        _ = CFPreferencesSynchronize(
          targetDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      }
    }
    try check(SettingsStore.loadMenu(domain: domain) == .defaults, "메뉴 메타데이터 없으면 기본 메뉴")
    var settings = AppSettings.defaults
    let template = "private-template-marker-" + String(repeating: "x", count: 260_000)
    settings.presets[0].template = template
    settings.presets[0].name = "사용자 Markdown"
    settings.useSubmenu = true
    settings.folderBasename = "private-folder-marker"
    try SettingsStore.save(settings, domain: domain)
    let fullData =
      CFPreferencesCopyValue(
        SettingsStore.key as CFString, domain as CFString,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as! Data
    let menuData =
      CFPreferencesCopyValue(
        SettingsStore.menuKey as CFString, menuDomain as CFString,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as! Data
    try check(fullData.count > 260_000 && menuData.count < 16_384, "큰 템플릿과 별개로 메뉴 JSON은 16KB 미만")
    let menuKeys =
      CFPreferencesCopyKeyList(
        menuDomain as CFString,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]
    try check(menuKeys == [SettingsStore.menuKey], "Finder 전용 preference 도메인에는 메뉴 key만 저장")
    try check(
      CFPreferencesCopyValue(
        SettingsStore.key as CFString, menuDomain as CFString,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) == nil,
      "Finder 전용 preference 도메인에 전체 템플릿 설정 없음")
    try check(
      CFPreferencesCopyValue(
        SettingsStore.menuKey as CFString, domain as CFString,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost) == nil,
      "새 메뉴 메타데이터는 호스트 설정 도메인에 저장하지 않음")
    let manifest = String(data: menuData, encoding: .utf8)!
    try check(
      !manifest.contains("private-template-marker") && !manifest.contains("template")
        && !manifest.contains("basename") && !manifest.contains("fileExtension")
        && !manifest.contains("folderBasename") && !manifest.contains("private-folder-marker"),
      "메뉴 데이터는 템플릿과 파일·폴더 생성 데이터 제외")
    try check(
      SettingsStore.loadMenu(domain: domain) == MenuSettings(settings: settings), "메뉴 메타데이터 왕복")
    settings.presets.reverse()
    settings.presets[0].isEnabled.toggle()
    settings.presets[0].name = "변경한 이름"
    settings.useSubmenu = false
    try SettingsStore.save(settings, domain: domain)
    try check(
      SettingsStore.loadMenu(domain: domain) == MenuSettings(settings: settings),
      "설정 변경 시 순서 이름 활성화 메뉴 모드 즉시 갱신")
    setMenu(nil)
    try check(
      SettingsStore.loadMenu(domain: domain) == .defaults, "기존 전체 설정이 있어도 Finder는 큰 설정을 읽지 않음")
    try SettingsStore.publishMenu(domain: domain)
    try check(
      SettingsStore.loadMenu(domain: domain) == MenuSettings(settings: settings),
      "호스트 시작 시 기존 사용자 설정 메뉴 마이그레이션")
    setMenu(Data("broken-json".utf8))
    try check(SettingsStore.loadMenu(domain: domain) == .defaults, "손상된 메뉴 데이터 기본값 복구")
    setMenu(Data(repeating: 32, count: 32_769))
    try check(SettingsStore.loadMenu(domain: domain) == .defaults, "메뉴 데이터 읽기 용량 제한")
    var invalidMenu = MenuSettings(settings: settings)
    invalidMenu.presets.append(invalidMenu.presets[0])
    setMenu(try JSONEncoder().encode(invalidMenu))
    try check(SettingsStore.loadMenu(domain: domain) == .defaults, "중복 메뉴 식별자 거부")
    invalidMenu = MenuSettings(settings: settings)
    invalidMenu.presets[0].id = "../escape"
    setMenu(try JSONEncoder().encode(invalidMenu))
    try check(SettingsStore.loadMenu(domain: domain) == .defaults, "잘못된 메뉴 식별자 거부")
    invalidMenu = MenuSettings(settings: settings)
    invalidMenu.presets[0].name = "줄\n바꿈"
    setMenu(try JSONEncoder().encode(invalidMenu))
    try check(SettingsStore.loadMenu(domain: domain) == .defaults, "잘못된 메뉴 이름 거부")
    try check(SettingsStore.load(domain: domain) == settings, "메뉴 손상 복구가 전체 사용자 설정은 보존")
    invalidMenu.presets = (0..<65).map {
      FileMenuPreset(id: "preset-\($0)", name: "형식", isEnabled: true)
    }
    setMenu(try JSONEncoder().encode(invalidMenu))
    try check(SettingsStore.loadMenu(domain: domain) == .defaults, "메뉴 형식 64개 제한")
    let empty = AppSettings(presets: [], useSubmenu: true)
    try SettingsStore.save(empty, domain: domain)
    try check(
      SettingsStore.loadMenu(domain: domain) == MenuSettings(settings: empty), "빈 활성 유형 목록 유지")
    let preservedMenu = try JSONEncoder().encode(MenuSettings(settings: settings))
    setMenu(preservedMenu)
    CFPreferencesSetValue(
      SettingsStore.key as CFString, Data("broken-full-settings".utf8) as CFData,
      domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    _ = CFPreferencesSynchronize(
      domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    try SettingsStore.publishMenu(domain: domain)
    try check(
      SettingsStore.loadMenu(domain: domain) == MenuSettings(settings: settings),
      "정상 메뉴가 있으면 앱 시작 시 전체 설정을 읽어 덮어쓰지 않음")
    CFPreferencesSetValue(
      SettingsStore.key as CFString, Data(repeating: 32, count: 18_000_001) as CFData,
      domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    _ = CFPreferencesSynchronize(
      domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    try SettingsStore.publishMenu(domain: domain)
    try check(
      SettingsStore.loadMenu(domain: domain) == MenuSettings(settings: settings),
      "전체 설정이 크기 제한을 넘어도 정상 메뉴는 마이그레이션 생략")
    setMenu(try JSONEncoder().encode(MenuSettings(settings: empty)))
    try SettingsStore.publishMenu(domain: domain)
    try check(
      SettingsStore.loadMenu(domain: domain) == MenuSettings(settings: empty),
      "빈 메뉴도 유효한 메타데이터이므로 전체 설정 조회 생략")
  }

}
