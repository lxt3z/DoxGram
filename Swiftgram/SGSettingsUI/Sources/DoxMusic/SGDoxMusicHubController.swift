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
        
        self.iconContainer.frame = CGRect(x: 16, y: 8, width: 38, height: 38)
        self.iconImageView.frame = CGRect(x: 7, y: 7, width: 24, height: 24)
        
        let textWidth = bounds.width - 66 - 36
        self.titleLabel.frame = CGRect(x: 66, y: 8, width: textWidth, height: 20)
        self.statusLabel.frame = CGRect(x: 66, y: 28, width: textWidth, height: 18)
        
        self.chevronImageView.frame = CGRect(x: bounds.width - 26, y: 19, width: 12, height: 16)
        self.separatorView.frame = CGRect(x: 66, y: bounds.height - 0.5, width: bounds.width - 66, height: 0.5)
    }
}

private final class SGDoxWaveHeroCell: UITableViewCell {
    let containerCard = UIView()
    let blurView = UIVisualEffectView()
    let ambientGradient = CAGradientLayer()
    let iconBadge = UIView()
    let iconImageView = UIImageView()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let playCircle = UIView()
    let playIcon = UIImageView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.containerCard.layer.cornerRadius = 18
        self.containerCard.layer.borderWidth = 0.5
        self.containerCard.layer.borderColor = UIColor(white: 1.0, alpha: 0.16).cgColor
        self.containerCard.clipsToBounds = true
        self.contentView.addSubview(self.containerCard)
        
        self.ambientGradient.colors = [
            UIColor(red: 0.42, green: 0.12, blue: 0.82, alpha: 0.85).cgColor,
            UIColor(red: 0.12, green: 0.42, blue: 0.95, alpha: 0.85).cgColor
        ]
        self.ambientGradient.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.ambientGradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.containerCard.layer.insertSublayer(self.ambientGradient, at: 0)
        
        self.blurView.effect = UIBlurEffect(style: .systemThinMaterialDark)
        self.containerCard.addSubview(self.blurView)
        
        self.iconBadge.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        self.iconBadge.layer.cornerRadius = 20
        self.iconBadge.clipsToBounds = true
        self.containerCard.addSubview(self.iconBadge)
        
        self.iconImageView.image = UIImage(systemName: "waveform.path.ecg") ?? UIImage(systemName: "dot.radiowaves.left.and.right")
        self.iconImageView.tintColor = .white
        self.iconImageView.contentMode = .scaleAspectFit
        self.iconBadge.addSubview(self.iconImageView)
        
        self.titleLabel.text = "Моя волна"
        self.titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        self.titleLabel.textColor = .white
        self.containerCard.addSubview(self.titleLabel)
        
        self.subtitleLabel.text = "Умный бесконечный поток музыки"
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.containerCard.addSubview(self.subtitleLabel)
        
        self.playCircle.backgroundColor = UIColor(white: 1.0, alpha: 0.22)
        self.playCircle.layer.cornerRadius = 19
        self.playCircle.clipsToBounds = true
        self.containerCard.addSubview(self.playCircle)
        
        self.playIcon.image = UIImage(systemName: "play.fill")
        self.playIcon.tintColor = .white
        self.playIcon.contentMode = .scaleAspectFit
        self.playCircle.addSubview(self.playIcon)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        self.containerCard.frame = CGRect(x: 16, y: 4, width: bounds.width - 32, height: bounds.height - 8)
        self.ambientGradient.frame = self.containerCard.bounds
        self.blurView.frame = self.containerCard.bounds
        
        self.iconBadge.frame = CGRect(x: 14, y: (self.containerCard.bounds.height - 40) * 0.5, width: 40, height: 40)
        self.iconImageView.frame = CGRect(x: 8, y: 8, width: 24, height: 24)
        
        let textWidth = self.containerCard.bounds.width - 64 - 54
        self.titleLabel.frame = CGRect(x: 64, y: 15, width: textWidth, height: 22)
        self.subtitleLabel.frame = CGRect(x: 64, y: 38, width: textWidth, height: 18)
        
        let playY = (self.containerCard.bounds.height - 38) * 0.5
        self.playCircle.frame = CGRect(x: self.containerCard.bounds.width - 50, y: playY, width: 38, height: 38)
        self.playIcon.frame = CGRect(x: 12, y: 10, width: 16, height: 18)
    }
}

private final class SGDoxLibraryHeaderCell: UITableViewCell {
    let titleLabel = UILabel()
    let countLabel = UILabel()
    let playAllButton = UIButton(type: .system)
    let shuffleButton = UIButton(type: .system)
    let separatorView = UIView()
    
    var onPlayAllTapped: (() -> Void)?
    var onShuffleTapped: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.selectionStyle = .none
        
        self.titleLabel.text = "Моя медиатека"
        self.titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        self.contentView.addSubview(self.titleLabel)
        
        self.countLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.contentView.addSubview(self.countLabel)
        
        self.playAllButton.setTitle(" Слушать всё", for: .normal)
        self.playAllButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        self.playAllButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.playAllButton.layer.cornerRadius = 18
        self.playAllButton.clipsToBounds = true
        self.playAllButton.addTarget(self, action: #selector(self.playAllPressed), for: .touchUpInside)
        self.contentView.addSubview(self.playAllButton)
        
        self.shuffleButton.setTitle(" Перемешать", for: .normal)
        self.shuffleButton.setImage(UIImage(systemName: "shuffle"), for: .normal)
        self.shuffleButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.shuffleButton.layer.cornerRadius = 18
        self.shuffleButton.clipsToBounds = true
        self.shuffleButton.addTarget(self, action: #selector(self.shufflePressed), for: .touchUpInside)
        self.contentView.addSubview(self.shuffleButton)
        
        self.contentView.addSubview(self.separatorView)
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
        
        self.titleLabel.frame = CGRect(x: 16, y: 10, width: bounds.width - 32, height: 20)
        self.countLabel.frame = CGRect(x: 16, y: 30, width: bounds.width - 32, height: 16)
        
        let buttonWidth = (bounds.width - 32 - 10) * 0.5
        self.playAllButton.frame = CGRect(x: 16, y: 50, width: buttonWidth, height: 36)
        self.shuffleButton.frame = CGRect(x: 16 + buttonWidth + 10, y: 50, width: buttonWidth, height: 36)
        
        self.separatorView.frame = CGRect(x: 16, y: bounds.height - 0.5, width: bounds.width - 16, height: 0.5)
    }
}

private final class SGDoxTrackCell: UITableViewCell {
    let artworkView = UIImageView()
    let playingIndicator = UIImageView()
    let titleLabel = UILabel()
    let artistLabel = UILabel()
    let likeButton = UIButton(type: .system)
    let separatorView = UIView()
    var currentTrackId: String?
    var onLikeTapped: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.selectionStyle = .default
        
        self.artworkView.layer.cornerRadius = 9
        self.artworkView.clipsToBounds = true
        self.artworkView.contentMode = .scaleAspectFill
        self.artworkView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        self.contentView.addSubview(self.artworkView)
        
        self.playingIndicator.image = UIImage(systemName: "waveform")
        self.playingIndicator.tintColor = .white
        self.playingIndicator.contentMode = .scaleAspectFit
        self.playingIndicator.isHidden = true
        self.artworkView.addSubview(self.playingIndicator)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.contentView.addSubview(self.titleLabel)
        
        self.artistLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.contentView.addSubview(self.artistLabel)
        
        self.likeButton.addTarget(self, action: #selector(self.likePressed), for: .touchUpInside)
        self.contentView.addSubview(self.likeButton)
        
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
        
        self.artworkView.frame = CGRect(x: 16, y: 7, width: 44, height: 44)
        self.playingIndicator.frame = CGRect(x: 12, y: 12, width: 20, height: 20)
        
        let textWidth = bounds.width - 70 - 48
        self.titleLabel.frame = CGRect(x: 70, y: 10, width: textWidth, height: 20)
        self.artistLabel.frame = CGRect(x: 70, y: 30, width: textWidth, height: 18)
        
        self.likeButton.frame = CGRect(x: bounds.width - 44, y: 7, width: 36, height: 44)
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
    private let miniGlossLayer = CAGradientLayer()
    private let miniArtworkImageView = UIImageView()
    private let miniTitleLabel = UILabel()
    private let miniArtistLabel = UILabel()
    private let miniPlayPauseButton = UIButton(type: .system)
    private let miniNextButton = UIButton(type: .system)
    private let miniProgressView = UIProgressView(progressViewStyle: .default)
    
    private var searchResults: [SGDoxMusicTrack] = []
    private var isSearching = false
    private var searchTimer: Foundation.Timer?
    private var activeSearchTask: URLSessionDataTask?
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData, style: .glass))
        self._hasGlassStyle = true
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.title = "DoxMusic"
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.ready.set(.single(true))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.searchTimer?.invalidate()
        self.activeSearchTask?.cancel()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        
        self.setupSearchBar()
        self.setupTableView()
        self.setupMiniPlayer()
        
        SGDoxMusicManager.shared.addStateListener { [weak self] in
            guard let self = self else { return }
            self.updateMiniPlayer()
            if let visible = self.tableView.indexPathsForVisibleRows {
                self.tableView.reloadRows(at: visible, with: .none)
            } else {
                self.tableView.reloadData()
            }
        }
        
        SGDoxMusicManager.shared.addTimeListener { [weak self] current, duration in
            guard let self = self, duration > 0 else { return }
            let progress = Float(current / duration)
            self.miniProgressView.setProgress(progress, animated: true)
        }
        
        DiscordRPCService.shared.onStatusChanged = { [weak self] _ in
            guard let self = self else { return }
            let serviceIndex = IndexPath(row: 2, section: 0)
            if self.tableView.numberOfSections > 0 && self.tableView.numberOfRows(inSection: 0) > 2 {
                self.tableView.reloadRows(at: [serviceIndex], with: .none)
            }
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
        self.miniPlayerContainer.layer.shadowOpacity = 0.32
        self.miniPlayerContainer.layer.shadowRadius = 14
        self.miniPlayerContainer.layer.shadowOffset = CGSize(width: 0, height: 5)
        
        let blurEffect = UIBlurEffect(style: self.presentationData.theme.overallDarkAppearance ? .systemMaterialDark : .systemMaterialLight)
        self.miniPlayerBlurView.effect = blurEffect
        self.miniPlayerBlurView.layer.cornerRadius = 24
        self.miniPlayerBlurView.layer.borderWidth = 0.5
        self.miniPlayerBlurView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        self.miniPlayerBlurView.clipsToBounds = true
        self.miniPlayerContainer.addSubview(self.miniPlayerBlurView)
        
        self.miniGlossLayer.colors = [
            UIColor.white.withAlphaComponent(0.16).cgColor,
            UIColor.white.withAlphaComponent(0.02).cgColor,
            UIColor.clear.cgColor
        ]
        self.miniGlossLayer.locations = [0.0, 0.5, 1.0]
        self.miniGlossLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.miniGlossLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.miniPlayerBlurView.contentView.layer.addSublayer(self.miniGlossLayer)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.miniPlayerTapped))
        self.miniPlayerContainer.addGestureRecognizer(tap)
        
        self.miniArtworkImageView.layer.cornerRadius = 9
        self.miniArtworkImageView.clipsToBounds = true
        self.miniArtworkImageView.contentMode = .scaleAspectFill
        self.miniArtworkImageView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.miniPlayerBlurView.contentView.addSubview(self.miniArtworkImageView)
        
        self.miniTitleLabel.font = UIFont.systemFont(ofSize: 13.5, weight: .semibold)
        self.miniTitleLabel.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.miniPlayerBlurView.contentView.addSubview(self.miniTitleLabel)
        
        self.miniArtistLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        self.miniArtistLabel.textColor = self.presentationData.theme.list.itemSecondaryTextColor
        self.miniPlayerBlurView.contentView.addSubview(self.miniArtistLabel)
        
        self.miniPlayPauseButton.tintColor = self.presentationData.theme.list.itemAccentColor
        self.miniPlayPauseButton.addTarget(self, action: #selector(self.miniPlayPausePressed), for: .touchUpInside)
        self.miniPlayerBlurView.contentView.addSubview(self.miniPlayPauseButton)
        
        let nextConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        self.miniNextButton.setImage(UIImage(systemName: "forward.fill", withConfiguration: nextConfig), for: .normal)
        self.miniNextButton.tintColor = self.presentationData.theme.list.itemSecondaryTextColor
        self.miniNextButton.addTarget(self, action: #selector(self.miniNextPressed), for: .touchUpInside)
        self.miniPlayerBlurView.contentView.addSubview(self.miniNextButton)
        
        self.miniProgressView.progressTintColor = self.presentationData.theme.list.itemAccentColor
        self.miniProgressView.trackTintColor = UIColor.white.withAlphaComponent(0.12)
        self.miniPlayerBlurView.contentView.addSubview(self.miniProgressView)
        
        self.view.addSubview(self.miniPlayerContainer)
        self.updateMiniPlayer()
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let navHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bounds = CGRect(origin: .zero, size: layout.size)
        
        self.searchBar.frame = CGRect(x: 8, y: navHeight + 4, width: bounds.width - 16, height: 44)
        
        let miniPlayerHeight: CGFloat = SGDoxMusicManager.shared.currentTrack != nil ? 56.0 : 0.0
        let miniPlayerY = bounds.height - layout.intrinsicInsets.bottom - miniPlayerHeight - 8
        
        self.miniPlayerContainer.frame = CGRect(x: 16, y: miniPlayerY, width: bounds.width - 32, height: miniPlayerHeight)
        self.miniPlayerBlurView.frame = self.miniPlayerContainer.bounds
        self.miniGlossLayer.frame = CGRect(x: 0, y: 0, width: self.miniPlayerBlurView.bounds.width, height: 26)
        self.miniPlayerContainer.isHidden = miniPlayerHeight == 0
        
        let artSide: CGFloat = 40.0
        self.miniArtworkImageView.frame = CGRect(x: 8, y: (miniPlayerHeight - artSide) * 0.5, width: artSide, height: artSide)
        self.miniPlayPauseButton.frame = CGRect(x: self.miniPlayerBlurView.bounds.width - 76, y: (miniPlayerHeight - 36) * 0.5, width: 34, height: 36)
        self.miniNextButton.frame = CGRect(x: self.miniPlayerBlurView.bounds.width - 38, y: (miniPlayerHeight - 36) * 0.5, width: 32, height: 36)
        
        let textX = self.miniArtworkImageView.frame.maxX + 10
        let textWidth = max(0, self.miniPlayPauseButton.frame.minX - textX - 8)
        self.miniTitleLabel.frame = CGRect(x: textX, y: (miniPlayerHeight - 34) * 0.5, width: textWidth, height: 18)
        self.miniArtistLabel.frame = CGRect(x: textX, y: (miniPlayerHeight - 34) * 0.5 + 18, width: textWidth, height: 15)
        self.miniProgressView.frame = CGRect(x: 16, y: self.miniPlayerBlurView.bounds.height - 2, width: self.miniPlayerBlurView.bounds.width - 32, height: 2)
        
        let tableY = self.searchBar.frame.maxY + 4
        self.tableView.frame = CGRect(x: 0, y: tableY, width: bounds.width, height: max(0, bounds.height - tableY))
        
        let bottomContentInset = layout.intrinsicInsets.bottom + (miniPlayerHeight > 0 ? (miniPlayerHeight + 16) : 16)
        self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomContentInset, right: 0)
        self.tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: layout.intrinsicInsets.bottom + (miniPlayerHeight > 0 ? (miniPlayerHeight + 8) : 0), right: 0)
    }
    
    private func updateMiniPlayer() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else {
            self.miniPlayerContainer.isHidden = true
            return
        }
        
        self.miniPlayerContainer.isHidden = false
        self.view.bringSubviewToFront(self.miniPlayerContainer)
        self.miniTitleLabel.text = track.title
        self.miniArtistLabel.text = track.artist
        
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        let iconName = manager.isPlaying ? "pause.fill" : "play.fill"
        self.miniPlayPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        
        self.miniArtworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
        SGDoxImageLoader.shared.loadArtwork(for: track, targetSize: CGSize(width: 80, height: 80)) { [weak self] image in
            if let image = image {
                self?.miniArtworkImageView.image = image
            }
        }
    }
    
    private func loadDefaultRecommendations() {
        if !SGDoxMusicManager.shared.history.isEmpty {
            let historyDeduped = AppleMusicService.deduplicateTracks(Array(SGDoxMusicManager.shared.history.suffix(20).reversed()))
            self.searchResults = historyDeduped
            self.tableView.reloadData()
            return
        }
        
        if AppleMusicService.shared.isAuthorized {
            AppleMusicService.shared.fetchUserPersonalMusic { [weak self] tracks in
                let deduped = AppleMusicService.deduplicateTracks(tracks)
                DispatchQueue.main.async {
                    self?.searchResults = deduped
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
        self.searchTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.performSearch(query: trimmed)
        }
    }
    
    private func performSearch(query: String) {
        if SpotifyService.shared.isAuthorized && !AppleMusicService.shared.isAuthorized {
            SpotifyService.shared.search(query: query) { [weak self] tracks, _ in
                let deduped = AppleMusicService.deduplicateTracks(tracks)
                DispatchQueue.main.async {
                    self?.searchResults = deduped
                    self?.tableView.reloadData()
                }
            }
        } else {
            AppleMusicService.shared.search(query: query) { [weak self] appleTracks, _ in
                let appleDeduped = AppleMusicService.deduplicateTracks(appleTracks)
                DispatchQueue.main.async {
                    if !appleDeduped.isEmpty {
                        self?.searchResults = appleDeduped
                        self?.tableView.reloadData()
                    } else if SpotifyService.shared.isAuthorized {
                        SpotifyService.shared.search(query: query) { spotifyTracks, _ in
                            let spotifyDeduped = AppleMusicService.deduplicateTracks(spotifyTracks)
                            DispatchQueue.main.async {
                                self?.searchResults = spotifyDeduped
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
            if indexPath.section == 0 {
                return 54.0
            }
            if indexPath.section == 1 {
                return 82.0
            }
            if self.hasFavorites && indexPath.section == 2 && indexPath.row == 0 {
                return 96.0
            }
        }
        return 58.0
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
            cell.chevronImageView.tintColor = theme.list.disclosureArrowColor
            cell.separatorView.backgroundColor = theme.list.itemBlocksSeparatorColor
            cell.separatorView.isHidden = indexPath.row == 2
            
            if indexPath.row == 0 {
                // Apple Music
                cell.iconContainer.backgroundColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
                cell.iconImageView.image = UIImage(systemName: "music.note")
                cell.titleLabel.text = "Apple Music"
                let isAuth = AppleMusicService.shared.isAuthorized
                cell.statusLabel.text = isAuth ? "Подключено (вся медиатека)" : "Нажмите для подключения"
                cell.statusLabel.textColor = isAuth ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor
            } else if indexPath.row == 1 {
                // Spotify
                cell.iconContainer.backgroundColor = UIColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1.0)
                cell.iconImageView.image = UIImage(systemName: "waveform")
                cell.titleLabel.text = "Spotify"
                let isAuth = SpotifyService.shared.isAuthorized
                cell.statusLabel.text = isAuth ? "Подключено к аккаунту" : (SpotifyService.shared.hasCustomClientId ? "Client ID настроен" : "Нажмите для настройки")
                cell.statusLabel.textColor = isAuth ? theme.list.itemAccentColor : theme.list.itemSecondaryTextColor
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
                cell.backgroundColor = theme.list.itemBlocksBackgroundColor
                cell.contentView.backgroundColor = theme.list.itemBlocksBackgroundColor
                cell.titleLabel.textColor = theme.list.itemPrimaryTextColor
                cell.countLabel.textColor = theme.list.itemSecondaryTextColor
                cell.separatorView.backgroundColor = theme.list.itemBlocksSeparatorColor
                
                let count = SGDoxMusicManager.shared.favorites.count
                cell.countLabel.text = "\(count) трек\(self.pluralEnding(count)) • Синхронизировано"
                
                cell.playAllButton.backgroundColor = theme.list.itemAccentColor
                cell.playAllButton.tintColor = .white
                cell.shuffleButton.backgroundColor = theme.list.itemAccentColor.withAlphaComponent(0.12)
                cell.shuffleButton.tintColor = theme.list.itemAccentColor
                
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
        let isCurrent = SGDoxMusicManager.shared.currentTrack?.id == track.id
        let isPlaying = isCurrent && SGDoxMusicManager.shared.isPlaying
        
        cell.backgroundColor = theme.list.itemBlocksBackgroundColor
        cell.titleLabel.text = track.title
        cell.titleLabel.textColor = isCurrent ? theme.list.itemAccentColor : theme.list.itemPrimaryTextColor
        cell.artistLabel.text = track.artist
        cell.artistLabel.textColor = theme.list.itemSecondaryTextColor
        cell.separatorView.backgroundColor = theme.list.itemBlocksSeparatorColor
        cell.separatorView.isHidden = isLast
        
        cell.playingIndicator.isHidden = !isPlaying
        cell.playingIndicator.tintColor = theme.list.itemAccentColor
        
        let isFav = SGDoxMusicManager.shared.isFavorite(track: track)
        let heartConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let heartIcon = isFav ? "suit.heart.fill" : "suit.heart"
        cell.likeButton.setImage(UIImage(systemName: heartIcon, withConfiguration: heartConfig), for: .normal)
        cell.likeButton.tintColor = isFav ? UIColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1.0) : theme.list.itemSecondaryTextColor.withAlphaComponent(0.4)
        cell.onLikeTapped = { [weak self, weak cell] in
            guard let cell = cell else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            SGDoxMusicManager.shared.toggleFavorite(track: track)
            
            UIView.animate(withDuration: 0.12, animations: {
                cell.likeButton.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
            }) { _ in
                UIView.animate(withDuration: 0.12) {
                    cell.likeButton.transform = .identity
                }
            }
            self?.tableView.reloadData()
        }
        
        cell.currentTrackId = track.id
        cell.artworkView.image = SGDoxImageLoader.shared.placeholderArtwork()
        SGDoxImageLoader.shared.loadArtwork(for: track, targetSize: CGSize(width: 88, height: 88)) { [weak cell] image in
            if cell?.currentTrackId == track.id, let image = image {
                cell?.artworkView.image = image
            }
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
    
    @objc private func miniNextPressed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.next()
    }
    
    @objc private func miniPlayerTapped() {
        self.openPlayer()
    }
    
    private func openPlayer() {
        let playerController = SGDoxMusicPlayerController(context: self.context)
        playerController.navigationPresentation = .modal
        self.push(playerController)
    }
}
