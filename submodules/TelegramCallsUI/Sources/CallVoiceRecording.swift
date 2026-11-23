import Foundation
import OpusBinding

// The playout callback drives the recording clock. Consume each microphone packet once.
final class CallVoiceRecording {
    private static let sampleRate = 48_000
    private static let packetSamples = 960
    private let queue = DispatchQueue(label: "CallVoiceRecording", qos: .utility)
    private let capacity = DispatchSemaphore(value: 100)
    private let overflowLock = NSLock()
    private var overflow = false
    private let writer = TGOggOpusWriter()
    private let item = TGDataItem()
    private let outputPCM: ((Data, UInt64) -> Void)?
    private var microphone: [Int16] = []
    private var microphoneTime: UInt64 = 0
    private var pending: [Int16] = []
    private var samplesWritten = 0
    private var failed = false
    private var finished = false

    init?(outputPCM: ((Data, UInt64) -> Void)? = nil) {
        self.outputPCM = outputPCM
        if outputPCM == nil && !self.writer.begin(with: self.item) { return nil }
    }

    func append(_ data: Data, rate: Int, channels: Int, isMicrophone: Bool) {
        let time = DispatchTime.now().uptimeNanoseconds
        guard self.capacity.wait(timeout: .now()) == .success else {
            self.overflowLock.lock()
            self.overflow = true
            self.overflowLock.unlock()
            return
        }
        self.queue.async {
            defer { self.capacity.signal() }
            guard !self.finished, !self.failed, rate >= 8000, rate <= 96000, channels > 0 else { return }
            if isMicrophone && data.isEmpty {
                self.microphone.removeAll(keepingCapacity: true)
                return
            }
            let frameCount = data.count / (MemoryLayout<Int16>.size * channels)
            let count = frameCount * Self.sampleRate / rate
            guard count > 0 else { return }
            let samples = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [Int16] in
                if rate == Self.sampleRate && channels == 1 && bytes.count.isMultiple(of: 2) {
                    var samples = [Int16](repeating: 0, count: count)
                    samples.withUnsafeMutableBytes { target in
                        target.copyMemory(from: bytes)
                    }
                    return samples
                }
                return (0 ..< count).map { index in
                    let begin = index * frameCount / count
                    let end = max(begin + 1, (index + 1) * frameCount / count)
                    var sum = 0
                    for frame in begin ..< end {
                        for channel in 0 ..< channels {
                            let offset = (frame * channels + channel) * 2
                            sum += Int(Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)))
                        }
                    }
                    return Int16(sum / ((end - begin) * channels))
                }
            }
            if isMicrophone {
                self.microphone = samples
                self.microphoneTime = time
                return
            }
            let useMicrophone = time >= self.microphoneTime && time - self.microphoneTime < 50_000_000
            var mixed: [Int16] = []
            mixed.reserveCapacity(samples.count)
            for (index, remote) in samples.enumerated() {
                let local = useMicrophone && index < self.microphone.count ? self.microphone[index] : 0
                mixed.append(Int16(clamping: Int(remote) + Int(local)))
            }
            self.microphone.removeAll(keepingCapacity: true)
            if let outputPCM = self.outputPCM {
                outputPCM(mixed.withUnsafeBytes { Data($0) }, time)
                return
            }
            self.pending.append(contentsOf: mixed)
            while self.pending.count >= Self.packetSamples && !self.failed {
                var packet = Array(self.pending.prefix(Self.packetSamples))
                self.pending.removeFirst(Self.packetSamples)
                self.write(&packet)
            }
        }
    }

    private func write(_ packet: inout [Int16]) {
        let count = packet.count
        self.failed = !packet.withUnsafeMutableBytes { bytes in
            self.writer.writeFrame(bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt(bytes.count))
        }
        if !self.failed { self.samplesWritten += count }
    }

    func finish(_ completion: @escaping ((Data, Int)?) -> Void) {
        self.queue.async {
            guard !self.finished else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            self.finished = true
            self.overflowLock.lock()
            let overflow = self.overflow
            self.overflowLock.unlock()
            let duration = self.samplesWritten + self.pending.count
            var result: (Data, Int)?
            if !overflow && !self.failed && duration > 0 {
                var tail = self.pending
                // A short final frame marks Ogg EOS. Leave room for Opus lookahead.
                if tail.count > 600 {
                    tail.append(contentsOf: repeatElement(Int16(0), count: Self.packetSamples - tail.count))
                    self.write(&tail)
                    tail.removeAll()
                }
                if tail.isEmpty { tail.append(0) }
                if !self.failed { self.write(&tail) }
                if !self.failed, let data = self.item.data() {
                    result = (data, max(1, (duration + Self.sampleRate - 1) / Self.sampleRate))
                }
            }
            let recording = result
            DispatchQueue.main.async { completion(recording) }
        }
    }
}
