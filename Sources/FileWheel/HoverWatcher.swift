import AppKit
import ApplicationServices

final class HoverWatcher {
    var enabled = true
    var isWheelVisible: () -> Bool = { false }
    var onFile: (URL, NSPoint) -> Void = { _, _ in }
    private var timer: Timer?
    private var lastPoint = NSPoint.zero
    private var stableSince = Date()
    private var checked = false
    private var suppressedPoint: NSPoint?
    private let system = AXUIElementCreateSystemWide()

    func start() {
        AXUIElementSetMessagingTimeout(system, 0.15)
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
    }

    func suppressUntilMoved() { suppressedPoint = NSEvent.mouseLocation }

    private func tick() {
        let point = NSEvent.mouseLocation
        if let suppressedPoint, hypot(point.x - suppressedPoint.x, point.y - suppressedPoint.y) > 60 { self.suppressedPoint = nil }
        if hypot(point.x - lastPoint.x, point.y - lastPoint.y) > 3 {
            lastPoint = point; stableSince = Date(); checked = false
        }
        guard enabled, !checked, suppressedPoint == nil, !isWheelVisible(),
              NSEvent.pressedMouseButtons == 0,
              Date().timeIntervalSince(stableSince) >= 0.7, AXIsProcessTrusted() else { return }
        checked = true
        guard let screen = NSScreen.screens.first else { return }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(screen.frame.maxY - point.y), &hit) == .success,
              let hit else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(hit, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder" else { return }
        if let file = FinderFileResolver.resolve(hit), FileKind.identify(file) != nil {
            suppressedPoint = point
            onFile(file, point)
        }
    }
}

enum FinderFileResolver {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func fileURL(_ value: CFTypeRef?) -> URL? {
        if let url = value as? URL, url.isFileURL { return url }
        if let string = value as? String, let url = URL(string: string), url.isFileURL { return url }
        return nil
    }

    static func regularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    static func resolve(_ hit: AXUIElement) -> URL? {
        var current = hit
        var names: [String] = []
        var fileElementFound = false
        var containingFolder: URL?
        var reachedWindow = false
        for _ in 0..<12 {
            let role = attribute(current, kAXRoleAttribute) as? String ?? ""
            if role == kAXWindowRole {
                reachedWindow = true
                containingFolder = fileURL(attribute(current, kAXDocumentAttribute))
                break
            }
            if let url = fileURL(attribute(current, kAXURLAttribute)), regularFile(url) { return url }
            if [kAXImageRole, kAXRowRole, kAXCellRole, kAXStaticTextRole, kAXTextFieldRole].contains(role) {
                fileElementFound = true
                collectNames(current, depth: 0, into: &names)
            }
            guard let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
        guard fileElementFound else { return nil }
        // Finder exposes AXURL on many items. For older views, use the exact item name in its AXDocument folder.
        if let folder = containingFolder {
            return match(names: names, folder: folder)
        }
        // Never guess a desktop path for an ordinary Finder window with no usable folder URL.
        guard !reachedWindow else { return nil }
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return nil }
        return match(names: names, folder: desktop)
    }

    private static func collectNames(_ element: AXUIElement, depth: Int, into names: inout [String]) {
        for key in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute] {
            if let text = attribute(element, key) as? String, !text.isEmpty, !text.contains("/"), !names.contains(text) { names.append(text) }
        }
        if depth < 2, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            for child in children.prefix(16) { collectNames(child, depth: depth + 1, into: &names) }
        }
    }

    static func match(names: [String], folder: URL) -> URL? {
        guard folder.isFileURL, (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        var exact: [URL] = []
        for name in names where name != "." && name != ".." && !name.contains("/") {
            let file = folder.appendingPathComponent(name)
            if regularFile(file), FileKind.identify(file) != nil { exact.append(file) }
        }
        let unique = Set(exact)
        if unique.count == 1 { return unique.first }
        if unique.count > 1 { return nil }
        // Finder can hide extensions. Refuse ambiguous basenames instead of choosing the wrong file.
        guard let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        let matches = contents.filter { names.contains($0.deletingPathExtension().lastPathComponent) && regularFile($0) && FileKind.identify($0) != nil }
        return matches.count == 1 ? matches[0] : nil
    }
}
