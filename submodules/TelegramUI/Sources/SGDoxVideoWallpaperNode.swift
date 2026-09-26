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
    private var currentUrl: URL?
    
    public var onReady: (() -> Void)?
    
    public override init() {
        super.init()
        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        self.backgroundColor = .clear
        self.isHidden = true
        self.alpha = 0.0
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        self.statusObserver?.invalidate()
        self.statusObserver = nil
        self.readyObserver?.invalidate()
        self.readyObserver = nil
        self.player?.pause()
        self.player = nil
        self.playerLayer?.removeFromSuperlayer()
        self.playerLayer = nil
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

    private func configureAudioSessionForSilentPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                if session.category == .playback {
                    try session.setCategory(.playback, options: [.mixWithOthers])
                } else {
                    try session.setCategory(.ambient, options: [.mixWithOthers])
                }
            }
        } catch {
        }
    }

    public func setup(with fileUrl: URL) {
        self.isHidden = false
        self.alpha = 1.0
        if self.currentUrl == fileUrl, self.player != nil {
            self.play()
            return
        }
        self.currentUrl = fileUrl
        
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        self.statusObserver?.invalidate()
        self.statusObserver = nil
        self.player?.pause()
        self.playerLayer?.removeFromSuperlayer()
        
        self.configureAudioSessionForSilentPlayback()
        
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
        
        self.readyObserver?.invalidate()
        self.readyObserver = playerLayer.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] layer, _ in
            if layer.isReadyForDisplay {
                DispatchQueue.main.async {
                    self?.backgroundColor = .black
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
        
        self.play()
    }
    
    public func clear() {
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
        self.currentUrl = nil
        self.isPlaying = false
        self.onReady = nil
        self.backgroundColor = .clear
        self.isHidden = true
        self.alpha = 0.0
    }
    
    public func play() {
        guard let player = self.player, !self.isPlaying else { return }
        self.configureAudioSessionForSilentPlayback()
        self.isPlaying = true
        player.play()
    }
    
    public func pause() {
        guard let player = self.player, self.isPlaying else { return }
        self.isPlaying = false
        player.pause()
    }
    
    @objc private func appWillResignActive() {
        self.pause()
    }
    
    @objc private func appDidBecomeActive() {
        if !self.isHidden && self.alpha > 0.01 {
            self.play()
        }
    }
    
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        let frame = CGRect(origin: .zero, size: size)
        transition.updateFrame(node: self, frame: frame)
        if let playerLayer = self.playerLayer {
            transition.updateFrame(layer: playerLayer, frame: CGRect(origin: .zero, size: size))
        }
    }
}
