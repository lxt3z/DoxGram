import Foundation
import UIKit
import AsyncDisplayKit
import Display
import AVFoundation
import SGSimpleSettings

public final class SGDoxVideoWallpaperNode: ASDisplayNode {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var endObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var readyObserver: NSKeyValueObservation?
    private var isPlaying: Bool = false
    private var wantsPlayback: Bool = false
    private var currentUrl: URL?
    private var posterToken: URL?
    
    public var onReady: (() -> Void)?
    
    public override init() {
        super.init()
        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        self.backgroundColor = .clear
        self.isHidden = true
        self.alpha = 0.0
        self.layer.contentsGravity = .resizeAspectFill
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.powerStateChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        self.releasePlayer()
    }
    
    public func setup(peerId: Int64) {
        if let localUrl = SGDoxAnimatedWallpaperManager.shared.localFileUrl(for: peerId) {
            self.isHidden = false
            self.alpha = 1.0
            self.setup(with: localUrl)
        } else {
            self.clear()
        }
    }

    public func setup(with fileUrl: URL) {
        self.isHidden = false
        self.alpha = 1.0
        if self.currentUrl != fileUrl {
            self.releasePlayer()
            self.currentUrl = fileUrl
            self.posterToken = nil
            self.layer.contents = nil
        }
        self.ensurePoster(for: fileUrl)
        if self.wantsPlayback {
            self.startPlayback()
        }
    }
    
    public func clear() {
        guard self.player != nil || self.playerLayer != nil || self.currentUrl != nil || self.layer.contents != nil else {
            self.isHidden = true
            self.alpha = 0.0
            self.backgroundColor = .clear
            return
        }
        self.wantsPlayback = false
        self.releasePlayer()
        self.currentUrl = nil
        self.posterToken = nil
        self.layer.contents = nil
        self.onReady = nil
        self.backgroundColor = .clear
        self.isHidden = true
        self.alpha = 0.0
    }
    
    public func play() {
        self.wantsPlayback = true
        self.startPlayback()
    }
    
    public func pause() {
        self.wantsPlayback = false
        self.releasePlayer()
    }
    
    @objc private func appWillResignActive() {
        self.releasePlayer()
    }
    
    @objc private func appDidBecomeActive() {
        if self.wantsPlayback && !self.isHidden && self.alpha > 0.01 {
            self.startPlayback()
        }
    }

    @objc private func powerStateChanged() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            self.releasePlayer()
        } else if self.wantsPlayback && !self.isHidden && self.alpha > 0.01 {
            self.startPlayback()
        }
    }
    
    public override func layout() {
        super.layout()
        self.layer.contentsGravity = .resizeAspectFill
        if let playerLayer = self.playerLayer {
            playerLayer.frame = self.bounds
        }
    }

    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        let frame = CGRect(origin: .zero, size: size)
        transition.updateFrame(node: self, frame: frame)
        if let playerLayer = self.playerLayer {
            transition.updateFrame(layer: playerLayer, frame: CGRect(origin: .zero, size: size))
        }
    }

    private func ensurePoster(for fileUrl: URL) {
        let posterUrl = fileUrl.deletingPathExtension().appendingPathExtension("poster.jpg")
        if self.posterToken == fileUrl, self.layer.contents != nil, FileManager.default.fileExists(atPath: posterUrl.path) {
            self.onReady?()
            return
        }
        if let image = UIImage(contentsOfFile: posterUrl.path) {
            self.applyPoster(image, for: fileUrl)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let asset = AVURLAsset(url: fileUrl)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1080, height: 1080)
            let time = CMTime(seconds: 0.05, preferredTimescale: 600)
            let image = (try? generator.copyCGImage(at: time, actualTime: nil)).map { UIImage(cgImage: $0) }
            if let image, let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: posterUrl, options: .atomic)
            }
            DispatchQueue.main.async {
                guard let self, self.currentUrl == fileUrl else {
                    return
                }
                if let image {
                    self.applyPoster(image, for: fileUrl)
                } else {
                    self.onReady?()
                }
            }
        }
    }

    private func applyPoster(_ image: UIImage, for fileUrl: URL) {
        guard self.currentUrl == fileUrl else {
            return
        }
        self.posterToken = fileUrl
        self.layer.contents = image.cgImage
        self.layer.contentsGravity = .resizeAspectFill
        self.onReady?()
    }

    private func startPlayback() {
        guard self.wantsPlayback, let fileUrl = self.currentUrl else {
            return
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return
        }
        if let player = self.player, self.playerLayer != nil {
            if !self.isPlaying {
                self.isPlaying = true
                player.play()
            }
            return
        }

        let asset = AVURLAsset(url: fileUrl)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.audioMix = AVMutableAudioMix()
        if let audibleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            playerItem.select(nil, in: audibleGroup)
        }
        for track in playerItem.tracks {
            if track.assetTrack?.mediaType == .audio {
                track.isEnabled = false
            }
        }

        self.statusObserver = playerItem.observe(\.status, options: [.new]) { item, _ in
            if item.status == .readyToPlay {
                for track in item.tracks {
                    if track.assetTrack?.mediaType == .audio {
                        track.isEnabled = false
                    }
                }
            }
        }

        let player = AVPlayer(playerItem: playerItem)
        player.volume = 0.0
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.preventsDisplaySleepDuringVideoPlayback = false
        if #available(iOS 15.0, *) {
            player.audiovisualBackgroundPlaybackPolicy = .pauses
        }

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = self.bounds
        self.layer.addSublayer(playerLayer)

        self.readyObserver = playerLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, _ in
            if layer.isReadyForDisplay {
                DispatchQueue.main.async {
                    self?.onReady?()
                }
            }
        }

        self.player = player
        self.playerLayer = playerLayer
        self.endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: playerItem, queue: .main) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        self.isPlaying = true
        player.play()
    }

    private func releasePlayer() {
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        self.statusObserver?.invalidate()
        self.statusObserver = nil
        self.readyObserver?.invalidate()
        self.readyObserver = nil
        self.player?.pause()
        self.playerLayer?.removeFromSuperlayer()
        self.playerLayer = nil
        self.player = nil
        self.isPlaying = false
    }
}
