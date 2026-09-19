import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import SGSimpleSettings
import AppBundle

// MARK: - Native Telegram-Style Liquid Glass Cells

private final class SGDoxServiceCell: UITableViewCell {
    let iconContainer = UIView()
    let iconImageView = UIImageView()
    let titleLabel = UILabel()
    let statusLabel = UILabel()
    let badgeLabel = UILabel()
    let chevronImageView = UIImageView()
    let separatorView = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.iconContainer.layer.cornerRadius = 10
        self.iconContainer.clipsToBounds = true
        self.contentView.addSubview(self.iconContainer)
        
        self.iconImageView.contentMode = .scaleAspectFit
        self.iconImageView.tintColor = .white
        self.iconContainer.addSubview(self.iconImageView)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        self.contentView.addSubview(self.titleLabel)
        
        self.statusLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.contentView.addSubview(self.statusLabel)
        
        self.badgeLabel.layer.cornerRadius = 11
        self.badgeLabel.clipsToBounds = true
        self.badgeLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        self.badgeLabel.textAlignment = .center
        self.contentView.addSubview(self.badgeLabel)
        
        self.chevronImageView.image = UIImage(systemName: "chevron.right")
        self.chevronImageView.contentMode = .scaleAspectFit
        self.contentView.addSubview(self.chevronImageView)
        
        self.contentView.addSubview(self.separatorView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        
        self.iconContainer.frame = CGRect(x: 16, y: 11, width: 38, height: 38)
        self.iconImageView.frame = CGRect(x: 7, y: 7, width: 24, height: 24)
        
        let hasBadge = !(self.badgeLabel.text?.isEmpty ?? true)
        let rightMargin: CGFloat = hasBadge ? 110 : 36
        let titleWidth = bounds.width - 66 - rightMargin
        
        self.titleLabel.frame = CGRect(x: 66, y: 10, width: titleWidth, height: 20)
        self.statusLabel.frame = CGRect(x: 66, y: 31, width: titleWidth, height: 18)
        
        if hasBadge {
            self.badgeLabel.frame = CGRect(x: bounds.width - 98, y: 18, width: 62, height: 24)
            self.chevronImageView.frame = CGRect(x: bounds.width - 28, y: 22, width: 14, height: 16)
        } else {
            self.badgeLabel.frame = .zero
            self.chevronImageView.frame = CGRect(x: bounds.width - 28, y: 22, width: 14, height: 16)
        }
        
        self.separatorView.frame = CGRect(x: 66, y: bounds.height - 0.5, width: bounds.width - 66, height: 0.5)
    }
}

private final class SGDoxWaveHeroCell: UITableViewCell {
    let containerCard = UIView()
    let gradientLayer = CAGradientLayer()
    let iconImageView = UIImageView()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let playPill = UIView()
    let playIcon = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.containerCard.layer.cornerRadius = 18
        self.containerCard.clipsToBounds = true
        self.contentView.addSubview(self.containerCard)
        
        self.gradientLayer.colors = [
            UIColor(red: 0.95, green: 0.18, blue: 0.52, alpha: 0.92).cgColor,
            UIColor(red: 0.55, green: 0.15, blue: 0.95, alpha: 0.92).cgColor,
            UIColor(red: 0.12, green: 0.58, blue: 0.98, alpha: 0.90).cgColor
        ]
        self.gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.containerCard.layer.insertSublayer(self.gradientLayer, at: 0)
        
        self.iconImageView.image = UIImage(systemName: "dot.radiowaves.left.and.right")
        self.iconImageView.tintColor = .white
        self.iconImageView.contentMode = .scaleAspectFit
        self.containerCard.addSubview(self.iconImageView)
        
        self.titleLabel.text = "⚡ Запустить «Мою волну»"
        self.titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        self.titleLabel.textColor = .white
        self.containerCard.addSubview(self.titleLabel)
        
        self.subtitleLabel.text = "Умный бесконечный поток под ваш вкус"
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.containerCard.addSubview(self.subtitleLabel)
        
        self.playPill.backgroundColor = UIColor(white: 1.0, alpha: 0.25)
        self.playPill.layer.cornerRadius = 18
        self.playPill.clipsToBounds = true
        self.containerCard.addSubview(self.playPill)
        
        self.playIcon.image = UIImage(systemName: "play.fill")
        self.playIcon.tintColor = .white
        self.playIcon.contentMode = .scaleAspectFit
        self.playPill.addSubview(self.playIcon)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        self.containerCard.frame = CGRect(x: 16, y: 4, width: bounds.width - 32, height: bounds.height - 8)
        self.gradientLayer.frame = self.containerCard.bounds
        
        self.iconImageView.frame = CGRect(x: 16, y: 20, width: 36, height: 36)
        
        let textWidth = self.containerCard.bounds.width - 64 - 56
        self.titleLabel.frame = CGRect(x: 62, y: 16, width: textWidth, height: 22)
        self.subtitleLabel.frame = CGRect(x: 62, y: 40, width: textWidth, height: 18)
        
        self.playPill.frame = CGRect(x: self.containerCard.bounds.width - 48, y: 20, width: 36, height: 36)
        self.playIcon.frame = CGRect(x: 10, y: 9, width: 18, height: 18)
    }
}

private final class SGDoxLibraryHeaderCell: UITableViewCell {
    let containerCard = UIView()
    let titleLabel = UILabel()
    let countLabel = UILabel()
    let playAllButton = UIButton(type: .system)
    let shuffleButton = UIButton(type: .system)
    
    var onPlayAllTapped: (() -> Void)?
    var onShuffleTapped: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.containerCard.layer.cornerRadius = 16
        self.containerCard.clipsToBounds = true
        self.contentView.addSubview(self.containerCard)
        
        self.titleLabel.text = "💖 Моя медиатека"
        self.titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        self.containerCard.addSubview(self.titleLabel)
        
        self.countLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.containerCard.addSubview(self.countLabel)
        
        self.playAllButton.setTitle(" Слушать всё", for: .normal)
        self.playAllButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        self.playAllButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.playAllButton.layer.cornerRadius = 16
        self.playAllButton.clipsToBounds = true
        self.playAllButton.addTarget(self, action: #selector(self.playAllPressed), for: .touchUpInside)
        self.containerCard.addSubview(self.playAllButton)
        
        self.shuffleButton.setTitle(" Перемешать", for: .normal)
        self.shuffleButton.setImage(UIImage(systemName: "shuffle"), for: .normal)
        self.shuffleButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.shuffleButton.layer.cornerRadius = 16
        self.shuffleButton.clipsToBounds = true
        self.shuffleButton.addTarget(self, action: #selector(self.shufflePressed), for: .touchUpInside)
        self.containerCard.addSubview(self.shuffleButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func playAllPressed() {
        self.onPlayAllTapped?()
    }
    
    @objc private func shufflePressed() {
        self.onShuffleTapped?()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        self.containerCard.frame = CGRect(x: 16, y: 4, width: bounds.width - 32, height: bounds.height - 8)
        
        self.titleLabel.frame = CGRect(x: 16, y: 12, width: self.containerCard.bounds.width - 32, height: 20)
        self.countLabel.frame = CGRect(x: 16, y: 33, width: self.containerCard.bounds.width - 32, height: 16)
        
        let buttonWidth = (self.containerCard.bounds.width - 32 - 12) * 0.5
        self.playAllButton.frame = CGRect(x: 16, y: 56, width: buttonWidth, height: 34)
        self.shuffleButton.frame = CGRect(x: 16 + buttonWidth + 12, y: 56, width: buttonWidth, height: 34)
    }
}

private final class SGDoxTrackCell: UITableViewCell {
    let artworkView = UIImageView()
    let titleLabel = UILabel()
    let artistLabel = UILabel()
    let sourceBadge = UILabel()
    let likeButton = UIButton(type: .system)
    let playIcon = UIImageView()
    let separatorView = UIView()
    var currentTrackId: String?
    var onLikeTapped: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.artworkView.layer.cornerRadius = 8
        self.artworkView.clipsToBounds = true
        self.artworkView.contentMode = .scaleAspectFill
        self.artworkView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        self.contentView.addSubview(self.artworkView)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.contentView.addSubview(self.titleLabel)
        
        self.artistLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.contentView.addSubview(self.artistLabel)
        
        self.sourceBadge.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        self.sourceBadge.layer.cornerRadius = 4
        self.sourceBadge.clipsToBounds = true
        self.sourceBadge.textAlignment = .center
        self.contentView.addSubview(self.sourceBadge)
        
        self.likeButton.addTarget(self, action: #selector(self.likePressed), for: .touchUpInside)
        self.contentView.addSubview(self.likeButton)
        
        self.playIcon.image = UIImage(systemName: "play.circle.fill")
        self.playIcon.contentMode = .scaleAspectFit
        self.contentView.addSubview(self.playIcon)
        
        self.contentView.addSubview(self.separatorView)
    }
    
    @objc private func likePressed() {
        self.onLikeTapped?()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        
        self.artworkView.frame = CGRect(x: 16, y: 9, width: 44, height: 44)
        
        let textWidth = bounds.width - 70 - 90
        self.titleLabel.frame = CGRect(x: 70, y: 12, width: textWidth, height: 19)
        self.artistLabel.frame = CGRect(x: 70, y: 32, width: textWidth - 46, height: 17)
        
        self.sourceBadge.frame = CGRect(x: bounds.width - 128, y: 32, width: 44, height: 16)
        self.likeButton.frame = CGRect(x: bounds.width - 78, y: 15, width: 34, height: 30)
        self.playIcon.frame = CGRect(x: bounds.width - 38, y: 19, width: 22, height: 22)
        
        self.separatorView.frame = CGRect(x: 70, y: bounds.height - 0.5, width: bounds.width - 70, height: 0.5)
    }
}

// MARK: - SGDoxMusicHubController

public final class SGDoxMusicHubController: ViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    
    private let miniPlayerContainer = UIView()
    private let miniPlayerBlurView = UIVisualEffectView()
    private let miniArtworkImageView = UIImageView()
    private let miniTitleLabel = UILabel()
    private let miniArtistLabel = UILabel()
    private let miniPlayPauseButton = UIButton(type: .system)
    private let miniProgressView = UIProgressView(progressViewStyle: .default)
    
    private var searchResults: [SGDoxMusicTrack] = []
    private var isSearching = false
    private var searchTimer: Timer?
    private var activeSearchTask: URLSessionDataTask?
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "DoxMusic"
        self.ready.set(.single(true))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.searchTimer?.invalidate()
        self.activeSearchTask?.cancel()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        
        self.setupSearchBar()
        self.setupTableView()
        self.setupMiniPlayer()
        
        SGDoxMusicManager.shared.addStateListener { [weak self] in
            self?.updateMiniPlayer()
            self?.tableView.reloadData()
        }
        
        SGDoxMusicManager.shared.addTimeListener { [weak self] current, duration in
            guard let self = self, duration > 0 else { return }
            let progress = Float(current / duration)
            self.miniProgressView.setProgress(progress, animated: true)
        }
        
        DiscordRPCService.shared.onStatusChanged = { [weak self] _ in
            self?.tableView.reloadData()
        }
        
        SGDoxMusicManager.shared.syncFavoritesWithServices()
        
        if self.searchResults.isEmpty {
            self.loadDefaultRecommendations()
        }
    }
    
    private func setupSearchBar() {
        self.searchBar.delegate = self
        self.searchBar.placeholder = "Поиск в Apple Music и Spotify..."
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.tintColor = self.presentationData.theme.list.itemAccentColor
        
        if let textField = self.searchBar.value(forKey: "searchField") as? UITextField {
            textField.textColor = self.presentationData.theme.list.itemPrimaryTextColor
            textField.backgroundColor = self.presentationData.theme.list.itemBlocksBackgroundColor
            textField.layer.cornerRadius = 10
            textField.clipsToBounds = true
        }
        self.view.addSubview(self.searchBar)
    }
    
    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.register(SGDoxServiceCell.self, forCellReuseIdentifier: "ServiceCell")
        self.tableView.register(SGDoxWaveHeroCell.self, forCellReuseIdentifier: "WaveHeroCell")
        self.tableView.register(SGDoxLibraryHeaderCell.self, forCellReuseIdentifier: "LibraryHeaderCell")
        self.tableView.register(SGDoxTrackCell.self, forCellReuseIdentifier: "TrackCell")
        self.view.addSubview(self.tableView)
    }
    
    private func setupMiniPlayer() {
        self.miniPlayerContainer.backgroundColor = .clear
        self.miniPlayerContainer.layer.shadowColor = UIColor.black.cgColor
        self.miniPlayerContainer.layer.shadowOpacity = 0.2
        self.miniPlayerContainer.layer.shadowRadius = 12
        self.miniPlayerContainer.layer.shadowOffset = CGSize(width: 0, height: 4)
        
        let blurEffect = UIBlurEffect(style: self.presentationData.theme.overallDarkAppearance ? .systemMaterialDark : .systemMaterialLight)
        self.miniPlayerBlurView.effect = blurEffect
        self.miniPlayerBlurView.layer.cornerRadius = 24
        self.miniPlayerBlurView.layer.borderWidth = 0.5
        self.miniPlayerBlurView.layer.borderColor = self.presentationData.theme.list.itemBlocksSeparatorColor.cgColor
        self.miniPlayerBlurView.clipsToBounds = true
        self.miniPlayerContainer.addSubview(self.miniPlayerBlurView)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.miniPlayerTapped))
        self.miniPlayerContainer.addGestureRecognizer(tap)
        
        self.miniArtworkImageView.layer.cornerRadius = 8
        self.miniArtworkImageView.clipsToBounds = true
        self.miniArtworkImageView.contentMode = .scaleAspectFill
        self.miniArtworkImageView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.miniPlayerBlurView.contentView.addSubview(self.miniArtworkImageView)
        
        self.miniTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.miniTitleLabel.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.miniPlayerBlurView.contentView.addSubview(self.miniTitleLabel)
        
        self.miniArtistLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        self.miniArtistLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        self.miniPlayerBlurView.contentView.addSubview(self.miniArtistLabel)
        
        self.miniPlayPauseButton.tintColor = self.presentationData.theme.list.itemAccentColor
        self.miniPlayPauseButton.addTarget(self, action: #selector(self.miniPlayPausePressed), for: .touchUpInside)
        self.miniPlayerBlurView.contentView.addSubview(self.miniPlayPauseButton)
        
        self.miniProgressView.progressTintColor = self.presentationData.theme.list.itemAccentColor
        self.miniProgressView.trackTintColor = self.presentationData.theme.list.itemBlocksSeparatorColor
        self.miniPlayerBlurView.contentView.addSubview(self.miniProgressView)
        
        self.view.addSubview(self.miniPlayerContainer)
        self.updateMiniPlayer()
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let navHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bounds = CGRect(origin: .zero, size: layout.size)
        
        self.searchBar.frame = CGRect(x: 8, y: navHeight + 4, width: bounds.width - 16, height: 44)
        
        let miniPlayerHeight: CGFloat = SGDoxMusicManager.shared.currentTrack != nil ? 60.0 : 0.0
        let miniPlayerY = bounds.height - layout.intrinsicInsets.bottom - miniPlayerHeight - 8
        
        self.miniPlayerContainer.frame = CGRect(x: 16, y: miniPlayerY, width: bounds.width - 32, height: miniPlayerHeight)
        self.miniPlayerBlurView.frame = self.miniPlayerContainer.bounds
        self.miniPlayerContainer.isHidden = miniPlayerHeight == 0
        
        self.miniArtworkImageView.frame = CGRect(x: 10, y: 10, width: 40, height: 40)
        self.miniPlayPauseButton.frame = CGRect(x: self.miniPlayerBlurView.bounds.width - 48, y: 12, width: 36, height: 36)
        
        let labelWidth = self.miniPlayerBlurView.bounds.width - 110
        self.miniTitleLabel.frame = CGRect(x: 60, y: 12, width: labelWidth, height: 18)
        self.miniArtistLabel.frame = CGRect(x: 60, y: 30, width: labelWidth, height: 16)
        self.miniProgressView.frame = CGRect(x: 0, y: self.miniPlayerBlurView.bounds.height - 2, width: self.miniPlayerBlurView.bounds.width, height: 2)
        
        let tableY = self.searchBar.frame.maxY + 4
        let tableBottom = self.miniPlayerContainer.isHidden ? (bounds.height - layout.intrinsicInsets.bottom) : miniPlayerY
        let tableHeight = max(0, tableBottom - tableY)
        self.tableView.frame = CGRect(x: 0, y: tableY, width: bounds.width, height: tableHeight)
    }
    
    private func updateMiniPlayer() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else {
            self.miniPlayerContainer.isHidden = true
            return
        }
        
        self.miniPlayerContainer.isHidden = false
        self.miniTitleLabel.text = track.title
        self.miniArtistLabel.text = track.artist
        
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        let iconName = manager.isPlaying ? "pause.circle.fill" : "play.circle.fill"
        self.miniPlayPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        
        if let artwork = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artwork) { [weak self] image in
                self?.miniArtworkImageView.image = image
            }
        } else {
            self.miniArtworkImageView.image = UIImage(bundleImageName: "Media Editor/SmallAudio")
        }
    }
    
    private func loadDefaultRecommendations() {
        if !SGDoxMusicManager.shared.history.isEmpty {
            self.searchResults = Array(SGDoxMusicManager.shared.history.suffix(20).reversed())
            self.tableView.reloadData()
            return
        }
        
        if AppleMusicService.shared.isAuthorized {
            AppleMusicService.shared.fetchUserPersonalMusic { [weak self] tracks in
                DispatchQueue.main.async {
                    self?.searchResults = tracks
                    self?.tableView.reloadData()
                }
            }
            return
        }
        
        self.searchResults = []
        self.tableView.reloadData()
    }
    
    // MARK: - Debounced Search
    
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchTimer?.invalidate()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self.isSearching = false
            self.loadDefaultRecommendations()
            return
        }
        
        self.isSearching = true
        self.searchTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.performSearch(query: trimmed)
        }
    }
    
    private func performSearch(query: String) {
        if SpotifyService.shared.isAuthorized && !AppleMusicService.shared.isAuthorized {
            SpotifyService.shared.search(query: query) { [weak self] tracks, _ in
                DispatchQueue.main.async {
                    self?.searchResults = tracks
                    self?.tableView.reloadData()
                }
            }
        } else {
            AppleMusicService.shared.search(query: query) { [weak self] appleTracks, _ in
                DispatchQueue.main.async {
                    if !appleTracks.isEmpty {
                        self?.searchResults = appleTracks
                        self?.tableView.reloadData()
                    } else if SpotifyService.shared.isAuthorized {
                        SpotifyService.shared.search(query: query) { spotifyTracks, _ in
                            DispatchQueue.main.async {
                                self?.searchResults = spotifyTracks
                                self?.tableView.reloadData()
                            }
                        }
                    } else {
                        self?.searchResults = []
                        self?.tableView.reloadData()
                    }
                }
            }
        }
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        self.searchTimer?.invalidate()
        let text = searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            self.performSearch(query: text)
        }
    }
    
    // MARK: - TableView
    
    private var hasFavorites: Bool {
        return !SGDoxMusicManager.shared.favorites.isEmpty
    }
    
    private func pluralEnding(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 { return "ов" }
        if mod10 == 1 { return "" }
        if mod10 >= 2 && mod10 <= 4 { return "а" }
        return "ов"
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        if self.isSearching {
            return 1
        }
        var count = 2
        if self.hasFavorites {
            count += 1
        }
        if !self.searchResults.isEmpty {
            count += 1
        }
        return count
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.isSearching {
            return self.searchResults.count
        }
        switch section {
        case 0:
            return 3
        case 1:
            return 1
        case 2:
            if self.hasFavorites {
                return 1 + min(50, SGDoxMusicManager.shared.favorites.count)
            } else {
                return self.searchResults.count
            }
        case 3:
            return self.searchResults.count
        default:
            return 0
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if !self.isSearching {
            if indexPath.section == 1 {
                return 88.0
            }
            if self.hasFavorites && indexPath.section == 2 && indexPath.row == 0 {
                return 102.0
            }
        }
        return 60.0
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if self.isSearching {
            return self.searchResults.isEmpty ? "Ничего не найдено" : "Результаты поиска (\(self.searchResults.count))"
        }
        switch section {
        case 0:
            return "Сервисы и интеграции"
        case 1:
            return "Умный поток"
        case 2:
            return self.hasFavorites ? "Моя медиатека" : "Недавно прослушано"
        case 3:
            return "Недавно прослушано"
        default:
            return nil
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let theme = self.presentationData.theme
        
        if !self.isSearching && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ServiceCell", for: indexPath) as! SGDoxServiceCell
            cell.backgroundColor = theme.list.itemBlocksBackgroundColor
            cell.titleLabel.textColor = theme.list.itemPrimaryTextColor
            cell.statusLabel.textColor = theme.list.itemSecondaryTextColor
            cell.chevronImageView.tintColor = theme.list.itemArrowColor
            cell.separatorView.backgroundColor = theme.list.itemBlocksSeparatorColor
            cell.separatorView.isHidden = indexPath.row == 2
            
            if indexPath.row == 0 {
                // Apple Music
                cell.iconContainer.backgroundColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
                cell.iconImageView.image = UIImage(systemName: "music.note")
                cell.titleLabel.text = "Apple Music"
                let isAuth = AppleMusicService.shared.isAuthorized
                cell.statusLabel.text = isAuth ? "Подключено (Полное воспроизведение)" : "Нажмите для входа"
                cell.statusLabel.textColor = isAuth ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor
                cell.badgeLabel.text = isAuth ? "Вкл" : "Войти"
                cell.badgeLabel.backgroundColor = isAuth ? theme.list.itemAccentColor.withAlphaComponent(0.2) : theme.list.itemBlocksSeparatorColor
                cell.badgeLabel.textColor = isAuth ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
            } else if indexPath.row == 1 {
                // Spotify
                cell.iconContainer.backgroundColor = UIColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1.0)
                cell.iconImageView.image = UIImage(systemName: "waveform")
                cell.titleLabel.text = "Spotify"
                let isAuth = SpotifyService.shared.isAuthorized
                cell.statusLabel.text = isAuth ? "Подключено к аккаунту" : (SpotifyService.shared.hasCustomClientId ? "Client ID настроен" : "Нажмите для настройки")
                cell.statusLabel.textColor = isAuth ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor
                cell.badgeLabel.text = isAuth ? "Вкл" : "Вход"
                cell.badgeLabel.backgroundColor = isAuth ? theme.list.itemAccentColor.withAlphaComponent(0.2) : theme.list.itemBlocksSeparatorColor
                cell.badgeLabel.textColor = isAuth ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
            } else {
                // Discord RPC
                cell.iconContainer.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1.0)
                cell.iconImageView.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")
                cell.titleLabel.text = "Discord RPC"
                let isEnabled = SGSimpleSettings.shared.discordRpcEnabled && !SGSimpleSettings.shared.discordRpcToken.isEmpty
                switch DiscordRPCService.shared.status {
                case .connected(let username):
                    cell.statusLabel.text = "В сети: \(username)"
                    cell.statusLabel.textColor = theme.list.itemAccentColor
                case .connecting:
                    cell.statusLabel.text = "Подключение..."
                    cell.statusLabel.textColor = theme.list.itemSecondaryTextColor
                case .error:
                    cell.statusLabel.text = "Ошибка токена"
                    cell.statusLabel.textColor = theme.list.itemDestructiveColor
                case .disconnected:
                    cell.statusLabel.text = isEnabled ? "Включен" : "Настроить токен"
                    cell.statusLabel.textColor = theme.list.itemSecondaryTextColor
                }
                cell.badgeLabel.text = isEnabled ? "Вкл" : "Токен"
                cell.badgeLabel.backgroundColor = isEnabled ? theme.list.itemAccentColor.withAlphaComponent(0.2) : theme.list.itemBlocksSeparatorColor
                cell.badgeLabel.textColor = isEnabled ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
            }
            return cell
        }
        
        if !self.isSearching && indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "WaveHeroCell", for: indexPath) as! SGDoxWaveHeroCell
            return cell
        }
        
        if !self.isSearching && self.hasFavorites && indexPath.section == 2 {
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "LibraryHeaderCell", for: indexPath) as! SGDoxLibraryHeaderCell
                cell.containerCard.backgroundColor = theme.list.itemBlocksBackgroundColor
                cell.titleLabel.textColor = theme.list.itemPrimaryTextColor
                cell.countLabel.textColor = theme.list.itemSecondaryTextColor
                
                let count = SGDoxMusicManager.shared.favorites.count
                cell.countLabel.text = "\(count) трек\(self.pluralEnding(count)) • Синхронизировано"
                
                cell.playAllButton.backgroundColor = theme.list.itemAccentColor
                cell.playAllButton.tintColor = .white
                cell.shuffleButton.backgroundColor = theme.list.itemBlocksSeparatorColor
                cell.shuffleButton.tintColor = theme.list.itemPrimaryTextColor
                
                cell.onPlayAllTapped = { [weak self] in
                    guard let self = self else { return }
                    let favs = SGDoxMusicManager.shared.favorites
                    guard let first = favs.first else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    SGDoxMusicManager.shared.play(track: first, queue: Array(favs.dropFirst()))
                    self.openPlayer()
                }
                
                cell.onShuffleTapped = { [weak self] in
                    guard let self = self else { return }
                    var shuffled = SGDoxMusicManager.shared.favorites.shuffled()
                    guard !shuffled.isEmpty else { return }
                    let first = shuffled.removeFirst()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    SGDoxMusicManager.shared.play(track: first, queue: shuffled)
                    self.openPlayer()
                }
                return cell
            }
            
            let trackIndex = indexPath.row - 1
            let favs = SGDoxMusicManager.shared.favorites
            guard trackIndex < favs.count else { return UITableViewCell() }
            let track = favs[trackIndex]
            
            let cell = tableView.dequeueReusableCell(withIdentifier: "TrackCell", for: indexPath) as! SGDoxTrackCell
            self.configureTrackCell(cell, track: track, isLast: trackIndex == min(favs.count - 1, 49))
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "TrackCell", for: indexPath) as! SGDoxTrackCell
        guard indexPath.row < self.searchResults.count else { return cell }
        let track = self.searchResults[indexPath.row]
        self.configureTrackCell(cell, track: track, isLast: indexPath.row == self.searchResults.count - 1)
        return cell
    }
    
    private func configureTrackCell(_ cell: SGDoxTrackCell, track: SGDoxMusicTrack, isLast: Bool) {
        let theme = self.presentationData.theme
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.titleLabel.text = track.title
        cell.titleLabel.textColor = theme.list.itemPrimaryTextColor
        cell.artistLabel.text = track.artist
        cell.artistLabel.textColor = theme.list.itemSecondaryTextColor
        cell.playIcon.tintColor = theme.list.itemAccentColor
        cell.separatorView.backgroundColor = theme.list.itemBlocksSeparatorColor
        cell.separatorView.isHidden = isLast
        
        cell.sourceBadge.text = track.source == .appleMusic ? "Apple" : "Spotify"
        cell.sourceBadge.backgroundColor = track.source == .appleMusic ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 0.15) : UIColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 0.15)
        cell.sourceBadge.textColor = track.source == .appleMusic ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : UIColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1.0)
        
        let isFav = SGDoxMusicManager.shared.isFavorite(track: track)
        let heartConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let heartIcon = isFav ? "suit.heart.fill" : "suit.heart"
        cell.likeButton.setImage(UIImage(systemName: heartIcon, withConfiguration: heartConfig), for: .normal)
        cell.likeButton.tintColor = isFav ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : theme.list.itemSecondaryTextColor
        cell.onLikeTapped = { [weak self] in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            SGDoxMusicManager.shared.toggleFavorite(track: track)
            self?.tableView.reloadData()
        }
        
        cell.currentTrackId = track.id
        if let artwork = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artwork) { [weak cell] image in
                if cell?.currentTrackId == track.id {
                    cell?.artworkView.image = image
                }
            }
        } else {
            cell.artworkView.image = UIImage(bundleImageName: "Media Editor/SmallAudio")
        }
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if !self.isSearching && indexPath.section == 0 {
            if indexPath.row == 0 {
                AppleMusicService.shared.requestAuthorization { [weak self] _ in
                    DispatchQueue.main.async { self?.tableView.reloadData() }
                }
            } else if indexPath.row == 1 {
                self.presentSpotifyMenu()
            } else {
                self.presentDiscordRpcDialog()
            }
            return
        }
        
        if !self.isSearching && indexPath.section == 1 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            SGDoxMusicManager.shared.startWave()
            self.openPlayer()
            return
        }
        
        if !self.isSearching && self.hasFavorites && indexPath.section == 2 {
            if indexPath.row > 0 {
                let trackIndex = indexPath.row - 1
                let favs = SGDoxMusicManager.shared.favorites
                guard trackIndex < favs.count else { return }
                let track = favs[trackIndex]
                let remaining = Array(favs.suffix(from: trackIndex + 1))
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                SGDoxMusicManager.shared.play(track: track, queue: remaining)
                self.openPlayer()
            }
            return
        }
        
        guard indexPath.row < self.searchResults.count else { return }
        let track = self.searchResults[indexPath.row]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.play(track: track, queue: self.searchResults)
        self.openPlayer()
    }
    
    // MARK: - Dialogs
    
    private func presentSpotifyMenu() {
        let isAuth = SpotifyService.shared.isAuthorized
        let alert = UIAlertController(
            title: "Spotify",
            message: isAuth ? "Spotify подключен к вашему аккаунту." : "Выберите способ подключения:",
            preferredStyle: .actionSheet
        )
        
        if isAuth {
            alert.addAction(UIAlertAction(title: "Выйти из Spotify", style: .destructive, handler: { [weak self] _ in
                SpotifyService.shared.logout()
                self?.tableView.reloadData()
            }))
        } else {
            alert.addAction(UIAlertAction(title: "Войти через OAuth", style: .default, handler: { [weak self] _ in
                guard let self = self else { return }
                if !SpotifyService.shared.hasCustomClientId {
                    self.presentSpotifyClientIdInput(promptBeforeOAuth: true)
                } else {
                    SpotifyService.shared.startAuthorization { [weak self] success, error in
                        DispatchQueue.main.async {
                            if !success, let error = error {
                                let errAlert = UIAlertController(title: "Ошибка Spotify", message: error, preferredStyle: .alert)
                                errAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                                self?.context.sharedContext.applicationBindings.presentNativeController(errAlert)
                            }
                            self?.tableView.reloadData()
                        }
                    }
                }
            }))
            
            alert.addAction(UIAlertAction(title: "Ввести Client ID", style: .default, handler: { [weak self] _ in
                self?.presentSpotifyClientIdInput(promptBeforeOAuth: false)
            }))
            
            alert.addAction(UIAlertAction(title: "Вставить Access Token", style: .default, handler: { [weak self] _ in
                self?.presentSpotifyTokenInput()
            }))
        }
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        self.context.sharedContext.applicationBindings.presentNativeController(alert)
    }
    
    private func presentSpotifyClientIdInput(promptBeforeOAuth: Bool) {
        let alert = UIAlertController(
            title: "Spotify Client ID",
            message: "Введите Client ID приложения из developer.spotify.com (Redirect URI tg://spotify-callback):",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Client ID..."
            textField.text = SpotifyService.shared.hasCustomClientId ? SpotifyService.shared.customClientId : ""
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return
            }
            SpotifyService.shared.customClientId = text
            self?.tableView.reloadData()
            if promptBeforeOAuth {
                SpotifyService.shared.startAuthorization { [weak self] success, error in
                    DispatchQueue.main.async {
                        if !success, let error = error {
                            let errAlert = UIAlertController(title: "Ошибка Spotify", message: error, preferredStyle: .alert)
                            errAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                            self?.context.sharedContext.applicationBindings.presentNativeController(errAlert)
                        }
                        self?.tableView.reloadData()
                    }
                }
            }
        }))
        self.context.sharedContext.applicationBindings.presentNativeController(alert)
    }
    
    private func presentSpotifyTokenInput() {
        let alert = UIAlertController(
            title: "Spotify Access Token",
            message: "Вставьте Access Token Spotify:",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Token..."
            textField.clearButtonMode = .whileEditing
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            SpotifyService.shared.setManualAccessToken(text)
            self?.tableView.reloadData()
        }))
        self.context.sharedContext.applicationBindings.presentNativeController(alert)
    }
    
    private func presentDiscordRpcDialog() {
        let alert = UIAlertController(
            title: "Discord Rich Presence",
            message: "Введите User Token от Discord для отображения музыки в профиле:",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.text = SGSimpleSettings.shared.discordRpcToken
            textField.placeholder = "User Token..."
            textField.clearButtonMode = .whileEditing
            textField.isSecureTextEntry = true
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        if SGSimpleSettings.shared.discordRpcEnabled {
            alert.addAction(UIAlertAction(title: "Выключить", style: .destructive, handler: { [weak self] _ in
                SGSimpleSettings.shared.discordRpcEnabled = false
                DiscordRPCService.shared.disconnect()
                self?.tableView.reloadData()
            }))
        }
        alert.addAction(UIAlertAction(title: "Подключить", style: .default, handler: { [weak self, weak alert] _ in
            let newToken = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            SGSimpleSettings.shared.discordRpcToken = newToken
            SGSimpleSettings.shared.discordRpcEnabled = !newToken.isEmpty
            if !newToken.isEmpty {
                DiscordRPCService.shared.validateToken(newToken) { [weak self] success, _ in
                    if success {
                        DiscordRPCService.shared.connect()
                    }
                    self?.tableView.reloadData()
                }
            } else {
                DiscordRPCService.shared.disconnect()
                self?.tableView.reloadData()
            }
        }))
        self.context.sharedContext.applicationBindings.presentNativeController(alert)
    }
    
    // MARK: - MiniPlayer & Player Navigation
    
    @objc private func miniPlayPausePressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.togglePlay()
    }
    
    @objc private func miniPlayerTapped() {
        self.openPlayer()
    }
    
    private func openPlayer() {
        let playerController = SGDoxMusicPlayerController(context: self.context)
        self.present(playerController, in: .window(.root))
    }
}
