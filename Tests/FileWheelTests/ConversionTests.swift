import XCTest
import AppKit
import PDFKit
@testable import FileWheel

final class ConversionTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func text(_ name: String = "notes.txt") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "Hello, FileWheel.\nUnicode: café 世界\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func image(_ name: String = "sample.png", orientation: Int = 1) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let context = CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 0.6))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 16))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testDocumentsRoundTripAndNoClobber() throws {
        let input = try text("notes ; $(not-a-command).txt")
        let before = try Data(contentsOf: input)
        for format in Converter.formats(for: input) {
            let output = try Converter.convert(input, to: format.ext)
            XCTAssertGreaterThan(try Data(contentsOf: output).count, 0)
            let roundTrip = try Converter.convert(output, to: "txt")
            XCTAssertTrue(try String(contentsOf: roundTrip).contains("café 世界"))
        }
        let originalRTF = directory.appendingPathComponent("notes ; $(not-a-command).rtf")
        let existing = try Data(contentsOf: originalRTF)
        let duplicate = try Converter.convert(input, to: "rtf")
        XCTAssertEqual(duplicate.lastPathComponent, "notes ; $(not-a-command)-1.rtf")
        XCTAssertEqual(try Data(contentsOf: originalRTF), existing)
        XCTAssertEqual(try Data(contentsOf: input), before)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".filewheel-") })
    }

    func testImageOutputsAndOrientation() throws {
        let input = try image(orientation: 6)
        let before = try Data(contentsOf: input)
        for format in Converter.formats(for: input) {
            let output = try Converter.convert(input, to: format.ext)
            if format.ext == "pdf" {
                XCTAssertEqual(PDFDocument(url: output)?.pageCount, 1)
            } else {
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
                let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(decoded.width, 16)
                XCTAssertEqual(decoded.height, 32)
            }
        }
        XCTAssertEqual(try Data(contentsOf: input), before)
    }

    func testEveryPDFPageIsExported() throws {
        let input = directory.appendingPathComponent("two pages.pdf")
        var box = CGRect(x: 0, y: 0, width: 50, height: 70)
        let context = try XCTUnwrap(CGContext(input as CFURL, mediaBox: &box, nil))
        for _ in 0..<2 { context.beginPDFPage(nil); context.setFillColor(CGColor(gray: 0.3, alpha: 1)); context.fill(box); context.endPDFPage() }
        context.closePDF()
        for ext in ["png", "jpg", "tiff"] {
            let output = try Converter.convert(input, to: ext)
            let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            XCTAssertEqual(files.count, 2)
            for file in files {
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(image.width, 100); XCTAssertEqual(image.height, 140)
            }
        }
        XCTAssertThrowsError(try Converter.convert(input, to: "txt"))
        XCTAssertEqual(PDFDocument(url: input)?.pageCount, 2)
    }

    func testInvalidFilesCancellationAndSymlinksLeaveNoOutput() throws {
        let invalid = try text("fake.png")
        XCTAssertThrowsError(try Converter.convert(invalid, to: "jpg"))
        let input = try text()
        let job = ConversionJob(); job.cancel()
        XCTAssertThrowsError(try Converter.convert(input, to: "rtf", job: job)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try Converter.convert(input, to: "mp3"))
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: input)
        XCTAssertThrowsError(try Converter.convert(link, to: "rtf"))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), ["fake.png", "notes.txt", "link.txt"])
    }

    func testFinderNameMatchingRefusesAmbiguityAndTraversal() throws {
        let file = try text("Draft.txt")
        XCTAssertEqual(FinderFileResolver.match(names: ["Draft"], folder: directory)?.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        _ = try text("Draft.md")
        XCTAssertNil(FinderFileResolver.match(names: ["Draft"], folder: directory))
        XCTAssertEqual(FinderFileResolver.match(names: ["Draft.txt"], folder: directory), file)
        XCTAssertNil(FinderFileResolver.match(names: ["../Draft.txt"], folder: directory))
        XCTAssertNil(FinderFileResolver.match(names: ["Draft.txt", "Draft.md"], folder: directory))
    }

    func testAudioAndVideoOutputsDecode() throws {
        guard let ffmpeg = Converter.executable("ffmpeg") else { throw XCTSkip("FFmpeg is optional and is not installed") }
        let audio = directory.appendingPathComponent("tone.wav")
        try ConversionJob().run(ffmpeg, ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.15", audio.path])
        for format in Converter.formats(for: audio) {
            let output = try Converter.convert(audio, to: format.ext)
            try ConversionJob().run(ffmpeg, ["-v", "error", "-nostdin", "-i", output.path, "-f", "null", "-"])
        }
        let video = directory.appendingPathComponent("clip.mov")
        try ConversionJob().run(ffmpeg, ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "color=c=purple:s=32x32:r=10:d=0.2", "-f", "lavfi", "-i", "sine=duration=0.2", "-c:v", "libx264", "-c:a", "aac", "-shortest", video.path])
        for format in Converter.formats(for: video) {
            let output = try Converter.convert(video, to: format.ext)
            try ConversionJob().run(ffmpeg, ["-v", "error", "-nostdin", "-i", output.path, "-f", "null", "-"])
        }
    }

    func testRunningProcessCanBeCancelled() throws {
        let job = ConversionJob()
        let done = expectation(description: "Process terminates")
        DispatchQueue.global().async {
            do { try job.run(URL(fileURLWithPath: "/bin/sleep"), ["20"]); XCTFail("Expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError) }
            done.fulfill()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { job.cancel() }
        wait(for: [done], timeout: 3)
    }
}
