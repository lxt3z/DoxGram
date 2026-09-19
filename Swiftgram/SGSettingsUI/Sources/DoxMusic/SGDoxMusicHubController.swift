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

public final class SGDoxMusicHubController: ViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    // Liquid Glass UI components
    private let backgroundGradientLayer = CAGradientLayer()
    private let backgroundBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    
    private let searchContainerView = UIView()
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    
    private let miniPlayerContainer = UIView()
    private let miniPlayerBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let miniArtworkImageView = UIImageView()
    private let miniTitleLabel = UILabel()
    private let miniArtistLabel = UILabel()
    private let miniPlayPauseButton = UIButton(type: .system)
    private let miniProgressView = UIProgressView(progressViewStyle: .default)
    
    private var searchResults: [SGDoxMusicTrack] = []
    private var isSearching = false
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "DoxMusic"
        self.statusBar.statusBarStyle = .White
        self.ready.set(.single(true))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 1.0)
        
        self.setupBackground()
        self.setupSearchBar()
        self.setupTableView()
        self.setupMiniPlayer()
        
        SGDoxMusicManager.shared.addStateListener { [weak self] in
            self?.updateMiniPlayer()
        }
        
        DiscordRPCService.shared.onStatusChanged = { [weak self] _ in
            self?.tableView.reloadData()
        }
        
        if self.searchResults.isEmpty {
            self.loadDefaultRecommendations()
        }
    }
    
    private func setupBackground() {
        self.backgroundGradientLayer.colors = [
            UIColor(red: 0.08, green: 0.09, blue: 0.18, alpha: 1.0).cgColor,
            UIColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1.0).cgColor,
            UIColor(red: 0.10, green: 0.04, blue: 0.14, alpha: 1.0).cgColor
        ]
        self.backgroundGradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.backgroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.view.layer.insertSublayer(self.backgroundGradientLayer, at: 0)
        
        self.backgroundBlurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.backgroundBlurView.alpha = 0.85
        self.view.insertSubview(self.backgroundBlurView, at: 1)
    }
    
    private func setupSearchBar() {
        self.searchContainerView.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.searchContainerView.layer.cornerRadius = 16
        self.searchContainerView.layer.borderWidth = 1.0
        self.searchContainerView.layer.borderColor = UIColor(white: 1.0, alpha: 0.15).cgColor
        self.searchContainerView.clipsToBounds = true
        self.view.addSubview(self.searchContainerView)
        
        self.searchBar.delegate = self
        self.searchBar.placeholder = "Поиск в Apple Music и Spotify..."
        self.searchBar.searchBarStyle = .minimal
        self.searchBar.tintColor = .white
        
        if let textField = self.searchBar.value(forKey: "searchField") as? UITextField {
            textField.textColor = .white
            textField.tintColor = .white
            textField.backgroundColor = .clear
            let placeholderColor = UIColor(white: 1.0, alpha: 0.5)
            textField.attributedPlaceholder = NSAttributedString(
                string: "Поиск в Apple Music и Spotify...",
                attributes: [.foregroundColor: placeholderColor]
            )
            if let leftView = textField.leftView as? UIImageView {
                leftView.tintColor = UIColor(white: 1.0, alpha: 0.7)
            }
        }
        self.searchContainerView.addSubview(self.searchBar)
    }
    
    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.showsVerticalScrollIndicator = false
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TrackCell")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ServiceCell")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WaveHeroCell")
        self.view.addSubview(self.tableView)
    }
    
    private func setupMiniPlayer() {
        self.miniPlayerContainer.backgroundColor = .clear
        self.miniPlayerContainer.layer.shadowColor = UIColor.black.cgColor
        self.miniPlayerContainer.layer.shadowOpacity = 0.4
        self.miniPlayerContainer.layer.shadowRadius = 14
        self.miniPlayerContainer.layer.shadowOffset = CGSize(width: 0, height: 6)
        
        self.miniPlayerBlurView.layer.cornerRadius = 24
        self.miniPlayerBlurView.layer.borderWidth = 1.0
        self.miniPlayerBlurView.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        self.miniPlayerBlurView.clipsToBounds = true
        self.miniPlayerContainer.addSubview(self.miniPlayerBlurView)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.miniPlayerTapped))
        self.miniPlayerContainer.addGestureRecognizer(tap)
        
        self.miniArtworkImageView.layer.cornerRadius = 10
        self.miniArtworkImageView.clipsToBounds = true
        self.miniArtworkImageView.contentMode = .scaleAspectFill
        self.miniArtworkImageView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.miniPlayerBlurView.contentView.addSubview(self.miniArtworkImageView)
        
        self.miniTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        self.miniTitleLabel.textColor = .white
        self.miniPlayerBlurView.contentView.addSubview(self.miniTitleLabel)
        
        self.miniArtistLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        self.miniArtistLabel.textColor = UIColor(white: 1.0, alpha: 0.65)
        self.miniPlayerBlurView.contentView.addSubview(self.miniArtistLabel)
        
        self.miniPlayPauseButton.tintColor = .white
        self.miniPlayPauseButton.addTarget(self, action: #selector(self.miniPlayPausePressed), for: .touchUpInside)
        self.miniPlayerBlurView.contentView.addSubview(self.miniPlayPauseButton)
        
        self.miniProgressView.progressTintColor = UIColor(red: 0.95, green: 0.25, blue: 0.6, alpha: 0.9)
        self.miniProgressView.trackTintColor = UIColor(white: 1.0, alpha: 0.15)
        self.miniPlayerBlurView.contentView.addSubview(self.miniProgressView)
        
        self.view.addSubview(self.miniPlayerContainer)
        self.updateMiniPlayer()
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let navHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bounds = CGRect(origin: .zero, size: layout.size)
        
        self.backgroundGradientLayer.frame = bounds
        self.backgroundBlurView.frame = bounds
        
        let searchY = navHeight + 8
        self.searchContainerView.frame = CGRect(x: 16, y: searchY, width: bounds.width - 32, height: 44)
        self.searchBar.frame = self.searchContainerView.bounds
        
        let miniPlayerHeight: CGFloat = SGDoxMusicManager.shared.currentTrack != nil ? 64.0 : 0.0
        let miniPlayerY = bounds.height - layout.intrinsicInsets.bottom - miniPlayerHeight - 12
        
        self.miniPlayerContainer.frame = CGRect(x: 16, y: miniPlayerY, width: bounds.width - 32, height: miniPlayerHeight)
        self.miniPlayerBlurView.frame = self.miniPlayerContainer.bounds
        self.miniPlayerContainer.isHidden = miniPlayerHeight == 0
        
        self.miniArtworkImageView.frame = CGRect(x: 12, y: 10, width: 44, height: 44)
        self.miniPlayPauseButton.frame = CGRect(x: self.miniPlayerBlurView.bounds.width - 52, y: 12, width: 40, height: 40)
        
        let labelWidth = self.miniPlayerBlurView.bounds.width - 120
        self.miniTitleLabel.frame = CGRect(x: 66, y: 13, width: labelWidth, height: 18)
        self.miniArtistLabel.frame = CGRect(x: 66, y: 32, width: labelWidth, height: 16)
        self.miniProgressView.frame = CGRect(x: 0, y: self.miniPlayerBlurView.bounds.height - 3, width: self.miniPlayerBlurView.bounds.width, height: 3)
        
        let tableY = self.searchContainerView.frame.maxY + 10
        let tableBottom = self.miniPlayerContainer.isHidden ? (bounds.height - layout.intrinsicInsets.bottom) : miniPlayerY
        let tableHeight = max(0, tableBottom - tableY)
        self.tableView.frame = CGRect(x: 0, y: tableY, width: bounds.width, height: tableHeight)
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = self.currentlyAppliedLayout {
            self.containerLayoutUpdated(layout, transition: .immediate)
        }
    }
    
    private func updateMiniPlayer() {
        let manager = SGDoxMusicManager.shared
        guard let track = manager.currentTrack else {
            self.miniPlayerContainer.isHidden = true
            self.view.setNeedsLayout()
            return
        }
        
        self.miniPlayerContainer.isHidden = false
        self.miniTitleLabel.text = track.title
        self.miniArtistLabel.text = track.artist
        
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        let iconName = manager.isPlaying ? "pause.circle.fill" : "play.circle.fill"
        self.miniPlayPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        
        let duration = manager.duration > 0 ? manager.duration : 30.0
        let progress = Float(manager.currentTime / duration)
        self.miniProgressView.setProgress(progress, animated: true)
        
        if let artwork = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artwork, targetSize: CGSize(width: 44, height: 44)) { [weak self] image in
                self?.miniArtworkImageView.image = image
            }
        } else {
            self.miniArtworkImageView.image = UIImage(bundleImageName: "Media Editor/SmallAudio")
        }
        
        self.view.setNeedsLayout()
    }
    
    private func loadDefaultRecommendations() {
        if SpotifyService.shared.isAuthorized {
            SpotifyService.shared.fetchWaveTracks(basedOn: nil) { [weak self] tracks in
                DispatchQueue.main.async {
                    self?.searchResults = tracks
                    self?.tableView.reloadData()
                }
            }
        } else {
            AppleMusicService.shared.fetchWaveTracks(basedOn: nil) { [weak self] tracks in
                DispatchQueue.main.async {
                    self?.searchResults = tracks
                    self?.tableView.reloadData()
                }
            }
        }
    }
    
    // MARK: - Search
    
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            self.isSearching = false
            self.loadDefaultRecommendations()
            return
        }
        
        self.isSearching = true
        if SpotifyService.shared.isAuthorized {
            SpotifyService.shared.search(query: query) { [weak self] tracks, _ in
                DispatchQueue.main.async {
                    if !tracks.isEmpty {
                        self?.searchResults = tracks
                        self?.tableView.reloadData()
                    } else {
                        // Fallback to Apple Music catalog
                        AppleMusicService.shared.search(query: query) { appleTracks, _ in
                            DispatchQueue.main.async {
                                self?.searchResults = appleTracks
                                self?.tableView.reloadData()
                            }
                        }
                    }
                }
            }
        } else {
            AppleMusicService.shared.search(query: query) { [weak self] tracks, _ in
                DispatchQueue.main.async {
                    self?.searchResults = tracks
                    self?.tableView.reloadData()
                }
            }
        }
    }
    
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    // MARK: - TableView
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return self.isSearching ? 1 : 3
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if self.isSearching {
            return self.searchResults.count
        }
        switch section {
        case 0: return 3
        case 1: return 1
        case 2: return self.searchResults.count
        default: return 0
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if !self.isSearching && indexPath.section == 1 {
            return 96.0
        }
        return 72.0
    }
    
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title: String
        if self.isSearching {
            title = "РЕЗУЛЬТАТЫ ПОИСКА"
        } else {
            switch section {
            case 0: title = "ИНТЕГРАЦИИ И АККАУНТЫ"
            case 1: title = "ПЕРСОНАЛЬНЫЙ МИКС"
            case 2: title = "РЕКОМЕНДАЦИИ И ТРЕКИ"
            default: return nil
            }
        }
        
        let headerView = UIView()
        headerView.backgroundColor = .clear
        let label = UILabel(frame: CGRect(x: 20, y: 8, width: 300, height: 20))
        label.text = title
        label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        label.textColor = UIColor(white: 1.0, alpha: 0.5)
        headerView.addSubview(label)
        return headerView
    }
    
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 34.0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if !self.isSearching && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ServiceCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            
            let card = UIView(frame: CGRect(x: 16, y: 4, width: tableView.bounds.width - 32, height: 64))
            card.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
            card.layer.cornerRadius = 16
            card.layer.borderWidth = 1.0
            card.layer.borderColor = UIColor(white: 1.0, alpha: 0.12).cgColor
            card.clipsToBounds = true
            
            let iconBox = UIView(frame: CGRect(x: 12, y: 12, width: 40, height: 40))
            iconBox.layer.cornerRadius = 10
            iconBox.clipsToBounds = true
            
            let iconImageView = UIImageView(frame: CGRect(x: 8, y: 8, width: 24, height: 24))
            iconImageView.tintColor = .white
            iconImageView.contentMode = .scaleAspectFit
            iconBox.addSubview(iconImageView)
            card.addSubview(iconBox)
            
            let titleLabel = UILabel(frame: CGRect(x: 64, y: 13, width: card.bounds.width - 130, height: 20))
            titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
            titleLabel.textColor = .white
            card.addSubview(titleLabel)
            
            let statusLabel = UILabel(frame: CGRect(x: 64, y: 33, width: card.bounds.width - 130, height: 16))
            statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            card.addSubview(statusLabel)
            
            let badge = UILabel(frame: CGRect(x: card.bounds.width - 86, y: 18, width: 74, height: 28))
            badge.layer.cornerRadius = 14
            badge.clipsToBounds = true
            badge.textAlignment = .center
            badge.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            card.addSubview(badge)
            
            if indexPath.row == 0 {
                // Apple Music
                iconBox.backgroundColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0)
                iconImageView.image = UIImage(systemName: "music.note")
                titleLabel.text = "Apple Music"
                let isAuth = AppleMusicService.shared.isAuthorized
                statusLabel.text = isAuth ? "Доступ к медиатеке разрешен" : "Нажмите для подключения"
                statusLabel.textColor = isAuth ? UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.9) : UIColor(white: 1.0, alpha: 0.5)
                badge.text = isAuth ? "Вкл" : "Войти"
                badge.backgroundColor = isAuth ? UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.25) : UIColor(white: 1.0, alpha: 0.15)
                badge.textColor = isAuth ? UIColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0) : .white
            } else if indexPath.row == 1 {
                // Spotify
                iconBox.backgroundColor = UIColor(red: 0.11, green: 0.73, blue: 0.33, alpha: 1.0)
                iconImageView.image = UIImage(systemName: "waveform")
                titleLabel.text = "Spotify"
                let isAuth = SpotifyService.shared.isAuthorized
                statusLabel.text = isAuth ? "Аккаунт подключен" : (SpotifyService.shared.hasCustomClientId ? "Client ID настроен" : "Нажмите для настройки входа")
                statusLabel.textColor = isAuth ? UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.9) : UIColor(white: 1.0, alpha: 0.5)
                badge.text = isAuth ? "Вкл" : "Вход"
                badge.backgroundColor = isAuth ? UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.25) : UIColor(white: 1.0, alpha: 0.15)
                badge.textColor = isAuth ? UIColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0) : .white
            } else {
                // Discord RPC
                iconBox.backgroundColor = UIColor(red: 0.35, green: 0.40, blue: 0.95, alpha: 1.0)
                iconImageView.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")
                titleLabel.text = "Discord RPC"
                let isEnabled = SGSimpleSettings.shared.discordRpcEnabled && !SGSimpleSettings.shared.discordRpcToken.isEmpty
                switch DiscordRPCService.shared.status {
                case .connected(let username):
                    statusLabel.text = "В сети: \(username)"
                    statusLabel.textColor = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 0.9)
                case .connecting:
                    statusLabel.text = "Подключение..."
                    statusLabel.textColor = UIColor(red: 0.9, green: 0.7, blue: 0.2, alpha: 0.9)
                case .error:
                    statusLabel.text = "Ошибка токена"
                    statusLabel.textColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 0.9)
                case .disconnected:
                    statusLabel.text = isEnabled ? "Включен" : "Настроить User Token"
                    statusLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
                }
                badge.text = isEnabled ? "Вкл" : "Токен"
                badge.backgroundColor = isEnabled ? UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 0.25) : UIColor(white: 1.0, alpha: 0.15)
                badge.textColor = isEnabled ? UIColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1.0) : .white
            }
            
            cell.contentView.addSubview(card)
            return cell
        }
        
        if !self.isSearching && indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "WaveHeroCell", for: indexPath)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            
            let card = UIView(frame: CGRect(x: 16, y: 4, width: tableView.bounds.width - 32, height: 88))
            card.layer.cornerRadius = 20
            card.clipsToBounds = true
            
            let gradient = CAGradientLayer()
            gradient.frame = card.bounds
            gradient.colors = [
                UIColor(red: 0.95, green: 0.15, blue: 0.55, alpha: 0.95).cgColor,
                UIColor(red: 0.50, green: 0.12, blue: 0.95, alpha: 0.95).cgColor,
                UIColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 0.90).cgColor
            ]
            gradient.startPoint = CGPoint(x: 0.0, y: 0.0)
            gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
            card.layer.insertSublayer(gradient, at: 0)
            
            card.layer.borderWidth = 1.0
            card.layer.borderColor = UIColor(white: 1.0, alpha: 0.35).cgColor
            
            let waveIcon = UIImageView(frame: CGRect(x: 18, y: 24, width: 40, height: 40))
            waveIcon.image = UIImage(systemName: "dot.radiowaves.left.and.right")
            waveIcon.tintColor = .white
            waveIcon.contentMode = .scaleAspectFit
            card.addSubview(waveIcon)
            
            let titleLabel = UILabel(frame: CGRect(x: 68, y: 20, width: card.bounds.width - 130, height: 24))
            titleLabel.text = "⚡ Запустить «Мою волну»"
            titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .heavy)
            titleLabel.textColor = .white
            card.addSubview(titleLabel)
            
            let descLabel = UILabel(frame: CGRect(x: 68, y: 44, width: card.bounds.width - 130, height: 20))
            descLabel.text = "Умный бесконечный поток музыки"
            descLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            descLabel.textColor = UIColor(white: 1.0, alpha: 0.85)
            card.addSubview(descLabel)
            
            let playPill = UIView(frame: CGRect(x: card.bounds.width - 56, y: 26, width: 36, height: 36))
            playPill.backgroundColor = UIColor(white: 1.0, alpha: 0.25)
            playPill.layer.cornerRadius = 18
            let playIcon = UIImageView(frame: CGRect(x: 10, y: 9, width: 18, height: 18))
            playIcon.image = UIImage(systemName: "play.fill")
            playIcon.tintColor = .white
            playPill.addSubview(playIcon)
            card.addSubview(playPill)
            
            cell.contentView.addSubview(card)
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "TrackCell", for: indexPath)
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        
        guard indexPath.row < self.searchResults.count else { return cell }
        let track = self.searchResults[indexPath.row]
        
        let card = UIView(frame: CGRect(x: 16, y: 4, width: tableView.bounds.width - 32, height: 64))
        card.backgroundColor = UIColor(white: 1.0, alpha: 0.06)
        card.layer.cornerRadius = 14
        card.layer.borderWidth = 1.0
        card.layer.borderColor = UIColor(white: 1.0, alpha: 0.09).cgColor
        card.clipsToBounds = true
        
        let artworkView = UIImageView(frame: CGRect(x: 10, y: 10, width: 44, height: 44))
        artworkView.layer.cornerRadius = 8
        artworkView.clipsToBounds = true
        artworkView.contentMode = .scaleAspectFill
        artworkView.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        card.addSubview(artworkView)
        
        if let artwork = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artwork, targetSize: CGSize(width: 44, height: 44)) { [weak artworkView] image in
                artworkView?.image = image
            }
        } else {
            artworkView.image = UIImage(bundleImageName: "Media Editor/SmallAudio")
        }
        
        let titleLabel = UILabel(frame: CGRect(x: 64, y: 13, width: card.bounds.width - 120, height: 20))
        titleLabel.text = track.title
        titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        card.addSubview(titleLabel)
        
        let subtitleLabel = UILabel(frame: CGRect(x: 64, y: 33, width: card.bounds.width - 120, height: 16))
        subtitleLabel.text = "\(track.artist) • \(track.source.rawValue)"
        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        card.addSubview(subtitleLabel)
        
        let playButton = UIImageView(frame: CGRect(x: card.bounds.width - 42, y: 20, width: 24, height: 24))
        playButton.image = UIImage(systemName: "play.circle.fill")
        playButton.tintColor = UIColor(white: 1.0, alpha: 0.7)
        card.addSubview(playButton)
        
        cell.contentView.addSubview(card)
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if !self.isSearching && indexPath.section == 0 {
            if indexPath.row == 0 {
                // Apple Music authorization
                AppleMusicService.shared.requestAuthorization { [weak self] _ in
                    DispatchQueue.main.async { self?.tableView.reloadData() }
                }
            } else if indexPath.row == 1 {
                // Spotify Configuration Dialog
                self.presentSpotifyMenu()
            } else {
                // Discord RPC dialog
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
        
        guard indexPath.row < self.searchResults.count else { return }
        let track = self.searchResults[indexPath.row]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SGDoxMusicManager.shared.play(track: track, queue: self.searchResults)
        self.openPlayer()
    }
    
    // MARK: - Spotify & Discord Dialogs
    
    private func presentSpotifyMenu() {
        let isAuth = SpotifyService.shared.isAuthorized
        let alert = UIAlertController(
            title: "Spotify",
            message: isAuth ? "Spotify подключен к вашему аккаунту." : "Выберите способ входа в Spotify:",
            preferredStyle: .actionSheet
        )
        
        if isAuth {
            alert.addAction(UIAlertAction(title: "Выйти из Spotify", style: .destructive, handler: { [weak self] _ in
                SpotifyService.shared.logout()
                self?.tableView.reloadData()
            }))
        } else {
            alert.addAction(UIAlertAction(title: "Войти через OAuth (Браузер)", style: .default, handler: { [weak self] _ in
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
            
            alert.addAction(UIAlertAction(title: "Ввести Spotify Client ID", style: .default, handler: { [weak self] _ in
                self?.presentSpotifyClientIdInput(promptBeforeOAuth: false)
            }))
            
            alert.addAction(UIAlertAction(title: "Вставить Access Token напрямую", style: .default, handler: { [weak self] _ in
                self?.presentSpotifyTokenInput()
            }))
        }
        
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        self.context.sharedContext.applicationBindings.presentNativeController(alert)
    }
    
    private func presentSpotifyClientIdInput(promptBeforeOAuth: Bool) {
        let alert = UIAlertController(
            title: "Spotify Client ID",
            message: "Создайте приложение на developer.spotify.com, добавьте Redirect URI tg://spotify-callback и вставьте Client ID сюда:",
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
            message: "Вставьте действующий Bearer Access Token аккаунта Spotify:",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "BQB... / Access Token"
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
            message: "Введите User Token от Discord для отображения музыки в статусе профиля:",
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
