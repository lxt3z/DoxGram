import Foundation
import AVFoundation
import AudioToolbox
import CoreImage
import TelegramVoip
import SGCallRecordings

final class CallVideoRecording {
    typealias Frame = OngoingGroupCallContext.VideoFrameData

    struct SavedFile {
        let url: URL
        let exceededLimit: Bool
    }

    private enum RecordingError: LocalizedError {
        case noVideo
        case cannotWrite

        var errorDescription: String? {
            switch self {
            case .noVideo: return "В записи нет кадров видео."
            case .cannotWrite: return "Не удалось сохранить видео."
            }
        }
    }

    private static let warningBytes: Int64 = 2_000_000_000
    private static let frameInterval: DispatchTimeInterval = .milliseconds(42)
    private let queue = DispatchQueue(label: "DoxGram.CallVideoRecording", qos: .utility)
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    private let framesInFlight = DispatchSemaphore(value: 4)
    private let audioInFlight = DispatchSemaphore(value: 50)
    private let file: URL
    private let savedURL: URL
    private let warning: () -> Void
    private let thermalStop: () -> Void
    private var timer: DispatchSourceTimer?
    private var remote: (CIImage, UInt64)?
    private var local: (CIImage, UInt64)?
    private var pendingRemote: (Frame, UInt64)?
    private var pendingLocal: (Frame, UInt64)?
    private var writer: AVAssetWriter?
    private var pixels: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var audioFormat: CMAudioFormatDescription?
    private var outputSize = CGSize.zero
    private var startTime: UInt64?
    private var audioEnd: CMTime?
    private var wroteVideo = false
    private var warned = false
    private var lastSizeCheck: UInt64 = 0
    private var lastFrameTime: UInt64 = 0
    private var thermalStopSent = false
    private var stopped = false
    private var failure: Error?

    init(warning: @escaping () -> Void, thermalStop: @escaping () -> Void) throws {
        let directory = try SGCallRecordings.directory(create: true)
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "DoxGram-\(date)-\(UUID().uuidString.prefix(8)).mp4"
        self.savedURL = directory.appendingPathComponent(name)
        self.file = directory.appendingPathComponent("." + name)
        self.warning = warning
        self.thermalStop = thermalStop

        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: .now(), repeating: Self.frameInterval, leeway: .milliseconds(4))
        timer.setEventHandler { [weak self] in self?.writeVideoFrame() }
        self.timer = timer
        timer.resume()
    }

    deinit {
        self.timer?.cancel()
        if self.writer?.status == .writing { self.writer?.cancelWriting() }
        try? FileManager.default.removeItem(at: self.file)
    }

    func appendVideo(_ frame: Frame, incoming: Bool) {
        let time = DispatchTime.now().uptimeNanoseconds
        guard self.framesInFlight.wait(timeout: .now()) == .success else { return }
        self.queue.async {
            defer { self.framesInFlight.signal() }
            guard !self.stopped, self.failure == nil else { return }
            if incoming {
                self.pendingRemote = (frame, time)
            } else {
                self.pendingLocal = (frame, time)
            }
        }
    }

    func clearCamera(incoming: Bool) {
        self.queue.async {
            if incoming {
                self.pendingRemote = nil
                self.remote = nil
            } else {
                self.pendingLocal = nil
                self.local = nil
            }
        }
    }

    func appendAudio(_ pcm: Data, at time: UInt64) {
        guard self.audioInFlight.wait(timeout: .now()) == .success else { return }
        self.queue.async {
            defer { self.audioInFlight.signal() }
            guard !self.stopped, let origin = self.startTime, time >= origin,
                  let input = self.audioInput, input.isReadyForMoreMediaData,
                  let format = self.audioFormat, !pcm.isEmpty else { return }
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: pcm.count,
                blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: pcm.count,
                flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block) == noErr, let block else { return }
            let copied = pcm.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> OSStatus in
                guard let address = bytes.baseAddress else { return -1 }
                return CMBlockBufferReplaceDataBytes(with: address, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count)
            }
            guard copied == noErr else { return }
            let timestamp = Self.timestamp(time, from: origin)
            let pts = self.audioEnd.map { CMTimeMaximum($0, timestamp) } ?? timestamp
            var sample: CMSampleBuffer?
            let count = pcm.count / 2
            guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block,
                formatDescription: format, sampleCount: count, presentationTimeStamp: pts,
                packetDescriptions: nil, sampleBufferOut: &sample) == noErr, let sample else { return }
            if input.append(sample) {
                self.audioEnd = CMTimeAdd(pts, CMTime(value: Int64(count), timescale: 48_000))
            }
        }
    }

    private func createWriter(size: CGSize, origin: UInt64) throws {
        let scale = min(CGFloat(1), 1280 / max(size.width, size.height))
        let width = max(2, Int(size.width * scale) & ~1)
        let height = max(2, Int(size.height * scale) & ~1)
        self.outputSize = CGSize(width: width, height: height)
        let writer = try AVAssetWriter(outputURL: self.file, fileType: .mp4)
        // Fragmented MP4 makes the growing file size observable during recording.
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        let picture = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: min(7_000_000, max(600_000, width * height * 5)),
                AVVideoExpectedSourceFrameRateKey: 24
            ]
        ])
        picture.expectsMediaDataInRealTime = true
        let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: picture, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ])
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ])
        audio.expectsMediaDataInRealTime = true
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr,
            let format, writer.canAdd(picture), writer.canAdd(audio) else { throw RecordingError.cannotWrite }
        writer.add(picture)
        writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? RecordingError.cannotWrite }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer
        self.pixels = pixels
        self.audioInput = audio
        self.audioFormat = format
        self.startTime = origin
    }

    private func writeVideoFrame() {
        guard !self.stopped, self.failure == nil else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let power = ProcessInfo.processInfo
        if power.thermalState == .critical {
            if !self.thermalStopSent {
                self.thermalStopSent = true
                DispatchQueue.main.async(execute: self.thermalStop)
            }
            return
        }
        if (power.thermalState == .serious || power.isLowPowerModeEnabled) && now - self.lastFrameTime < 82_000_000 {
            return
        }
        self.lastFrameTime = now
        if let (frame, timestamp) = self.pendingRemote {
            self.pendingRemote = nil
            if let image = Self.videoImage(frame) { self.remote = (image, timestamp) }
        }
        if let (frame, timestamp) = self.pendingLocal {
            self.pendingLocal = nil
            if let image = Self.videoImage(frame) { self.local = (image, timestamp) }
        }
        let remote = self.remote.flatMap { now - $0.1 < 750_000_000 ? $0.0 : nil }
        let local = self.local.flatMap { now - $0.1 < 750_000_000 ? $0.0 : nil }
        if self.writer == nil {
            guard let first = remote ?? local else { return }
            do { try self.createWriter(size: first.extent.size, origin: now) } catch {
                self.failure = error
                return
            }
        }
        if now - self.lastSizeCheck >= 1_000_000_000 {
            self.lastSizeCheck = now
            self.checkSize()
        }
        if self.writer?.status == .failed {
            self.failure = self.writer?.error ?? RecordingError.cannotWrite
            return
        }
        guard let pixels = self.pixels, let startTime = self.startTime, pixels.assetWriterInput.isReadyForMoreMediaData,
              let pool = pixels.pixelBufferPool else { return }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { return }
        let canvas = CGRect(origin: .zero, size: self.outputSize)
        var composed = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvas)
        if let main = remote ?? local {
            composed = Self.fit(main, in: canvas).composited(over: composed)
        }
        if remote != nil, let local {
            let inset = CGRect(x: canvas.width * 0.69, y: canvas.height * 0.035,
                width: canvas.width * 0.28, height: canvas.height * 0.28)
            composed = Self.fit(local, in: inset).composited(over: composed)
        }
        self.imageContext.render(composed, to: buffer, bounds: canvas, colorSpace: self.colorSpace)
        if pixels.append(buffer, withPresentationTime: Self.timestamp(now, from: startTime)) {
            self.wroteVideo = true
        }
    }

    private func checkSize() {
        if !self.warned && Self.size(of: self.file) > Self.warningBytes {
            self.warned = true
            DispatchQueue.main.async(execute: self.warning)
        }
    }

    func finish(_ completion: @escaping (Result<SavedFile, Error>) -> Void) {
        self.queue.async {
            self.stopped = true
            self.timer?.cancel()
            self.timer = nil
            guard let writer = self.writer, writer.status == .writing, self.wroteVideo, self.failure == nil else {
                let error = self.failure ?? self.writer?.error ?? RecordingError.noVideo
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            self.pixels?.assetWriterInput.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting {
                self.queue.async {
                    guard writer.status == .completed else {
                        let error = writer.error ?? RecordingError.cannotWrite
                        DispatchQueue.main.async { completion(.failure(error)) }
                        return
                    }
                    self.checkSize()
                    do {
                        try FileManager.default.moveItem(at: self.file, to: self.savedURL)
                        let file = SavedFile(url: self.savedURL, exceededLimit: self.warned)
                        DispatchQueue.main.async { completion(.success(file)) }
                    } catch {
                        DispatchQueue.main.async { completion(.failure(error)) }
                    }
                }
            }
        }
    }

    private static func size(of url: URL) -> Int64 {
        return ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    private static func timestamp(_ time: UInt64, from origin: UInt64) -> CMTime {
        return CMTime(value: Int64((time - origin) / 1_000), timescale: 1_000_000)
    }

    private static func fit(_ image: CIImage, in area: CGRect) -> CIImage {
        let scale = min(area.width / image.extent.width, area.height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return scaled.transformed(by: CGAffineTransform(translationX: area.midX - scaled.extent.midX,
            y: area.midY - scaled.extent.midY))
    }

    private static func videoImage(_ frame: Frame) -> CIImage? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let image: CIImage
        switch frame.buffer {
        case let .native(buffer), let .argb(buffer), let .bgra(buffer):
            image = CIImage(cvPixelBuffer: buffer.pixelBuffer)
        case let .nv12(buffer):
            guard let pixel = Self.yuvBuffer(width: buffer.width, height: buffer.height, y: buffer.y,
                strideY: buffer.strideY, chroma: buffer.uv, strideUV: buffer.strideUV) else { return nil }
            image = CIImage(cvPixelBuffer: pixel)
        case let .i420(buffer):
            let cols = (buffer.width + 1) / 2
            let rows = (buffer.height + 1) / 2
            let u = buffer.u
            let v = buffer.v
            guard buffer.strideU >= cols, buffer.strideV >= cols,
                  u.count >= buffer.strideU * rows, v.count >= buffer.strideV * rows else { return nil }
            var uv = Data(count: cols * rows * 2)
            uv.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
                u.withUnsafeBytes { (u: UnsafeRawBufferPointer) in
                    v.withUnsafeBytes { (v: UnsafeRawBufferPointer) in
                        for row in 0 ..< rows {
                            for col in 0 ..< cols {
                                target[(row * cols + col) * 2] = u[row * buffer.strideU + col]
                                target[(row * cols + col) * 2 + 1] = v[row * buffer.strideV + col]
                            }
                        }
                    }
                }
            }
            guard let pixel = Self.yuvBuffer(width: buffer.width, height: buffer.height, y: buffer.y,
                strideY: buffer.strideY, chroma: uv, strideUV: cols * 2) else { return nil }
            image = CIImage(cvPixelBuffer: pixel)
        }
        let mirrored = image.transformed(by: CGAffineTransform(scaleX: frame.mirrorHorizontally ? -1 : 1,
            y: frame.mirrorVertically ? -1 : 1))
        switch frame.deviceRelativeOrientation ?? frame.orientation {
        case .rotation0: return mirrored
        case .rotation90: return mirrored.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
        case .rotation180: return mirrored.transformed(by: CGAffineTransform(rotationAngle: .pi))
        case .rotation270: return mirrored.transformed(by: CGAffineTransform(rotationAngle: .pi / 2))
        }
    }

    private static func yuvBuffer(width: Int, height: Int, y: Data, strideY: Int, chroma: Data, strideUV: Int) -> CVPixelBuffer? {
        let chromaWidth = ((width + 1) / 2) * 2
        let chromaHeight = (height + 1) / 2
        guard width > 0, height > 0, strideY >= width, strideUV >= chromaWidth,
              y.count >= strideY * height, chroma.count >= strideUV * chromaHeight else { return nil }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, nil, &pixel) == kCVReturnSuccess,
              let pixel, CVPixelBufferLockBaseAddress(pixel, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        for (index, plane) in [(y, strideY, width, height), (chroma, strideUV, chromaWidth, chromaHeight)].enumerated() {
            guard let destination = CVPixelBufferGetBaseAddressOfPlane(pixel, index) else { return nil }
            let outputStride = CVPixelBufferGetBytesPerRowOfPlane(pixel, index)
            guard outputStride >= plane.2 else { return nil }
            plane.0.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                guard let source = bytes.baseAddress else { return }
                for row in 0 ..< plane.3 {
                    memcpy(destination.advanced(by: outputStride * row), source.advanced(by: plane.1 * row), plane.2)
                }
            }
        }
        return pixel
    }
}
