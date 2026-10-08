import AVFoundation
import ScreenCaptureKit

/// Receives ScreenCaptureKit frames and writes them, minus paused stretches, to an MP4.
public final class RegionWriter: NSObject, SCStreamOutput {
    public let queue = DispatchQueue(label: "com.anup.snip.recorder")
    public let url: URL
    public let pixelSize: CGSize
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var started = false
    private var paused = false
    private var pausedAt: CMTime?
    /// Total paused time, taken off every later timestamp so the video has no gaps.
    private var offset = CMTime.zero

    public init(url: URL, pixelSize: CGSize) {
        self.url = url
        self.pixelSize = pixelSize
    }

    public func prepare() throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let w = Int(pixelSize.width), h = Int(pixelSize.height)
        // Past 4096×2304 hardware H.264 gives up; HEVC handles 5K and 6K displays.
        let codec: AVVideoCodecType = (w > 4096 || h > 2304) ? .hevc : .h264
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(w * h * 4, 2_000_000),
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 120,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw WriterError.cannotWrite }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? WriterError.cannotWrite }
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
    }

    private var hostNow: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    public func setPaused(_ value: Bool) {
        queue.async { [self] in
            guard value != paused else { return }
            paused = value
            if value {
                pausedAt = hostNow
            } else if let pausedAt {
                offset = offset + (hostNow - pausedAt)
                self.pausedAt = nil
            }
        }
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !paused, buffer.isValid, let pixels = buffer.imageBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let writer, let input, let adaptor else { return }
        let time = buffer.presentationTimeStamp - offset
        if !started {
            writer.startSession(atSourceTime: time)
            started = true
        }
        if input.isReadyForMoreMediaData { adaptor.append(pixels, withPresentationTime: time) }
    }

    /// Closes the file. Returns nil when no frame was written.
    public func finish() async -> URL? {
        await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
            queue.async { [self] in
                guard let writer, let input, started else {
                    writer?.cancelWriting()
                    done.resume(returning: nil)
                    return
                }
                // Hold the last frame until the moment Stop was pressed, even if the screen sat still.
                let end = (pausedAt ?? hostNow) - offset
                input.markAsFinished()
                writer.endSession(atSourceTime: end)
                writer.finishWriting {
                    done.resume(returning: writer.status == .completed ? self.url : nil)
                }
            }
        }
    }
}

public enum WriterError: LocalizedError {
    case cannotWrite
    public var errorDescription: String? { "Can't write video" }
}
