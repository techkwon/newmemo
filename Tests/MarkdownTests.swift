import AppKit

@main
enum MarkdownTests {
  private static var checks = 0

  private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    checks += 1
    guard condition() else {
      throw NSError(
        domain: "MarkdownTests", code: checks, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }

  private static func attribute(
    _ key: NSAttributedString.Key, at text: String, in rendered: NSAttributedString
  ) -> Any? {
    let range = (rendered.string as NSString).range(of: text)
    guard range.location != NSNotFound else { return nil }
    return rendered.attribute(key, at: range.location, effectiveRange: nil)
  }

  private static func font(_ text: String, in rendered: NSAttributedString) -> NSFont {
    attribute(.font, at: text, in: rendered) as? NSFont ?? .systemFont(ofSize: 1)
  }

  static func main() throws {
    _ = NSApplication.shared
    let headings = MarkdownRenderer.render(
      "# 제목1\n## 제목2\n### 제목3\n#### 제목4\n##### 제목5\n###### 제목6")
    try check(!headings.string.contains("#"), "제목 기호 제거")
    for level in 1...6 {
      let current = font("제목\(level)", in: headings)
      try check(
        NSFontManager.shared.traits(of: current).contains(.boldFontMask), "제목 \(level) 굵게 표시")
      if level < 6 {
        try check(
          current.pointSize > font("제목\(level + 1)", in: headings).pointSize, "제목 단계별 글자 크기")
      }
    }
    let inline = MarkdownRenderer.render("**굵게** *기울임* ~~취소~~ `코드` **복합 *강조***")
    try check(inline.string == "굵게 기울임 취소 코드 복합 강조", "인라인 문법과 중첩 강조 해석")
    try check(
      NSFontManager.shared.traits(of: font("굵게", in: inline)).contains(.boldFontMask), "굵게 글꼴")
    try check(
      NSFontManager.shared.traits(of: font("기울임", in: inline)).contains(.italicFontMask), "기울임 글꼴")
    try check(
      (attribute(.strikethroughStyle, at: "취소", in: inline) as? Int)
        == NSUnderlineStyle.single.rawValue, "취소선 속성")
    try check(font("코드", in: inline).isFixedPitch, "인라인 코드 고정폭 글꼴")
    try check(attribute(.backgroundColor, at: "코드", in: inline) != nil, "인라인 코드 배경")

    let links = MarkdownRenderer.render(
      "[웹](https://example.com) [HTTP](http://example.com) [메일](mailto:teacher@example.com) [파일](file:///tmp/private) [스크립트](javascript:alert%281%29) [커스텀](newmemo://create) [데이터](data:text/plain,test) [상대](../secret) [제어](https://example.com/%0aevil)"
    )
    for text in ["웹", "HTTP", "메일"] {
      try check(attribute(.link, at: text, in: links) is URL, "허용 링크 \(text)")
    }
    for text in ["파일", "스크립트", "커스텀", "데이터", "상대", "제어"] {
      try check(attribute(.link, at: text, in: links) == nil, "위험하거나 상대적인 링크 비활성화 \(text)")
    }
    let image = MarkdownRenderer.render("![사진 설명](https://invalid.test/private.png)")
    try check(image.string.contains("사진 설명") && image.string.contains("이미지"), "이미지는 설명만 표시")
    try check(attribute(.attachment, at: "사진 설명", in: image) == nil, "외부 이미지 첨부 미생성")
    try check(attribute(.link, at: "사진 설명", in: image) == nil, "이미지 URL 비활성화")
    let html = "<script>alert('실행 안 됨')</script> <b>태그</b>"
    try check(MarkdownRenderer.render(html).string == html, "HTML 태그는 실행 없이 원문 표시")

    let code = MarkdownRenderer.render(
      "```swift\n# 코드 제목\n**원문** [링크](https://example.com)\n```\n문단")
    try check(code.string == "# 코드 제목\n**원문** [링크](https://example.com)\n문단", "코드 울타리 내부 원문 보존")
    try check(font("코드 제목", in: code).isFixedPitch, "블록 코드 고정폭")
    try check(attribute(.link, at: "링크", in: code) == nil, "코드 블록에서 링크 해석 안 함")
    try check(
      MarkdownRenderer.render("~~~~\n```\n원문\n~~~\n계속\n~~~~").string == "```\n원문\n~~~\n계속\n",
      "종류와 길이가 맞는 울타리만 종료")
    try check(
      MarkdownRenderer.render("```\n닫히지 않은 **코드**").string == "닫히지 않은 **코드**", "미완성 코드 울타리도 원문 보존")

    let list = MarkdownRenderer.render("- 항목\n  + 하위\n12) 번호\n- [ ] 할 일\n- [x] 완료\n> 인용")
    try check(list.string == "• 항목\n• 하위\n12. 번호\n☐ 할 일\n☑ 완료\n│ 인용", "목록, 작업 상태, 인용 표시")
    let nestedParagraph = attribute(.paragraphStyle, at: "하위", in: list) as? NSParagraphStyle
    try check((nestedParagraph?.firstLineHeadIndent ?? 0) > 0, "하위 목록 들여쓰기")
    try check(MarkdownRenderer.render("앞\n\n뒤\n").string == "앞\n\n뒤\n", "빈 줄과 마지막 줄바꿈 보존")
    try check(MarkdownRenderer.render("한글\r\n다음\r줄").string == "한글\n다음\n줄", "CRLF/CR 미리보기 줄바꿈")
    try check(MarkdownRenderer.render("").length == 0, "빈 문서")
    try check(MarkdownRenderer.render("앞\n---\n뒤").string.contains("─"), "가로 구분선")
    let table = MarkdownRenderer.render(
      "| **항목** | 값 |\n| :--- | ---: |\n| 사과 | 3 |\n| 파이프 \\| 포함 | 4 |")
    try check(table.string == "항목\t값\n사과\t3\n파이프 | 포함\t4", "간단 파이프 표와 이스케이프")
    try check(
      NSFontManager.shared.traits(of: font("항목", in: table)).contains(.boldFontMask), "표 머리글 강조")
    let tableParagraph = attribute(.paragraphStyle, at: "사과", in: table) as? NSParagraphStyle
    try check(tableParagraph?.tabStops.count == 1, "표 열을 네이티브 탭으로 구분")

    let large = String(repeating: "한글 plain 1234567890\n", count: 10_000)
    let start = Date()
    let largeRendered = MarkdownRenderer.render(large)
    try check(largeRendered.string == large, "큰 일반 문서 내용 보존")
    let punctuation = String(repeating: "*", count: 60_001) + " 내용"
    try check(MarkdownRenderer.render(punctuation).length > 0, "긴 미완성 문법도 종료")
    let blankLines = String(repeating: "\n", count: 100_000)
    let blankStart = Date()
    try check(MarkdownRenderer.render(blankLines).string == blankLines, "빈 줄 10만 개를 누락 없이 보존")
    let blankDuration = Date().timeIntervalSince(blankStart)
    let mixed = MarkdownRenderer.render("일반 문단\n# 큰 제목\n이어진 일반 문단\n```\n코드\n```\n마지막 문단")
    try check(mixed.string == "일반 문단\n큰 제목\n이어진 일반 문단\n코드\n마지막 문단", "일반 텍스트와 블록 경계 순서 보존")
    try check(
      font("마지막 문단", in: mixed).pointSize == font("일반 문단", in: mixed).pointSize,
      "제목과 코드 이후 일반 글꼴 복원")
    try check(attribute(.backgroundColor, at: "마지막 문단", in: mixed) == nil, "코드 배경이 다음 문단에 적용되지 않음")
    print(
      "PASS: \(checks) Markdown checks (large input \(large.utf8.count) bytes, \(String(format: "%.2f", Date().timeIntervalSince(start))) s; 100k blank lines \(String(format: "%.2f", blankDuration)) s)"
    )
  }
}
