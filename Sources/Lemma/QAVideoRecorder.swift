import AppKit
import AVFoundation
@preconcurrency import ScreenCaptureKit

/// A 60 fps video of Lemma's own windows, for demos made from QA copies: ScreenCaptureKit streams this app's windows
/// (peeks and widgets included, as they open) and each frame is encoded as it arrives. Capturing one's own windows needs
/// no screen-recording permission. The frames' times are mapped to the wall clock, so that a script driving the copy can
/// line its own events up with the video.
final class QAVideoRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "lemma.qa.video")
    private var stream: SCStream?
    private var display: SCDisplay?
    private var windowIDs: [CGWindowID] = []
    private var watcher: Task<Void, Never>?
    private var failure: Error?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var started = false
    private var firstFrameWall: Double = 0
    private var frames = 0

    /// Starts recording the main window's rectangle into `url` (QuickTime, HEVC) at up to `fps` frames a second.
    func start(url: URL, fps: Int) async throws {
        let content = try await SCShareableContent.currentProcess
        guard let main = content.windows.filter({ $0.windowLayer == 0 && $0.frame.width > 400 }).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let display = content.displays.first(where: { $0.frame.intersects(main.frame) }) ?? content.displays.first,
              let app = main.owningApplication ?? content.applications.first else { throw QAHooks.QAError.missing("window to record") }
        let scale = NSScreen.screens.first { $0.frame.width == display.frame.width }?.backingScaleFactor ?? 2
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: main.frame.minX - display.frame.minX, y: main.frame.minY - display.frame.minY, width: main.frame.width, height: main.frame.height)
        configuration.width = Int(main.frame.width * scale)
        configuration.height = Int(main.frame.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 8
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: configuration.width, AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 60_000_000, AVVideoExpectedSourceFrameRateKey: fps]])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? QAHooks.QAError.missing("video writer") }
        queue.sync { self.writer = writer; self.input = input; self.started = false; self.frames = 0 }
        _ = app
        // The app's windows on screen; the filter follows them as hovers, peeks and the Ask widget open and close (a
        // filter naming the application left out the panels opened after the start).
        let windows = Self.visibleWindows(content)
        self.display = display
        self.windowIDs = windows.map(\.windowID)
        let stream = SCStream(filter: SCContentFilter(display: display, including: windows), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, let content = try? await SCShareableContent.currentProcess else { continue }
                let windows = Self.visibleWindows(content)
                let ids = windows.map(\.windowID)
                guard ids != self.windowIDs, let display = self.display, let stream = self.stream else { continue }
                self.windowIDs = ids
                try? await stream.updateContentFilter(SCContentFilter(display: display, including: windows))
            }
        }
    }

    private static func visibleWindows(_ content: SCShareableContent) -> [SCWindow] {
        content.windows.filter { $0.isOnScreen && $0.windowLayer >= 0 && $0.windowLayer != 24 && $0.frame.width > 40 && $0.frame.height > 40 }
            .sorted { $0.windowID < $1.windowID }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { queue.async { self.failure = error } }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let writer, let input,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let time = sampleBuffer.presentationTimeStamp
        if !started {
            writer.startSession(atSourceTime: time)
            // Frame times are on the host clock: the wall-clock time of the first frame is now, less how long ago it was taken.
            let ago = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) - CMTimeGetSeconds(time)
            firstFrameWall = Date().timeIntervalSince1970 - ago
            started = true
        }
        if input.isReadyForMoreMediaData, input.append(sampleBuffer) { frames += 1 }
    }

    /// Stops, finishes the file and returns the wall-clock time of its first frame and how many frames it holds.
    func stop() async throws -> (firstFrameWall: Double, frames: Int) {
        watcher?.cancel(); watcher = nil
        try await stream?.stopCapture()
        stream = nil
        if let failure = queue.sync(execute: { self.failure }) { throw failure }
        let (writer, input, wall, frames): (AVAssetWriter?, AVAssetWriterInput?, Double, Int) = queue.sync { (self.writer, self.input, self.firstFrameWall, self.frames) }
        input?.markAsFinished()
        await writer?.finishWriting()
        if let error = writer?.error { throw error }
        queue.sync { self.writer = nil; self.input = nil }
        return (wall, frames)
    }
}
