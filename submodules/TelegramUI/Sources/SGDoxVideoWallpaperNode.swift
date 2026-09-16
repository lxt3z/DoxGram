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
    private var isPlaying: Bool = false
    private var currentUrl: URL?
    
    public override init() {
        super.init()
        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        self.player?.pause()
        self.player = nil
    }
    
    public func setup(peerId: Int64) {
        if let localUrl = SGDoxAnimatedWallpaperManager.shared.localFileUrl(for: peerId) {
            self.setup(with: localUrl)
            self.isHidden = false
        } else {
            self.clear()
            self.isHidden = true
        }
    }

    public func setup(with fileUrl: URL) {
        if self.currentUrl == fileUrl, self.player != nil {
            self.play()
            return
        }
        self.currentUrl = fileUrl
        
        if let endObserver = self.endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        self.player?.pause()
        self.playerLayer?.removeFromSuperlayer()
        
        let asset = AVURLAsset(url: fileUrl)
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.actionAtItemEnd = .none
        
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = self.bounds
        self.layer.addSublayer(playerLayer)
        
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
        self.player?.pause()
        self.playerLayer?.removeFromSuperlayer()
        self.playerLayer = nil
        self.player = nil
        self.currentUrl = nil
        self.isPlaying = false
    }
    
    public func play() {
        guard let player = self.player, !self.isPlaying else { return }
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
