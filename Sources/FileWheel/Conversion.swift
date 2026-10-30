import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum FileKind: String {
    case image = "Image", document = "Document", pdf = "PDF", audio = "Audio", video = "Video"

    var symbol: String {
        switch self {
        case .image: return "photo"
        case .document: return "doc.text"
        case .pdf: return "doc.richtext"
        case .audio: return "waveform"
        case .video: return "film"
        }
    }

    static func identify(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ["txt", "md", "rtf", "doc", "docx", "odt", "html", "htm"].contains(ext) { return .document }
        if ["mp3", "m4a", "wav", "flac", "ogg", "aiff", "aif", "aac", "opus"].contains(ext) { return .audio }
        if ["mp4", "mov", "mkv", "webm", "avi", "m4v", "mpeg", "mpg"].contains(ext) { return .video }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image), ext != "svg" { return .image }
        return nil
    }
}

struct OutputFormat: Identifiable, Equatable {
    let ext: String
    let detail: String
    var id: String { ext }
    var label: String { ext.uppercased() }
}

enum ConversionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum Converter {
    static func executable(_ name: String) -> URL? {
        // Finder-launched helpers do not inherit a shell's Homebrew PATH.
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    static func formats(for input: URL) -> [OutputFormat] {
        var formats: [(String, String)]
        switch FileKind.identify(input) {
        case .image:
            let types = CGImageDestinationCopyTypeIdentifiers() as! [String]
            formats = [("png", "Lossless"), ("jpg", "Compact"), ("heic", "Efficient"), ("tiff", "Print"), ("bmp", "Bitmap")]
                .filter { UTType(filenameExtension: $0.0).map { types.contains($0.identifier) } ?? false }
            if executable("cwebp") != nil { formats.insert(("webp", "For the web"), at: min(2, formats.count)) }
            formats.append(("pdf", "One document"))
        case .document:
            formats = [("txt", "Plain text"), ("rtf", "Rich text"), ("docx", "Word"), ("html", "Web page"), ("odt", "OpenDocument")]
        case .pdf:
            formats = [("png", "Every page"), ("jpg", "Every page"), ("tiff", "Every page"), ("txt", "Extract text")]
        case .audio:
            formats = [("mp3", "Universal"), ("m4a", "Compact"), ("wav", "Uncompressed"), ("flac", "Lossless"), ("aiff", "Studio"), ("ogg", "Opus audio")]
        case .video:
            formats = [("mp4", "H.264 video"), ("mov", "QuickTime"), ("mkv", "Matroska"), ("webm", "Web video"), ("mp3", "Audio only"), ("wav", "Audio only")]
        case nil: return []
        }
        let inputExtension = input.pathExtension.lowercased()
        return formats.filter { $0.0 != inputExtension && !(inputExtension == "jpeg" && $0.0 == "jpg") }
            .map { OutputFormat(ext: $0.0, detail: $0.1) }
    }

    static func convert(_ input: URL, to ext: String, job: ConversionJob = ConversionJob()) throws -> URL {
        guard input.isFileURL,
              let values = try? input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              FileManager.default.isReadableFile(atPath: input.path),
              let kind = FileKind.identify(input), formats(for: input).contains(where: { $0.ext == ext }) else {
            throw ConversionError.message("Choose a supported, readable local file and an available output format.")
        }
        try job.checkCancellation()
        let manager = FileManager.default
        let parent = input.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".filewheel-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false,
                                    attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: staging) }
        let isPageFolder = kind == .pdf && ext != "txt"
        let payload = staging.appendingPathComponent(isPageFolder ? "pages" : "converted.\(ext)")
        switch kind {
        case .image: try image(input, to: payload, ext: ext, job: job)
        case .pdf: try pdf(input, to: payload, ext: ext, job: job)
        case .document:
            var arguments = ["-convert", ext, "-noload", "-nostore", "-output", payload.path]
            if input.pathExtension.lowercased() == "md" { arguments += ["-format", "txt"] }
            arguments += ["--", input.path]
            try job.run(URL(fileURLWithPath: "/usr/bin/textutil"), arguments)
        case .audio, .video: try media(input, to: payload, ext: ext, kind: kind, job: job)
        }
        try job.checkCancellation()
        guard manager.fileExists(atPath: payload.path) else { throw ConversionError.message("The converter did not produce an output file.") }
        let stem = input.deletingPathExtension().lastPathComponent + (isPageFolder ? "-\(ext)-pages" : "")
        // moveItem fails if another writer wins the name; it never replaces their file.
        for index in 0..<10_000 {
            let name = stem + (index == 0 ? "" : "-\(index)") + (isPageFolder ? "" : ".\(ext)")
            let output = parent.appendingPathComponent(name)
            if manager.fileExists(atPath: output.path) { continue }
            do { try manager.moveItem(at: payload, to: output); return output }
            catch {
                if manager.fileExists(atPath: output.path) { continue }
                throw error
            }
        }
        throw ConversionError.message("Too many files have this name. Rename the source and try again.")
    }

    private static func image(_ input: URL, to output: URL, ext: String, job: ConversionJob) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else { throw ConversionError.message("This image could not be decoded.") }
        // shortcut: reject multi-frame images; add explicit animation/page support before converting them.
        guard CGImageSourceGetCount(source) == 1 else { throw ConversionError.message("Animated and multi-page images are not supported yet. Your original is unchanged.") }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else {
            throw ConversionError.message("This image is invalid or exceeds the 100-megapixel limit.")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ConversionError.message("This image could not be decoded.") }
        try job.checkCancellation()
        if ext == "pdf" {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let context = CGContext(output as CFURL, mediaBox: &box, nil) else { throw ConversionError.message("Could not create the PDF.") }
            context.beginPDFPage(nil); context.draw(image, in: box); context.endPDFPage(); context.closePDF()
        } else if ext == "webp", let encoder = executable("cwebp") {
            let intermediate = output.deletingLastPathComponent().appendingPathComponent("source.png")
            try writeImage(image, to: intermediate, ext: "png")
            try job.run(encoder, ["-quiet", "-q", "90", intermediate.path, "-o", output.path])
        } else {
            try writeImage(image, to: output, ext: ext)
        }
    }

    private static func writeImage(_ image: CGImage, to output: URL, ext: String) throws {
        guard let type = UTType(filenameExtension: ext),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.message("This Mac cannot encode \(ext.uppercased()).")
        }
        let settings: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9,
                                       kCGImageDestinationBackgroundColor: CGColor(gray: 1, alpha: 1)]
        CGImageDestinationAddImage(destination, image, settings as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ConversionError.message("Could not finish encoding the image.") }
    }

    private static func pdf(_ input: URL, to output: URL, ext: String, job: ConversionJob) throws {
        guard let document = PDFDocument(url: input), !document.isLocked, document.pageCount > 0 else {
            throw ConversionError.message("This PDF is unreadable, empty, or password-protected.")
        }
        if ext == "txt" {
            guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ConversionError.message("This PDF has no extractable text. Scanned pages need OCR, which is not included.")
            }
            try text.write(to: output, atomically: true, encoding: .utf8)
            return
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        for index in 0..<document.pageCount {
            try job.checkCancellation()
            try autoreleasepool {
                guard let page = document.page(at: index) else { throw ConversionError.message("Could not read PDF page \(index + 1).") }
                let bounds = page.bounds(for: .mediaBox)
                let rotated = abs(page.rotation % 180) == 90
                let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
                guard size.width > 0, size.height > 0, size.width * size.height * 4 <= 100_000_000 else {
                    throw ConversionError.message("PDF page \(index + 1) exceeds the rendering limit.")
                }
                let thumbnail = page.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .mediaBox)
                guard let image = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw ConversionError.message("Could not render PDF page \(index + 1).")
                }
                try writeImage(image, to: output.appendingPathComponent(String(format: "page-%04d.%@", index + 1, ext)), ext: ext)
            }
        }
    }

    private static func media(_ input: URL, to output: URL, ext: String, kind: FileKind, job: ConversionJob) throws {
        guard let ffmpeg = executable("ffmpeg") else { throw ConversionError.message("Audio and video need FFmpeg. Install it with ‘brew install ffmpeg’, then try again.") }
        var arguments = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-protocol_whitelist", "file,pipe", "-i", input.path]
        if ["mp3", "m4a", "wav", "flac", "aiff", "ogg"].contains(ext) {
            arguments += ["-map", "0:a:0", "-vn"]
            switch ext {
            case "mp3": arguments += ["-c:a", "libmp3lame", "-q:a", "2"]
            case "m4a": arguments += ["-c:a", "aac", "-b:a", "192k"]
            case "wav": arguments += ["-c:a", "pcm_s24le"]
            case "flac": arguments += ["-c:a", "flac"]
            case "aiff": arguments += ["-c:a", "pcm_s24be"]
            default: arguments += ["-c:a", "libopus", "-b:a", "160k"]
            }
        } else {
            arguments += ["-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt", "yuv420p"]
            arguments += ext == "webm"
                ? ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-c:a", "libopus"]
                : ["-c:v", "libx264", "-preset", "medium", "-crf", "20", "-c:a", "aac", "-b:a", "192k"]
            if ext == "mp4" || ext == "mov" { arguments += ["-movflags", "+faststart"] }
        }
        arguments.append(output.path)
        try job.run(ffmpeg, arguments)
    }
}

// Mutable cancellation state and the active process are protected by lock.
final class ConversionJob: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if process?.isRunning == true { process?.terminate() }
    }

    func checkCancellation() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }

    func run(_ executable: URL, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        task.standardError = errors
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try task.run(); process = task; lock.unlock() }
        catch { lock.unlock(); throw error }
        // Drain before waiting so a converter cannot deadlock on a full stderr pipe.
        var diagnostic = Data()
        while true {
            let chunk = errors.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            diagnostic.append(chunk)
            if diagnostic.count > 8192 { diagnostic = Data(diagnostic.suffix(8192)) }
        }
        task.waitUntilExit()
        lock.lock(); process = nil; lock.unlock()
        try checkCancellation()
        guard task.terminationStatus == 0 else {
            let detail = String(decoding: diagnostic, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.message(detail.isEmpty ? "The conversion engine could not convert this file." : String(detail.suffix(700)))
        }
    }
}
