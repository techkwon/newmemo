import AppKit

/// A local, text-only Markdown preview. URLs become attributes; no resources are fetched.
enum MarkdownRenderer {
  private static let bodyFont = NSFont.systemFont(ofSize: 14)
  private static let bodyParagraph: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 3
    style.paragraphSpacing = 3
    return style.copy() as! NSParagraphStyle
  }()
  private static let bodyAttributes: [NSAttributedString.Key: Any] = [
    .font: bodyFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: bodyParagraph,
  ]
  private static let parsingOptions = AttributedString.MarkdownParsingOptions(
    interpretedSyntax: .inlineOnlyPreservingWhitespace,
    failurePolicy: .returnPartiallyParsedIfPossible)

  static func render(_ source: String) -> NSAttributedString {
    let output = NSMutableAttributedString(string: "")
    let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.components(separatedBy: "\n")
    var index = 0
    var fence: (marker: Character, count: Int)?
    var plainBuffer = ""
    func flushPlainText() {
      guard !plainBuffer.isEmpty else { return }
      output.append(NSAttributedString(string: plainBuffer, attributes: bodyAttributes))
      plainBuffer.removeAll(keepingCapacity: true)
    }
    while index < lines.count {
      let line = lines[index]
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let newline = index < lines.count - 1 ? "\n" : ""
      if let activeFence = fence {
        if let closing = fenceMarker(trimmed), closing.marker == activeFence.marker,
          closing.count >= activeFence.count,
          trimmed.dropFirst(closing.count).trimmingCharacters(in: .whitespaces).isEmpty
        {
          fence = nil
        } else {
          output.append(NSAttributedString(string: line + newline, attributes: codeAttributes))
        }
        index += 1
        continue
      }
      if isPlainBlockLine(line, trimmed: trimmed) {
        plainBuffer.append(contentsOf: line)
        plainBuffer.append(contentsOf: newline)
        index += 1
        continue
      }
      flushPlainText()
      if let opening = fenceMarker(trimmed) {
        fence = opening
        index += 1
        continue
      }
      if index + 1 < lines.count, let header = pipeCells(line),
        let separator = pipeCells(lines[index + 1]), header.count == separator.count,
        separator.allSatisfy(isTableSeparator)
      {
        appendTableRow(header, header: true, newline: "\n", to: output)
        index += 2
        while index < lines.count, let cells = pipeCells(lines[index]), cells.count == header.count
        {
          appendTableRow(
            cells, header: false, newline: index < lines.count - 1 ? "\n" : "", to: output)
          index += 1
        }
        continue
      }
      if let heading = heading(trimmed) {
        let sizes: [CGFloat] = [28, 24, 21, 18, 16, 15]
        let paragraph = paragraphStyle()
        paragraph.paragraphSpacingBefore = 8
        paragraph.paragraphSpacing = 6
        output.append(
          inline(
            heading.text + newline,
            font: .systemFont(ofSize: sizes[heading.level - 1], weight: .bold), paragraph: paragraph
          ))
      } else if isHorizontalRule(trimmed) {
        output.append(
          NSAttributedString(
            string: "────────────────────────" + newline,
            attributes: [
              .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.separatorColor,
              .paragraphStyle: bodyParagraph,
            ]))
      } else if trimmed.hasPrefix(">") {
        var quoted = trimmed.dropFirst()
        if quoted.first == " " { quoted = quoted.dropFirst() }
        let paragraph = paragraphStyle()
        paragraph.headIndent = 18
        paragraph.firstLineHeadIndent = 8
        output.append(
          inline("│ " + quoted + newline, paragraph: paragraph, color: .secondaryLabelColor))
      } else if let list = listItem(line) {
        let paragraph = paragraphStyle()
        paragraph.firstLineHeadIndent = CGFloat(list.indent) * 8
        paragraph.headIndent = paragraph.firstLineHeadIndent + 22
        output.append(inline(list.marker + list.text + newline, paragraph: paragraph))
      } else {
        output.append(inline(line + newline))
      }
      index += 1
    }
    flushPlainText()
    return output
  }

  private static func inline(
    _ source: String, font: NSFont = bodyFont,
    paragraph: NSParagraphStyle = bodyParagraph, color: NSColor = .labelColor
  ) -> NSAttributedString {
    guard !hasNoInlineSyntax(source),
      let parsed = try? AttributedString(markdown: source, options: parsingOptions)
    else {
      return NSAttributedString(
        string: source,
        attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    let result = NSMutableAttributedString(string: "")
    for run in parsed.runs {
      var text = String(parsed[run.range].characters)
      var attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
      ]
      var runFont = font
      if let intent = run.inlinePresentationIntent {
        if intent.contains(.code) {
          runFont = .monospacedSystemFont(ofSize: max(11, font.pointSize - 1), weight: .regular)
          attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
        }
        if intent.contains(.stronglyEmphasized) {
          runFont = fontWithTrait(.bold, base: runFont)
        }
        if intent.contains(.emphasized) {
          runFont = fontWithTrait(.italic, base: runFont)
        }
        if intent.contains(.strikethrough) {
          attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
      }
      attributes[.font] = runFont
      if run.imageURL != nil {
        text = "[이미지: \(text.isEmpty ? "설명 없음" : text)]"
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
      } else if let url = run.link, isAllowedLink(url) {
        attributes[.link] = url
        attributes[.foregroundColor] = NSColor.linkColor
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
      }
      result.append(NSAttributedString(string: text, attributes: attributes))
    }
    return result
  }

  private static func fontWithTrait(_ trait: NSFontDescriptor.SymbolicTraits, base: NSFont)
    -> NSFont
  {
    let descriptor = base.fontDescriptor.withSymbolicTraits(
      base.fontDescriptor.symbolicTraits.union(trait))
    return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
  }

  private static func hasNoInlineSyntax(_ source: String) -> Bool {
    !source.utf8.contains {
      switch $0 {
      case 33, 38, 42, 60, 91, 92, 95, 96, 126: return true
      default: return false
      }
    }
  }

  private static func isPlainBlockLine(_ line: String, trimmed: String) -> Bool {
    guard hasNoInlineSyntax(line), !line.contains("|") else { return false }
    guard let first = trimmed.first else { return true }
    if ["#", ">", "-", "+"].contains(first) { return false }
    return !(first.isASCII && first.isNumber)
  }

  private static func isAllowedLink(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme),
      let decoded = url.absoluteString.removingPercentEncoding,
      decoded.rangeOfCharacter(from: .controlCharacters) == nil
    else { return false }
    return scheme == "mailto" ? url.absoluteString.count > 7 : !(url.host ?? "").isEmpty
  }

  private static func paragraphStyle() -> NSMutableParagraphStyle {
    bodyParagraph.mutableCopy() as! NSMutableParagraphStyle
  }

  private static let codeAttributes: [NSAttributedString.Key: Any] = {
    let paragraph = paragraphStyle()
    paragraph.paragraphSpacing = 0
    paragraph.firstLineHeadIndent = 10
    paragraph.headIndent = 10
    return [
      .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
      .foregroundColor: NSColor.labelColor,
      .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
      .paragraphStyle: paragraph.copy() as! NSParagraphStyle,
    ]
  }()

  private static func fenceMarker(_ line: String) -> (marker: Character, count: Int)? {
    guard let first = line.first, first == "`" || first == "~" else { return nil }
    let count = line.prefix(while: { $0 == first }).count
    return count >= 3 ? (first, count) : nil
  }

  private static func heading(_ line: String) -> (level: Int, text: String)? {
    let count = line.prefix(while: { $0 == "#" }).count
    guard (1...6).contains(count) else { return nil }
    let remaining = line.dropFirst(count)
    guard remaining.isEmpty || remaining.first == " " || remaining.first == "\t" else { return nil }
    return (count, remaining.trimmingCharacters(in: .whitespaces))
  }

  private static func isHorizontalRule(_ line: String) -> Bool {
    let compact = line.filter { !$0.isWhitespace }
    guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else {
      return false
    }
    return compact.allSatisfy { $0 == first }
  }

  private static func listItem(_ line: String) -> (indent: Int, marker: String, text: String)? {
    let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
    let content = line.dropFirst(leading.count)
    guard let first = content.first else { return nil }
    let indent = min(12, leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) })
    if ["-", "*", "+"].contains(first), content.dropFirst().first?.isWhitespace == true {
      var text = content.dropFirst().trimmingCharacters(in: .whitespaces)
      var marker = "• "
      if text.hasPrefix("[ ] ") {
        marker = "☐ "
        text = String(text.dropFirst(4))
      }
      if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
        marker = "☑ "
        text = String(text.dropFirst(4))
      }
      return (indent, marker, text)
    }
    let digits = content.prefix(while: { $0.isASCII && $0.isNumber })
    guard !digits.isEmpty, digits.count <= 9 else { return nil }
    let remainder = content.dropFirst(digits.count)
    guard remainder.first == "." || remainder.first == ")",
      remainder.dropFirst().first?.isWhitespace == true
    else { return nil }
    return (indent, "\(digits). ", remainder.dropFirst().trimmingCharacters(in: .whitespaces))
  }

  /// Basic pipe tables only: escaped pipes are preserved, and cells are rendered as tabbed text.
  private static func pipeCells(_ line: String) -> [String]? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.contains("|") else { return nil }
    var cells: [String] = []
    var cell = ""
    var escaped = false
    for character in trimmed {
      if escaped {
        if character != "|" { cell.append("\\") }
        cell.append(character)
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "|" {
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        cell = ""
        if cells.count > 17 { return nil }
      } else {
        cell.append(character)
      }
    }
    if escaped { cell.append("\\") }
    cells.append(cell.trimmingCharacters(in: .whitespaces))
    if trimmed.hasPrefix("|") { cells.removeFirst() }
    if trimmed.hasSuffix("|"), cells.last?.isEmpty == true { cells.removeLast() }
    return (2...16).contains(cells.count) ? cells : nil
  }

  private static func isTableSeparator(_ cell: String) -> Bool {
    let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
  }

  private static func appendTableRow(
    _ cells: [String], header: Bool, newline: String, to output: NSMutableAttributedString
  ) {
    let paragraph = paragraphStyle()
    paragraph.tabStops = (1..<cells.count).map {
      NSTextTab(textAlignment: .left, location: CGFloat($0) * 150)
    }
    paragraph.defaultTabInterval = 150
    let row = inline(
      cells.joined(separator: "\t") + newline,
      font: .systemFont(ofSize: 13, weight: header ? .bold : .regular), paragraph: paragraph)
    output.append(row)
  }
}
