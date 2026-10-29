import CoreFoundation
import Foundation

@main
enum RequestAuthorizationTests {
  static var checks = 0
  static func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    checks += 1
    guard try value() else {
      throw NSError(
        domain: "RequestAuthorizationTests", code: checks,
        userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  static func rejected(_ operation: () throws -> Any) -> Bool {
    do {
      _ = try operation()
      return false
    } catch { return true }
  }
  static func main() throws {
    let domain = "kr.techkwon.NewMemo.AuthorizationTests.\(UUID().uuidString)"
    let otherDomain = domain + ".other"
    defer {
      for name in [domain, otherDomain] {
        let application = SettingsStore.menuDomain(for: name) as CFString
        CFPreferencesSetValue(
          RequestAuthorization.key as CFString, nil, application,
          kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        _ = CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
      }
    }
    let folder = URL(fileURLWithPath: "/Users/Shared/한글 & ? %")
    let requests =
      [
        FolderCreateRequest(directory: folder).url,
        PresetCreateRequest(directory: folder, presetID: "md").url,
        CreateRequest(directory: folder, kind: .text).url,
      ] + UtilityAction.allCases.map { UtilityRequest(action: $0, paths: [folder]).url! }
    try check(
      rejected { try RequestAuthorization.authorize(requests[0], domain: domain) },
      "초기화 전 토큰 없는 Finder 요청 거부")
    try RequestAuthorization.prepare(domain: domain)
    try RequestAuthorization.prepare(domain: otherDomain)
    for request in requests {
      try check(
        rejected { try RequestAuthorization.verify(request, domain: domain) },
        "인증 없는 원래 URL 거부")
      let authorized = try RequestAuthorization.authorize(request, domain: domain)
      try check(
        try RequestAuthorization.verify(authorized, domain: domain) == request,
        "인증 봉투 후 엄격한 원래 요청 복원")
      try check(
        rejected { try RequestAuthorization.verify(authorized, domain: otherDomain) },
        "다른 사용자 범위 토큰 거부")
      var parts = URLComponents(url: authorized, resolvingAgainstBaseURL: false)!
      parts.queryItems!.append(URLQueryItem(name: "auth", value: "wrong"))
      try check(
        rejected { try RequestAuthorization.verify(parts.url!, domain: domain) },
        "중복 인증 키 거부")
      parts = URLComponents(url: authorized, resolvingAgainstBaseURL: false)!
      parts.queryItems = parts.queryItems!.map {
        $0.name == "auth" ? URLQueryItem(name: "auth", value: "wrong") : $0
      }
      try check(
        rejected { try RequestAuthorization.verify(parts.url!, domain: domain) },
        "틀린 인증 토큰 거부")
      parts = URLComponents(url: authorized, resolvingAgainstBaseURL: false)!
      parts.queryItems!.append(URLQueryItem(name: "unexpected", value: "1"))
      try check(
        rejected { try RequestAuthorization.verify(parts.url!, domain: domain) },
        "인증 후에도 원래 엄격한 알 수 없는 키 거부")
      try check(
        rejected { try RequestAuthorization.authorize(authorized, domain: domain) },
        "이미 인증된 URL 중복 포장 거부")
    }
    let before = try RequestAuthorization.authorize(requests[0], domain: domain)
    try RequestAuthorization.prepare(domain: domain)
    try check(
      try RequestAuthorization.verify(before, domain: domain) == requests[0],
      "앱 재시작 준비 시 기존 토큰 유지")
    let settings = URL(string: "newmemo://settings")!
    try check(
      try RequestAuthorization.authorize(settings, domain: domain) == settings,
      "읽기 전용 설정창 URL 유지")
    try check(
      try RequestAuthorization.verify(settings, domain: domain) == settings,
      "읽기 전용 설정창은 인증 없이 허용")
    for raw in [
      "file:///Users/Shared", "https://example.com", "newmemo://settings?path=/Users/Shared",
      "newmemo://utility?action=copyPaths&path=/Users/Shared&auth=",
      "newmemo://user@folder?path=/Users/Shared",
      "newmemo://folder?path=/Users/Shared#fragment",
      "newmemo://utility?action=copyPaths&path=/" + String(repeating: "a", count: 65_607),
    ] {
      let url = URL(string: raw)!
      try check(
        rejected { try RequestAuthorization.authorize(url, domain: domain) },
        "잘못된 URL 포장 거부")
      try check(
        rejected { try RequestAuthorization.verify(url, domain: domain) },
        "잘못된 URL 수신 거부")
    }
    print("PASS: \(checks) request authorization checks")
  }
}
