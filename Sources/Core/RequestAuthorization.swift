import CoreFoundation
import Foundation

/// A local capability prevents websites from invoking mutating Finder actions by guessing a URL.
/// It is not an isolation boundary against applications running as the same macOS user.
enum RequestAuthorization {
  static let key = "finderRequestAuthorization.v1"
  private static let queryKey = "auth"
  private static let maximumURLBytes = 65_606

  static func prepare(domain: String = SettingsStore.domain) throws {
    if try readToken(domain: domain) != nil { return }
    let token = (UUID().uuidString + UUID().uuidString)
      .replacingOccurrences(of: "-", with: "").lowercased()
    let application = SettingsStore.menuDomain(for: domain) as CFString
    CFPreferencesSetValue(
      key as CFString, token as CFString, application,
      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    guard CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
      try readToken(domain: domain) == token
    else { throw RequestAuthorizationError.unavailable }
  }

  static func authorize(_ url: URL, domain: String = SettingsStore.domain) throws -> URL {
    if url.absoluteString == "newmemo://settings" { return url }
    guard isRequest(url), let token = try readToken(domain: domain),
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { throw RequestAuthorizationError.unavailable }
    parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: queryKey, value: token)]
    guard let authorized = parts.url, authorized.absoluteString.utf8.count <= maximumURLBytes else {
      throw NoteError.invalidRequest
    }
    return authorized
  }

  static func verify(_ url: URL, domain: String = SettingsStore.domain) throws -> URL {
    if url.absoluteString == "newmemo://settings" { return url }
    guard url.absoluteString.utf8.count <= maximumURLBytes,
      var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let items = parts.queryItems,
      items.filter({ $0.name == queryKey }).count == 1,
      let supplied = items.first(where: { $0.name == queryKey })?.value,
      let expected = try readToken(domain: domain), supplied == expected
    else { throw RequestAuthorizationError.unauthorized }
    parts.queryItems = items.filter { $0.name != queryKey }
    guard let request = parts.url, isRequest(request) else { throw NoteError.invalidRequest }
    return request
  }

  private static func readToken(domain: String) throws -> String? {
    let application = SettingsStore.menuDomain(for: domain) as CFString
    guard CFPreferencesSynchronize(application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    else { throw RequestAuthorizationError.unavailable }
    guard
      let token = CFPreferencesCopyValue(
        key as CFString, application, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String,
      token.utf8.count == 64,
      token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { return nil }
    return token
  }

  private static func isRequest(_ url: URL) -> Bool {
    (try? UtilityRequest(url: url)) != nil || (try? FolderCreateRequest(url: url)) != nil
      || (try? PresetCreateRequest(url: url)) != nil || (try? CreateRequest(url: url)) != nil
  }
}

enum RequestAuthorizationError: LocalizedError {
  case unavailable, unauthorized

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Finder 요청을 준비하지 못했습니다. 새 메모 앱을 한 번 연 뒤 Finder 메뉴를 다시 사용해 주세요."
    case .unauthorized:
      return "인증되지 않은 요청을 실행하지 않았습니다. Finder의 새 메모 메뉴를 사용해 주세요."
    }
  }
}
