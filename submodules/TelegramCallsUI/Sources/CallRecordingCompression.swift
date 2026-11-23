import Foundation
import AVFoundation
import AccountContext

// Main-thread scheduler. The original MP4 is already saved before a job is queued.
final class CallRecordingCompression {
    static let shared = CallRecordingCompression()

    private struct Job {
        let source: URL
        let calls: PresentationCallManager
    }

    private var pending: [Job] = []
    private var running: Job?
    private var cancel: (() -> Void)?
    private var interrupted = false
    private var idleSince: TimeInterval?
    private var timer: Timer?

    func enqueue(_ source: URL, calls: PresentationCallManager) {
        self.pending.append(Job(source: source, calls: calls))
        if self.timer == nil {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func canCompress(_ job: Job) -> Bool {
        let power = ProcessInfo.processInfo
        return !job.calls.hasActiveCall && !job.calls.hasActiveGroupCall &&
            power.thermalState == .nominal && !power.isLowPowerModeEnabled
    }

    private func check() {
        if let running = self.running {
            if !self.interrupted && !self.canCompress(running) {
                self.interrupted = true
                self.cancel?()
            }
            return
        }
        guard let job = self.pending.first else {
            self.idleSince = nil
            self.timer?.invalidate()
            self.timer = nil
            return
        }
        guard self.canCompress(job) else {
            self.idleSince = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let since = self.idleSince ?? now
        self.idleSince = since
        guard now - since >= 5 else { return }
        self.pending.removeFirst()
        self.idleSince = nil
        self.start(job)
    }

    private func start(_ job: Job) {
        let output = job.source.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: job.source), presetName: AVAssetExportPresetHEVCHighestQuality),
              export.supportedFileTypes.contains(.mp4) else { return }
        self.running = job
        self.interrupted = false
        let completed: (Bool) -> Void = { success in
            DispatchQueue.main.async {
                if self.interrupted || !self.canCompress(job) {
                    self.pending.insert(job, at: 0)
                } else if success {
                    let size = Self.size(output)
                    if size > 0, size < Self.size(job.source) {
                        Self.replaceOriginal(job.source, with: output)
                    }
                }
                try? FileManager.default.removeItem(at: output)
                self.running = nil
                self.cancel = nil
            }
        }
        if #available(iOS 18.0, *) {
            let task = Task(priority: .background) {
                do {
                    try await export.export(to: output, as: .mp4)
                    completed(true)
                } catch {
                    completed(false)
                }
            }
            self.cancel = { task.cancel() }
        } else {
            export.outputURL = output
            export.outputFileType = .mp4
            self.cancel = { export.cancelExport() }
            export.exportAsynchronously { completed(export.status == .completed) }
        }
    }

    private static func replaceOriginal(_ source: URL, with output: URL) {
        let manager = FileManager.default
        let backup = source.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).original.mp4")
        do {
            try manager.linkItem(at: source, to: backup)
        } catch {
            return
        }
        do {
            _ = try manager.replaceItemAt(source, withItemAt: output)
            try? manager.removeItem(at: backup)
        } catch {
            if manager.fileExists(atPath: source.path) {
                try? manager.removeItem(at: backup)
            } else {
                try? manager.moveItem(at: backup, to: source)
            }
        }
    }

    private static func size(_ url: URL) -> Int64 {
        return ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }
}
