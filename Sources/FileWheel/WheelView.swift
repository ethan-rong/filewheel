import SwiftUI

let wheelViolet = Color(red: 100 / 255, green: 70 / 255, blue: 199 / 255)

@MainActor final class WheelModel: ObservableObject {
    @Published var input: URL
    @Published var formats: [OutputFormat]
    @Published var selection = 0
    @Published var busy = false
    @Published var message: String?
    @Published var result: URL?
    var convert: (OutputFormat) -> Void = { _ in }
    var dismiss: () -> Void = {}
    var cancel: () -> Void = {}

    init(input: URL) { self.input = input; formats = Converter.formats(for: input) }

    var kind: FileKind? { FileKind.identify(input) }
    var selected: OutputFormat? { formats.indices.contains(selection) ? formats[selection] : nil }
    var note: String {
        if kind == .video { return "Main video + first audio track. Subtitles omitted." }
        if kind == .document { return input.pathExtension == "md" ? "Markdown is treated as plain text." : "Complex document layouts may change." }
        if kind == .image { return "New copy · photo metadata is not retained" }
        if kind == .pdf { return "All pages · 144 dpi · no OCR" }
        return "New copy · first audio track"
    }
    func step(_ amount: Int) {
        guard !busy, result == nil, message == nil, !formats.isEmpty else { return }
        selection = (selection + amount + formats.count) % formats.count
    }
    func choose() { if !busy, result == nil, message == nil, let selected { convert(selected) } }
}

struct WheelSector: Shape {
    let index: Int
    let count: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.54
        let step = 360.0 / Double(max(count, 1))
        let start = (-90 + Double(index) * step - step / 2 + 1.8) * .pi / 180
        let end = (-90 + Double(index) * step + step / 2 - 1.8) * .pi / 180
        let corner = 7.0
        func point(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .radians(start + corner / outer), endAngle: .radians(end - corner / outer), clockwise: false)
        path.addQuadCurve(to: point(outer - corner, end), control: point(outer, end))
        path.addLine(to: point(inner + corner, end))
        path.addQuadCurve(to: point(inner, end - corner / inner), control: point(inner, end))
        path.addArc(center: center, radius: inner, startAngle: .radians(end - corner / inner), endAngle: .radians(start + corner / inner), clockwise: true)
        path.addQuadCurve(to: point(inner + corner, start), control: point(inner, start))
        path.addLine(to: point(outer - corner, start))
        path.addQuadCurve(to: point(outer, start + corner / outer), control: point(outer, start))
        path.closeSubpath()
        return path
    }
}

struct WheelView: View {
    @ObservedObject var model: WheelModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var surface: Color { scheme == .dark ? Color(red: 0.15, green: 0.14, blue: 0.18) : Color(red: 0.96, green: 0.95, blue: 0.98) }
    private var ink: Color { scheme == .dark ? Color(red: 0.96, green: 0.95, blue: 1) : Color(red: 0.09, green: 0.08, blue: 0.13) }
    private var secondary: Color { scheme == .dark ? Color(red: 0.78, green: 0.76, blue: 0.83) : Color(red: 0.32, green: 0.30, blue: 0.37) }
    private var accent: Color { scheme == .dark ? Color(red: 0.75, green: 0.66, blue: 1) : wheelViolet }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(accent)
                Text("FILEWHEEL").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(2.2)
                Spacer()
                Button(action: model.dismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).disabled(model.busy).accessibilityLabel("Close wheel")
            }
            .foregroundStyle(ink).padding(.horizontal, 13).padding(.vertical, 4)
            .background { Capsule().fill(.regularMaterial) }
            .frame(width: 220)

            ZStack {
                if !model.busy && model.message == nil && model.result == nil {
                    ForEach(Array(model.formats.enumerated()), id: \.element.id) { index, format in
                        sector(index, format)
                    }
                } else {
                    Circle().stroke(wheelViolet.opacity(0.13), lineWidth: 64).padding(33)
                }
                center
            }
            .frame(width: 396, height: 396)
            .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.12), radius: 14, y: 7)

            VStack(spacing: 4) {
                Text(model.busy ? "Your original stays untouched" : "Click to convert  ·  Scroll to select  ·  Esc to close")
                    .font(.system(size: 11, weight: .medium))
                Text(model.note).font(.system(size: 10))
            }
            .foregroundStyle(secondary).padding(.horizontal, 14).padding(.vertical, 9)
            .background { Capsule().fill(.regularMaterial) }
        }
        .padding(18)
        .frame(width: 440, height: 510)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.selection)
    }

    private func sector(_ index: Int, _ format: OutputFormat) -> some View {
        let shape = WheelSector(index: index, count: model.formats.count)
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(model.formats.count)
        let selected = model.selection == index
        return Button { model.selection = index; model.choose() } label: {
            ZStack {
                if selected { shape.fill(wheelViolet) }
                else if reduceTransparency { shape.fill(surface) }
                else { shape.fill(.regularMaterial) }
                shape.stroke(selected ? Color.white.opacity(0.45) : ink.opacity(0.16), lineWidth: selected ? 1.5 : 0.7)
                VStack(spacing: 5) {
                    Text(format.label).font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(format.detail).font(.system(size: 10, weight: .medium))
                    if selected { Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)) }
                }
                .foregroundStyle(selected ? .white : ink)
                .offset(x: cos(angle) * 151, y: sin(angle) * 151)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain).contentShape(shape).focusable(false)
        .onHover { inside in if inside { model.selection = index } }
        .accessibilityLabel("Convert to \(format.label), \(format.detail)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help("Create a \(format.label) copy beside the original")
    }

    private var center: some View {
        VStack(spacing: 9) {
            if model.busy {
                ProgressView().controlSize(.small)
                Text("Converting…").font(.system(size: 16, weight: .semibold))
                Text(model.input.lastPathComponent).font(.system(size: 11)).lineLimit(2)
                Button("Cancel", action: model.cancel).buttonStyle(.borderless).tint(accent)
            } else if let result = model.result {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(accent)
                Text("All done").font(.system(size: 18, weight: .semibold))
                Text(result.lastPathComponent).font(.system(size: 11)).lineLimit(2)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([result]); model.dismiss() }
                    .buttonStyle(.borderless).tint(accent)
            } else if let message = model.message {
                Image(systemName: "exclamationmark.circle").font(.system(size: 25)).foregroundStyle(accent)
                Text("Couldn’t convert").font(.system(size: 14, weight: .semibold))
                ScrollView { Text(message).font(.system(size: 11)).textSelection(.enabled) }.frame(maxHeight: 73)
                Button("Back") { model.message = nil }.buttonStyle(.borderless).tint(accent)
            } else {
                Image(systemName: model.kind?.symbol ?? "doc").font(.system(size: 28, weight: .light)).foregroundStyle(accent)
                Text(model.input.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(2).truncationMode(.middle)
                Text((model.kind?.rawValue ?? "File").uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(secondary)
                if let selected = model.selected {
                    Text("→ \(selected.label)").font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                }
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(ink)
        .frame(width: 154, height: 166)
        .frame(width: 202, height: 202)
        .background {
            if reduceTransparency { Circle().fill(surface) } else { Circle().fill(.regularMaterial) }
        }
        .overlay { Circle().stroke(ink.opacity(0.12), lineWidth: 0.7) }
    }
}
