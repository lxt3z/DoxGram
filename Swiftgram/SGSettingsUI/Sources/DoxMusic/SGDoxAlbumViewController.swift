import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import AppBundle

public final class SGDoxAlbumViewController: ViewController, UITableViewDataSource, UITableViewDelegate {
    public let context: AccountContext
    public let album: SGDoxAlbum
    
    private var tracks: [SGDoxMusicTrack] = []
    
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    
    private let headerView = UIView()
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistButton = UIButton(type: .system)
    private let subtitleLabel = UILabel()
    private let playAllButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    
    public init(context: AccountContext, album: SGDoxAlbum) {
        self.context = context
        self.album = album
        super.init(navigationBarPresentationData: nil)
        self.navigationPresentation = .modal
        self.statusBar.statusBarStyle = .White
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
        
        self.blurView.frame = self.view.bounds
        self.blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.blurView)
        
        // Grabber
        let grabber = UIView(frame: CGRect(x: (self.view.bounds.width - 38) * 0.5, y: 10, width: 38, height: 5))
        grabber.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        grabber.layer.cornerRadius = 2.5
        grabber.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        self.view.addSubview(grabber)
        
        // Close Button
        let closeButton = UIButton(type: .system)
        closeButton.frame = CGRect(x: self.view.bounds.width - 44, y: 12, width: 32, height: 32)
        closeButton.autoresizingMask = [.flexibleLeftMargin]
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor(white: 1.0, alpha: 0.5)
        closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(closeButton)
        
        // Table View
        self.tableView.frame = CGRect(x: 0, y: 44, width: self.view.bounds.width, height: self.view.bounds.height - 44)
        self.tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.tableView.backgroundColor = .clear
        self.tableView.separatorColor = UIColor(white: 1.0, alpha: 0.08)
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(AlbumTrackCell.self, forCellReuseIdentifier: "AlbumTrackCell")
        self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 44, right: 0)
        self.view.addSubview(self.tableView)
        
        // Activity Indicator
        self.activityIndicator.center = CGPoint(x: self.view.bounds.width * 0.5, y: self.view.bounds.height * 0.55)
        self.activityIndicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        self.activityIndicator.color = .white
        self.activityIndicator.hidesWhenStopped = true
        self.view.addSubview(self.activityIndicator)
        self.activityIndicator.startAnimating()
        
        self.setupHeaderView()
        self.loadAlbumData()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.layoutHeader(width: self.view.bounds.width)
    }
    
    private func setupHeaderView() {
        self.artworkImageView.layer.cornerRadius = 16
        self.artworkImageView.layer.cornerCurve = .continuous
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        self.headerView.addSubview(self.artworkImageView)
        
        if let artUrl = self.album.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artUrl) { [weak self] image in
                self?.artworkImageView.image = image
            }
        }
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        self.titleLabel.textColor = .white
        self.titleLabel.textAlignment = .center
        self.titleLabel.numberOfLines = 2
        self.titleLabel.text = self.album.title
        self.headerView.addSubview(self.titleLabel)
        
        self.artistButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.artistButton.setTitleColor(UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0), for: .normal)
        self.artistButton.setTitle(self.album.artist, for: .normal)
        self.artistButton.addTarget(self, action: #selector(self.artistPressed), for: .touchUpInside)
        self.headerView.addSubview(self.artistButton)
        
        var subParts: [String] = []
        if let rel = self.album.releaseDate, rel.count >= 4 {
            subParts.append(String(rel.prefix(4)))
        }
        if self.album.trackCount > 0 {
            subParts.append("\(self.album.trackCount) треков")
        }
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        self.subtitleLabel.textAlignment = .center
        self.subtitleLabel.text = subParts.joined(separator: " • ")
        self.headerView.addSubview(self.subtitleLabel)
        
        self.playAllButton.setTitle("▶  Слушать", for: .normal)
        self.playAllButton.setTitleColor(.white, for: .normal)
        self.playAllButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.playAllButton.backgroundColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 0.85)
        self.playAllButton.layer.cornerRadius = 19
        self.playAllButton.addTarget(self, action: #selector(self.playAllPressed), for: .touchUpInside)
        self.headerView.addSubview(self.playAllButton)
        
        self.shuffleButton.setTitle("🔀  Перемешать", for: .normal)
        self.shuffleButton.setTitleColor(.white, for: .normal)
        self.shuffleButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.shuffleButton.backgroundColor = UIColor(white: 1.0, alpha: 0.16)
        self.shuffleButton.layer.cornerRadius = 19
        self.shuffleButton.addTarget(self, action: #selector(self.shufflePressed), for: .touchUpInside)
        self.headerView.addSubview(self.shuffleButton)
        
        self.layoutHeader(width: self.view.bounds.width)
    }
    
    private func layoutHeader(width: CGFloat) {
        guard width > 0 else { return }
        let screenW = width
        
        let artSize: CGFloat = min(150.0, screenW * 0.42)
        self.artworkImageView.frame = CGRect(x: (screenW - artSize) * 0.5, y: 16, width: artSize, height: artSize)
        
        let titleY = self.artworkImageView.frame.maxY + 14
        self.titleLabel.frame = CGRect(x: 20, y: titleY, width: screenW - 40, height: 26)
        
        let artistY = self.titleLabel.frame.maxY + 4
        self.artistButton.frame = CGRect(x: 20, y: artistY, width: screenW - 40, height: 20)
        
        let subY = self.artistButton.frame.maxY + 4
        self.subtitleLabel.frame = CGRect(x: 20, y: subY, width: screenW - 40, height: 16)
        
        let btnW = (screenW - 48 - 12) * 0.5
        let btnH: CGFloat = 38.0
        let btnY = self.subtitleLabel.frame.maxY + 16
        
        self.playAllButton.frame = CGRect(x: 24, y: btnY, width: btnW, height: btnH)
        self.shuffleButton.frame = CGRect(x: self.playAllButton.frame.maxX + 12, y: btnY, width: btnW, height: btnH)
        
        let totalH = btnY + btnH + 16
        self.headerView.frame = CGRect(x: 0, y: 0, width: screenW, height: totalH)
        self.tableView.tableHeaderView = self.headerView
    }
    
    private func loadAlbumData() {
        AppleMusicService.shared.fetchAlbumTracks(collectionId: self.album.id) { [weak self] albumTracks in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()
                self.tracks = albumTracks
                if !albumTracks.isEmpty {
                    var subParts: [String] = []
                    if let rel = self.album.releaseDate, rel.count >= 4 {
                        subParts.append(String(rel.prefix(4)))
                    }
                    subParts.append("\(albumTracks.count) треков")
                    self.subtitleLabel.text = subParts.joined(separator: " • ")
                }
                self.tableView.reloadData()
            }
        }
    }
    
    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc private func artistPressed() {
        let artistVc = SGDoxArtistViewController(context: self.context, artistName: self.album.artist)
        self.present(artistVc, in: .window(.root))
    }
    
    @objc private func playAllPressed() {
        guard !self.tracks.isEmpty else { return }
        var list = self.tracks
        let first = list.removeFirst()
        SGDoxMusicManager.shared.play(track: first, queue: list)
    }
    
    @objc private func shufflePressed() {
        guard !self.tracks.isEmpty else { return }
        var list = self.tracks
        list.shuffle()
        let first = list.removeFirst()
        SGDoxMusicManager.shared.play(track: first, queue: list)
    }
    
    // MARK: - UITableViewDataSource & Delegate
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.tracks.count
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 52.0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "AlbumTrackCell", for: indexPath) as? AlbumTrackCell else {
            return UITableViewCell()
        }
        let track = self.tracks[indexPath.row]
        let isCurrent = SGDoxMusicManager.shared.currentTrack?.id == track.id
        cell.configure(track: track, index: indexPath.row + 1, isCurrent: isCurrent)
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let track = self.tracks[indexPath.row]
        let upcoming = Array(self.tracks.dropFirst(indexPath.row + 1))
        SGDoxMusicManager.shared.play(track: track, queue: upcoming)
        tableView.reloadData()
    }
}

// MARK: - AlbumTrackCell

private final class AlbumTrackCell: UITableViewCell {
    private let indexLabel = UILabel()
    private let titleLabel = UILabel()
    private let durationLabel = UILabel()
    private let playingIndicator = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.indexLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        self.indexLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        self.indexLabel.textAlignment = .center
        self.contentView.addSubview(self.indexLabel)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        self.titleLabel.textColor = .white
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)
        
        self.durationLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.durationLabel.textColor = UIColor(white: 1.0, alpha: 0.45)
        self.durationLabel.textAlignment = .right
        self.contentView.addSubview(self.durationLabel)
        
        self.playingIndicator.image = UIImage(systemName: "waveform")
        self.playingIndicator.tintColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
        self.playingIndicator.isHidden = true
        self.contentView.addSubview(self.playingIndicator)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        
        self.indexLabel.frame = CGRect(x: 12, y: (bounds.height - 20) * 0.5, width: 28, height: 20)
        
        let durW: CGFloat = 46
        self.durationLabel.frame = CGRect(x: bounds.width - durW - 16, y: (bounds.height - 18) * 0.5, width: durW, height: 18)
        self.playingIndicator.frame = CGRect(x: bounds.width - 36, y: (bounds.height - 18) * 0.5, width: 18, height: 18)
        
        let titleX: CGFloat = 48
        let titleW: CGFloat = bounds.width - titleX - durW - 24
        self.titleLabel.frame = CGRect(x: titleX, y: (bounds.height - 20) * 0.5, width: titleW, height: 20)
    }
    
    func configure(track: SGDoxMusicTrack, index: Int, isCurrent: Bool) {
        self.indexLabel.text = "\(index)"
        self.titleLabel.text = track.title
        self.titleLabel.textColor = isCurrent ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : .white
        
        let durM = Int(track.duration) / 60
        let durS = Int(track.duration) % 60
        self.durationLabel.text = track.duration > 0 ? String(format: "%d:%02d", durM, durS) : ""
        self.durationLabel.isHidden = isCurrent
        self.playingIndicator.isHidden = !isCurrent
    }
}
