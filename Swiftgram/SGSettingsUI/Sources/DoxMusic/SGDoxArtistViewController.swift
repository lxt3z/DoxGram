import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import AppBundle

public final class SGDoxArtistViewController: ViewController, UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    public let context: AccountContext
    public let artistName: String
    
    private var topTracks: [SGDoxMusicTrack] = []
    private var albums: [SGDoxAlbum] = []
    private var artistImageUrl: String?
    
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    
    private let headerView = UIView()
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playAllButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let albumsSectionLabel = UILabel()
    private var albumsCollectionView: UICollectionView!
    
    public init(context: AccountContext, artistName: String) {
        self.context = context
        self.artistName = artistName
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
        
        // Grabber / Close button
        let grabber = UIView(frame: CGRect(x: (self.view.bounds.width - 38) * 0.5, y: 10, width: 38, height: 5))
        grabber.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        grabber.layer.cornerRadius = 2.5
        grabber.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        self.view.addSubview(grabber)
        
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
        self.tableView.register(ArtistTrackCell.self, forCellReuseIdentifier: "ArtistTrackCell")
        self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
        self.view.addSubview(self.tableView)
        
        // Setup Header View
        self.setupHeaderView()
        
        // Activity Indicator
        self.activityIndicator.center = CGPoint(x: self.view.bounds.width * 0.5, y: self.view.bounds.height * 0.45)
        self.activityIndicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        self.activityIndicator.color = .white
        self.activityIndicator.hidesWhenStopped = true
        self.view.addSubview(self.activityIndicator)
        self.activityIndicator.startAnimating()
        
        self.loadArtistData()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.layoutHeader(width: self.view.bounds.width)
    }
    
    private func setupHeaderView() {
        let avatarSize: CGFloat = 100.0
        self.avatarImageView.layer.cornerRadius = avatarSize * 0.5
        self.avatarImageView.clipsToBounds = true
        self.avatarImageView.contentMode = .scaleAspectFill
        self.avatarImageView.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        self.avatarImageView.layer.borderWidth = 1.0
        self.avatarImageView.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        self.headerView.addSubview(self.avatarImageView)
        
        self.nameLabel.text = self.artistName
        self.nameLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        self.nameLabel.textColor = .white
        self.nameLabel.textAlignment = .center
        self.headerView.addSubview(self.nameLabel)
        
        self.subtitleLabel.text = "Исполнитель"
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.subtitleLabel.textAlignment = .center
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
        
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 120, height: 165)
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        
        self.albumsSectionLabel.text = "Альбомы и синглы"
        self.albumsSectionLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        self.albumsSectionLabel.textColor = .white
        self.albumsSectionLabel.isHidden = true
        self.headerView.addSubview(self.albumsSectionLabel)
        
        self.albumsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.albumsCollectionView.backgroundColor = .clear
        self.albumsCollectionView.showsHorizontalScrollIndicator = false
        self.albumsCollectionView.dataSource = self
        self.albumsCollectionView.delegate = self
        self.albumsCollectionView.register(ArtistAlbumCell.self, forCellWithReuseIdentifier: "ArtistAlbumCell")
        self.albumsCollectionView.isHidden = true
        self.headerView.addSubview(self.albumsCollectionView)
        
        self.layoutHeader(width: self.view.bounds.width)
    }
    
    private func layoutHeader(width: CGFloat) {
        guard width > 0 else { return }
        let screenW = width
        
        let avatarSize: CGFloat = 100.0
        self.avatarImageView.frame = CGRect(x: (screenW - avatarSize) * 0.5, y: 12, width: avatarSize, height: avatarSize)
        self.nameLabel.frame = CGRect(x: 20, y: self.avatarImageView.frame.maxY + 10, width: screenW - 40, height: 28)
        self.subtitleLabel.frame = CGRect(x: 20, y: self.nameLabel.frame.maxY + 2, width: screenW - 40, height: 18)
        
        let btnW = (screenW - 48 - 12) * 0.5
        let btnH: CGFloat = 38.0
        let btnY = self.subtitleLabel.frame.maxY + 14
        
        self.playAllButton.frame = CGRect(x: 24, y: btnY, width: btnW, height: btnH)
        self.shuffleButton.frame = CGRect(x: self.playAllButton.frame.maxX + 12, y: btnY, width: btnW, height: btnH)
        
        let hasAlbums = !self.albums.isEmpty
        self.albumsSectionLabel.isHidden = !hasAlbums
        self.albumsCollectionView.isHidden = !hasAlbums
        
        let collY = btnY + btnH + 18
        let totalH: CGFloat
        if hasAlbums {
            self.albumsSectionLabel.frame = CGRect(x: 20, y: collY, width: screenW - 40, height: 22)
            self.albumsCollectionView.frame = CGRect(x: 0, y: collY + 28, width: screenW, height: 175)
            totalH = collY + 28 + 175 + 10
        } else {
            totalH = collY + 6
        }
        self.headerView.frame = CGRect(x: 0, y: 0, width: screenW, height: totalH)
        self.tableView.tableHeaderView = self.headerView
    }
    
    private func loadArtistData() {
        AppleMusicService.shared.fetchArtistDetails(artistName: self.artistName) { [weak self] tracks, albums, artistImageUrl in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()
                self.topTracks = tracks
                // Sort albums newest first
                self.albums = albums.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
                self.artistImageUrl = artistImageUrl
                
                if let imgUrl = artistImageUrl {
                    SGDoxImageLoader.shared.loadImage(urlString: imgUrl) { [weak self] loadedImage in
                        self?.avatarImageView.image = loadedImage
                    }
                } else {
                    self.avatarImageView.image = UIImage(systemName: "music.mic")
                    self.avatarImageView.tintColor = .white
                }
                
                self.layoutHeader(width: self.view.bounds.width)
                self.albumsCollectionView.reloadData()
                self.tableView.reloadData()
            }
        }
    }
    
    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc private func playAllPressed() {
        guard !self.topTracks.isEmpty else { return }
        var list = self.topTracks
        let first = list.removeFirst()
        SGDoxMusicManager.shared.play(track: first, queue: list)
    }
    
    @objc private func shufflePressed() {
        guard !self.topTracks.isEmpty else { return }
        var list = self.topTracks
        list.shuffle()
        let first = list.removeFirst()
        SGDoxMusicManager.shared.play(track: first, queue: list)
    }
    
    // MARK: - UITableViewDataSource & Delegate
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.topTracks.count
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return self.topTracks.isEmpty ? nil : "Популярные треки"
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 58.0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "ArtistTrackCell", for: indexPath) as? ArtistTrackCell else {
            return UITableViewCell()
        }
        let track = self.topTracks[indexPath.row]
        let isCurrent = SGDoxMusicManager.shared.currentTrack?.id == track.id
        cell.configure(track: track, index: indexPath.row + 1, isCurrent: isCurrent)
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let track = self.topTracks[indexPath.row]
        let upcoming = Array(self.topTracks.dropFirst(indexPath.row + 1))
        SGDoxMusicManager.shared.play(track: track, queue: upcoming)
        tableView.reloadData()
    }
    
    // MARK: - UICollectionViewDataSource & Delegate
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.albums.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ArtistAlbumCell", for: indexPath) as? ArtistAlbumCell else {
            return UICollectionViewCell()
        }
        let album = self.albums[indexPath.item]
        cell.configure(album: album)
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let album = self.albums[indexPath.item]
        let albumVc = SGDoxAlbumViewController(context: self.context, album: album)
        self.present(albumVc, in: .window(.root))
    }
}

// MARK: - ArtistTrackCell

private final class ArtistTrackCell: UITableViewCell {
    private let indexLabel = UILabel()
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playingIndicator = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.indexLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        self.indexLabel.textColor = UIColor(white: 1.0, alpha: 0.45)
        self.indexLabel.textAlignment = .center
        self.contentView.addSubview(self.indexLabel)
        
        self.artworkImageView.layer.cornerRadius = 6
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        self.contentView.addSubview(self.artworkImageView)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.titleLabel.textColor = .white
        self.contentView.addSubview(self.titleLabel)
        
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.contentView.addSubview(self.subtitleLabel)
        
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
        
        self.indexLabel.frame = CGRect(x: 8, y: (bounds.height - 20) * 0.5, width: 24, height: 20)
        self.artworkImageView.frame = CGRect(x: 36, y: (bounds.height - 42) * 0.5, width: 42, height: 42)
        
        let textX: CGFloat = 88
        let textW: CGFloat = bounds.width - textX - 44
        self.titleLabel.frame = CGRect(x: textX, y: 10, width: textW, height: 20)
        self.subtitleLabel.frame = CGRect(x: textX, y: 30, width: textW, height: 16)
        
        self.playingIndicator.frame = CGRect(x: bounds.width - 34, y: (bounds.height - 20) * 0.5, width: 20, height: 20)
    }
    
    func configure(track: SGDoxMusicTrack, index: Int, isCurrent: Bool) {
        self.indexLabel.text = "\(index)"
        self.titleLabel.text = track.title
        self.titleLabel.textColor = isCurrent ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : .white
        
        let durM = Int(track.duration) / 60
        let durS = Int(track.duration) % 60
        let durStr = track.duration > 0 ? String(format: "%d:%02d", durM, durS) : ""
        let sub = track.album.isEmpty ? durStr : (durStr.isEmpty ? track.album : "\(track.album) • \(durStr)")
        self.subtitleLabel.text = sub
        
        self.playingIndicator.isHidden = !isCurrent
        
        if let artUrl = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artUrl) { [weak self] image in
                self?.artworkImageView.image = image
            }
        } else {
            self.artworkImageView.image = nil
        }
    }
}

// MARK: - ArtistAlbumCell

private final class ArtistAlbumCell: UICollectionViewCell {
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        
        self.artworkImageView.layer.cornerRadius = 10
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        self.contentView.addSubview(self.artworkImageView)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.numberOfLines = 2
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)
        
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 11, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        self.contentView.addSubview(self.subtitleLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.contentView.bounds.width
        self.artworkImageView.frame = CGRect(x: 0, y: 0, width: w, height: w)
        self.titleLabel.frame = CGRect(x: 0, y: w + 6, width: w, height: 28)
        self.subtitleLabel.frame = CGRect(x: 0, y: w + 34, width: w, height: 14)
    }
    
    func configure(album: SGDoxAlbum) {
        self.titleLabel.text = album.title
        var subParts: [String] = []
        if let rel = album.releaseDate, rel.count >= 4 {
            subParts.append(String(rel.prefix(4)))
        }
        if album.trackCount > 0 {
            subParts.append("\(album.trackCount) тр.")
        }
        self.subtitleLabel.text = subParts.joined(separator: " • ")
        
        if let artUrl = album.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artUrl) { [weak self] image in
                self?.artworkImageView.image = image
            }
        } else {
            self.artworkImageView.image = nil
        }
    }
}
