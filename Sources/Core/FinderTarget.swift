import Foundation

enum FinderMenuContext: CaseIterable {
  case items, sidebar, background, toolbar
}

/// A short-lived snapshot of Finder's destination and selection for one menu.
struct FinderTarget {
  let creationDirectory: URL?
  let selectedPaths: [URL]

  init(context: FinderMenuContext, target: URL?, selection: [URL]) {
    var candidate = target
    if context == .items || context == .sidebar {
      if selection.count > 1 {
        candidate = nil
      } else if let selected = selection.first ?? target {
        let values = try? selected.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        // Finder presents app bundles and document packages as files. Creating inside
        // one can invalidate its signature or corrupt the document's structure.
        let folder = values?.isDirectory == true && values?.isPackage != true
        candidate = folder ? selected : selected.deletingLastPathComponent()
      }
      selectedPaths = selection.isEmpty ? target.map { [$0] } ?? [] : selection
    } else {
      selectedPaths = context == .toolbar ? selection : []
    }
    creationDirectory = candidate
  }
}
