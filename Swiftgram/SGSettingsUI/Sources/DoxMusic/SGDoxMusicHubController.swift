import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import SGSimpleSettings

public final class SGDoxMusicHubController: ViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let miniPlayerView = UIView()
    private let miniArtworkImageView = UIImageView()
    private let miniTitleLabel = UILabel()
    private let miniPlayPauseButton = UIButton(type: .system)
    
    private var searchResults: [SGDoxMusicTrack] = []
    private var isSearching = false
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = "DoxMusic"
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        
        self.setupSearchBar()
        self.setupTableView()
        self.setupMiniPlayer()
        
        SGDoxMusicManager.shared.addStateListener { [weak self] in
            self?.updateMiniPlayer()
        }
        
        DiscordRPCService.shared.onStatusChanged = { [weak self] _ in
            self?.tableView.reloadData()
        }
        
        // Load initial wave tracks if empty
        if self.searchResults.isEmpty {
            self.loadDefaultRecommendations()
        }
    }
    
    private func setupSearchBar() {
        self.searchBar.delegate = self
        self.searchBar.placeholder = "Поиск в Apple Music и Spotify..."
        self.searchBar.searchBarStyle = .minimal
        self.view.addSubview(self.searchBar)
    }
    
    private func setupTableView() {
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.backgroundColor = .clear
        self.tableView.separatorColor = self.presentationData.theme.list.itemPlainSeparatorColor
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TrackCell")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ServiceCell")
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "WaveHeroCell")
        self.view.addSubview(self.tableView)
    }
    
    private func setupMiniPlayer() {
        self.miniPlayerView.backgroundColor = self.presentationData.theme.rootController.tabBar.backgroundColor
        self.miniPlayerView.layer.shadowColor = UIColor.black.cgColor
        self.miniPlayerView.layer.shadowOpacity = 0.15
        self.miniPlayerView.layer.shadowRadius = 8
        self.miniPlayerView.layer.cornerRadius = 14
        self.miniPlayerView.clipsToBounds = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.miniPlayerTapped))
        self.miniPlayerView.addGestureRecognizer(tap)
        
        self.miniArtworkImageView.layer.cornerRadius = 6
        self.miniArtworkImageView.clipsToBounds = true
        self.miniArtworkImageView.contentMode = .scaleAspectFill
        self.miniArtworkImageView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.miniPlayerView.addSubview(self.miniArtworkImageView)
        
        self.miniTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.miniTitleLabel.textColor = self.presentationData.theme.list.itemPrimaryTextColor
        self.miniPlayerView.addSubview(self.miniTitleLabel)
        
        self.miniPlayPauseButton.tintColor = self.presentationData.theme.list.itemAccentColor
        self.miniPlayPauseButton.addTarget(self, action: #selector(self.miniPlayPausePressed), for: .touchUpInside)
        self.miniPlayerView.addSubview(self.miniPlayPauseButton)
        
        self.view.addSubview(self.miniPlayerView)
        self.updateMiniPlayer()
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        let navHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        let bounds = CGRect(origin: .zero, size: layout.size)
        
        self.searchBar.frame = CGRect(x: 8, y: navHeight + 4, width: bounds.width - 16, height: 48)
        
        let miniPlayerHeight: CGFloat = SGDoxMusicManager.shared.currentTrack != nil ? 56.0 : 0.0
        let miniPlayerY = bounds.height - layout.intrinsicInsets.bottom - miniPlayerHeight - 8
        
        self.miniPlayerView.frame = CGRect(x: 12, y: miniPlayerY, width: bounds.width - 24, height: miniPlayerHeight)
        self.miniPlayerView.isHidden = miniPlayerHeight == 0
        
        self.miniArtworkImageView.frame = CGRect(x: 8, y: 8, width: 40, height: 40)
        self.miniPlayPauseButton.frame = CGRect(x: self.miniPlayerView.bounds.width - 48, y: 8, width: 40, height: 40)
        self.miniTitleLabel.frame = CGRect(x: 56, y: 16, width: self.miniPlayerView.bounds.width - 110, height: 24)
        
        let tableY = self.searchBar.frame.maxY + 4
        let tableHeight = (self.miniPlayerView.isHidden ? bounds.height : miniPlayerY) - tableY
        self.tableView.frame = CGRect(x: 0, y: tableY, width: bounds.width, height: max(0, tableHeight))
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
            self.miniPlayerView.isHidden = true
            self.view.setNeedsLayout()
            return
        }
        
        self.miniPlayerView.isHidden = false
        self.miniTitleLabel.text = "\(track.title) — \(track.artist)"
        
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        let iconName = manager.isPlaying ? "pause.fill" : "play.fill"
        self.miniPlayPauseButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)
        
        if let artwork = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artwork, targetSize: CGSize(width: 40, height: 40)) { [weak self] image in
                self?.miniArtworkImageView.image = image
            }
        } else {
            self.miniArtworkImageView.image = nil
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
        guard !query.isEmpty else {
            self.isSearching = false
            self.loadDefaultRecommendations()
            return
        }
        self.isSearching = true
        
        // Search Apple Music
        AppleMusicService.shared.search(query: query) { [weak self] appleTracks, _ in
            // Search Spotify
            SpotifyService.shared.search(query: query) { [weak self] spotifyTracks, _ in
                DispatchQueue.main.async {
                    guard let self = self, self.isSearching else { return }
                    self.searchResults = appleTracks + spotifyTracks
                    self.tableView.reloadData()
                }
            }
        }
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
        case 0: return 3 // Services: Apple Music, Spotify, Discord RPC
        case 1: return 1 // Wave Hero Card
        case 2: return self.searchResults.count
        default: return 0
        }
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if self.isSearching {
            return "Результаты поиска"
        }
        switch section {
        case 0: return "Подключение аккаунтов и сервисов"
        case 1: return "Умный поток"
        case 2: return "Рекомендации"
        default: return nil
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if !self.isSearching && indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ServiceCell", for: indexPath)
            if indexPath.row == 0 {
                let isAuth = AppleMusicService.shared.isAuthorized
                cell.textLabel?.text = isAuth ? "Apple Music (Подключено)" : "Подключить Apple Music"
                cell.imageView?.image = UIImage(systemName: "applelogo")
                cell.accessoryType = isAuth ? .checkmark : .disclosureIndicator
            } else if indexPath.row == 1 {
                let isAuth = SpotifyService.shared.isAuthorized
                cell.textLabel?.text = isAuth ? "Spotify (Подключено)" : "Подключить Spotify"
                cell.imageView?.image = UIImage(systemName: "music.note")
                cell.accessoryType = isAuth ? .checkmark : .disclosureIndicator
            } else {
                let isEnabled = SGSimpleSettings.shared.discordRpcEnabled && !SGSimpleSettings.shared.discordRpcToken.isEmpty
                let statusText: String
                switch DiscordRPCService.shared.status {
                case .connected(let username):
                    statusText = "Discord RPC (\(username))"
                case .connecting:
                    statusText = "Discord RPC (Подключение...)"
                case .error:
                    statusText = "Discord RPC (Ошибка токена)"
                case .disconnected:
                    statusText = isEnabled ? "Discord RPC (Включен)" : "Настроить Discord RPC"
                }
                cell.textLabel?.text = statusText
                cell.imageView?.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")
                cell.accessoryType = isEnabled ? .checkmark : .disclosureIndicator
            }
            return cell
        }
        
        if !self.isSearching && indexPath.section == 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "WaveHeroCell", for: indexPath)
            cell.textLabel?.text = "⚡ Запустить «Мою волну»"
            cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
            cell.textLabel?.textColor = .systemPink
            cell.detailTextLabel?.text = "Бесконечный микс на основе ваших предпочтений"
            cell.imageView?.image = UIImage(systemName: "dot.radiowaves.left.and.right")
            cell.imageView?.tintColor = .systemPink
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "TrackCell", for: indexPath)
        let track = self.searchResults[indexPath.row]
        cell.textLabel?.text = track.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        cell.detailTextLabel?.text = "\(track.artist) • \(track.source.rawValue)"
        cell.imageView?.image = UIImage(systemName: "music.note")
        cell.imageView?.layer.cornerRadius = 6
        cell.imageView?.clipsToBounds = true
        if let artwork = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artwork, targetSize: CGSize(width: 44, height: 44)) { [weak cell] image in
                if let image = image {
                    cell?.imageView?.image = image
                    cell?.setNeedsLayout()
                }
            }
        }
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if !self.isSearching && indexPath.section == 0 {
            if indexPath.row == 0 {
                AppleMusicService.shared.requestAuthorization { [weak self] _ in
                    DispatchQueue.main.async { self?.tableView.reloadData() }
                }
            } else if indexPath.row == 1 {
                if SpotifyService.shared.isAuthorized {
                    SpotifyService.shared.logout()
                    self.tableView.reloadData()
                } else {
                    SpotifyService.shared.startAuthorization { [weak self] _, _ in
                        DispatchQueue.main.async { self?.tableView.reloadData() }
                    }
                }
            } else {
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
            return
        }
        
        if !self.isSearching && indexPath.section == 1 {
            SGDoxMusicManager.shared.startWave()
            self.openPlayer()
            return
        }
        
        let track = self.searchResults[indexPath.row]
        SGDoxMusicManager.shared.play(track: track, queue: self.searchResults)
        self.openPlayer()
    }
    
    // MARK: - MiniPlayer & Player Navigation
    
    @objc private func miniPlayPausePressed() {
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
