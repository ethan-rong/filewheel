import AppKit
import SwiftUI
import ApplicationServices

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem!
    private let watcher = HoverWatcher()
    private var panel: WheelPanel?
    private var model: WheelModel?
    private var job: ConversionJob?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var lastScroll = Date.distantPast
    private var pauseItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "FileWheel")
        status.button?.toolTip = "FileWheel · hover, choose, convert"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "FileWheel", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        add("Choose a file…", #selector(chooseFile), to: menu)
        add("Preview the wheel", #selector(preview), to: menu)
        add("Enable Finder hover…", #selector(enableHover), to: menu)
        pauseItem = add("Pause hovering", #selector(togglePause), to: menu)
        menu.addItem(.separator())
        add("View project & help", #selector(help), to: menu)
        add("Quit FileWheel", #selector(quit), to: menu, key: "q")
        status.menu = menu
        watcher.isWheelVisible = { [weak self] in self?.panel?.isVisible == true }
        watcher.onFile = { [weak self] url, point in self?.show(url, near: point) }
        watcher.start()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }
            if event.type == .scrollWheel {
                guard self.model?.busy == false, self.model?.message == nil, self.model?.result == nil else { return event }
                if abs(event.scrollingDeltaY) > 0.5, Date().timeIntervalSince(self.lastScroll) > 0.16 {
                    self.model?.step(event.scrollingDeltaY > 0 ? -1 : 1); self.lastScroll = Date()
                }
                return nil
            }
            if event.keyCode != 53, self.model?.busy == true || self.model?.message != nil || self.model?.result != nil { return event }
            switch event.keyCode {
            case 53: if self.model?.busy != true { self.dismiss() }; return nil
            case 48: self.model?.step(event.modifierFlags.contains(.shift) ? -1 : 1); return nil
            case 123, 126: self.model?.step(-1); return nil
            case 124, 125: self.model?.step(1); return nil
            case 36, 76: self.model?.choose(); return nil
            default: return event
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.model?.busy != true { self?.dismiss() }
        }
        if CommandLine.arguments.contains("--preview") { preview() }
        else if !AXIsProcessTrusted() { showWelcome() }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; menu.addItem(item); return item
    }

    @objc private func chooseFile() {
        guard model?.busy != true else { return }
        let chooser = NSOpenPanel()
        chooser.title = "Choose a file to convert"
        chooser.canChooseDirectories = false
        chooser.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if chooser.runModal() == .OK, let url = chooser.url {
            if Converter.formats(for: url).isEmpty { alert("This file type is not supported yet.", "Choose an image, document, PDF, audio file, or video.") }
            else { show(url, near: NSEvent.mouseLocation) }
        }
    }

    @objc private func preview() {
        guard model?.busy != true else { return }
        do { show(try SampleFile.create(), near: NSScreen.main.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? NSEvent.mouseLocation) }
        catch { alert("Couldn’t create the preview", error.localizedDescription) }
    }

    @objc private func enableHover() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func togglePause() {
        watcher.enabled.toggle()
        pauseItem.title = watcher.enabled ? "Pause hovering" : "Resume hovering"
        if !watcher.enabled, model?.busy != true { dismiss() }
    }

    @objc private func help() { NSWorkspace.shared.open(URL(string: "https://github.com/ethan-rong/filewheel#readme")!) }

    @objc private func quit() {
        if model?.busy == true {
            alert("A conversion is running", "Cancel it from the wheel before quitting.")
            panel?.makeKeyAndOrderFront(nil)
        } else { NSApp.terminate(nil) }
    }

    private func showWelcome() {
        let alert = NSAlert()
        alert.messageText = "FileWheel is ready"
        alert.informativeText = "Hover over a supported file in Finder or on your desktop to choose a new format.\n\nEnable FileWheel in System Settings → Privacy & Security → Accessibility. The helper stays in your menu bar; there is no main app window.\n\nYou can preview the wheel without this permission."
        alert.addButton(withTitle: "Preview wheel")
        alert.addButton(withTitle: "Open Accessibility Settings")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { preview() } else { enableHover() }
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.runModal()
    }

    func show(_ url: URL, near point: NSPoint) {
        guard model?.busy != true else { return }
        dismiss()
        let model = WheelModel(input: url)
        guard !model.formats.isEmpty else { return }
        self.model = model
        model.dismiss = { [weak self] in self?.dismiss() }
        model.cancel = { [weak self] in self?.job?.cancel() }
        model.convert = { [weak self] format in self?.convert(format) }
        let size = NSSize(width: 440, height: 510)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: max(bounds.minX, min(point.x - size.width / 2, bounds.maxX - size.width)),
                             y: max(bounds.minY, min(point.y - size.height / 2, bounds.maxY - size.height)))
        let panel = WheelPanel(contentRect: NSRect(origin: origin, size: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "FileWheel"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WheelView(model: model))
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        guard model?.busy != true else { return }
        panel?.orderOut(nil); panel = nil; model = nil
        watcher.suppressUntilMoved()
    }

    private func convert(_ format: OutputFormat) {
        guard let model, !model.busy else { return }
        model.busy = true
        let job = ConversionJob(); self.job = job
        let input = model.input
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Converter.convert(input, to: format.ext, job: job) }
            DispatchQueue.main.async {
                model.busy = false
                switch result {
                case .success(let url): model.result = url
                case .failure(let error):
                    model.message = error is CancellationError ? "Conversion cancelled. Your original is unchanged." : error.localizedDescription
                }
                self.job = nil
            }
        }
    }
}

enum SampleFile {
    static func create() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FileWheel-preview", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Weekend notes.txt")
        try "A new format. A small gesture.\n\nThis is a sample file for trying FileWheel.\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

@main
struct FileWheelMain {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            do { try renderPreview(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])) }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func renderPreview(to url: URL) throws {
        let model = WheelModel(input: URL(fileURLWithPath: "/sample/Weekend notes.txt"))
        let view = HStack(spacing: 0) {
            previewCard(model: model, dark: false)
            previewCard(model: model, dark: true)
        }
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw ConversionError.message("Could not render the preview.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.message("Could not save the preview.") }
    }

    @MainActor private static func previewCard(model: WheelModel, dark: Bool) -> some View {
        VStack(spacing: 0) {
            Text("A new format.").font(.system(size: 32, weight: .semibold, design: .rounded))
            Text("A small gesture.").font(.system(size: 32, weight: .semibold, design: .rounded)).foregroundStyle(dark ? Color(red: 0.75, green: 0.66, blue: 1) : wheelViolet)
            WheelView(model: model).padding(.top, 18)
            Text(dark ? "SMOKED · DARK APPEARANCE" : "FROSTED · LIGHT APPEARANCE")
                .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2).padding(.bottom, 28)
        }
        .padding(.top, 36).frame(width: 500)
        .background {
            LinearGradient(colors: dark ? [Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.22, green: 0.17, blue: 0.31)] : [Color(red: 0.94, green: 0.93, blue: 0.97), Color(red: 0.80, green: 0.84, blue: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        .foregroundStyle(dark ? Color.white : Color(red: 0.1, green: 0.09, blue: 0.14))
    }
}
