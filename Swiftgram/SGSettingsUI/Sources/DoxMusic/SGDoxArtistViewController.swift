import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import AppBundle

public final class SGDoxArtistViewController: ViewController, UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
    public let context: AccountContext
    public let artistName: String
    
    private var topTracks: [SGDoxMusicTrack] = []
    private var albums: [SGDoxAlbum] = []
    private var artistImageUrl: String?
    
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let grabber = UIView()
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let emptyStateLabel = UILabel()
    
    // Apple Music Hero Banner Header
    private let headerView = UIView()
    private let heroContainer = UIView()
    private let bannerImageView = UIImageView()
    private let bannerGradient = CAGradientLayer()
    private let verifiedBadge = UIImageView()
    private let nameLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let playAllButton = UIButton(type: .system)
    private let shuffleButton = UIButton(type: .system)
    private let albumsSectionLabel = UILabel()
    private var albumsCollectionView: UICollectionView!
    
    private let heroBannerHeight: CGFloat = 280.0
    private var panGesture: UIPanGestureRecognizer?
    
    public init(context: AccountContext, artistName: String) {
        self.context = context
        self.artistName = artistName
        super.init(navigationBarPresentationData: nil)
        self.navigationPresentation = .modal
        self.statusBar.statusBarStyle = .White
        self.ready.set(.single(true))
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadDisplayNode() {
        super.loadDisplayNode()
        self.displayNode.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Disable horizontal interactive pop to allow smooth album scrolling without dismissing
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    
    public override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.displayNode.frame = CGRect(origin: .zero, size: layout.size)
        self.view.frame = CGRect(origin: .zero, size: layout.size)
        self.blurView.frame = CGRect(origin: .zero, size: layout.size)
        
        let inNav = self.navigationController != nil
        self.grabber.isHidden = inNav
        
        let statusBarHeight = layout.statusBarHeight ?? layout.safeInsets.top
        let topInset: CGFloat = inNav ? (statusBarHeight + 44.0) : max(44.0, statusBarHeight + 14.0)
        
        self.grabber.frame = CGRect(x: (layout.size.width - 38) * 0.5, y: max(8, statusBarHeight - 22), width: 38, height: 5)
        
        // Close button: always accessible at top right with liquid glass styling
        let closeY = inNav ? statusBarHeight + 6.0 : max(8.0, statusBarHeight - 22.0)
        self.closeButton.frame = CGRect(x: layout.size.width - 48.0, y: closeY, width: 36.0, height: 36.0)
        self.closeButton.layer.cornerRadius = 18.0
        self.view.bringSubviewToFront(self.closeButton)
        
        self.tableView.frame = CGRect(x: 0, y: inNav ? topInset : 0, width: layout.size.width, height: layout.size.height - (inNav ? topInset : 0))
        self.layoutHeader(width: layout.size.width)
        
        // Fix loading indicator positioning: center inside visible content area
        self.activityIndicator.center = CGPoint(x: layout.size.width * 0.5, y: max(200.0, layout.size.height * 0.42))
        self.view.bringSubviewToFront(self.activityIndicator)
        
        let headerBottom = self.headerView.frame.maxY + (inNav ? topInset : 0)
        self.emptyStateLabel.frame = CGRect(x: 20.0, y: min(layout.size.height - 80.0, headerBottom + 30.0), width: layout.size.width - 40.0, height: 30.0)
        self.view.bringSubviewToFront(self.emptyStateLabel)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0)
        
        self.blurView.frame = self.view.bounds
        self.blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.blurView)
        
        // Grabber
        self.grabber.backgroundColor = UIColor(white: 1.0, alpha: 0.35)
        self.grabber.layer.cornerRadius = 2.5
        self.view.addSubview(self.grabber)
        
        // Glass Close button
        let closeConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: closeConfig), for: .normal)
        self.closeButton.tintColor = .white
        self.closeButton.backgroundColor = UIColor(white: 0.15, alpha: 0.65)
        self.closeButton.layer.borderWidth = 0.5
        self.closeButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.25).cgColor
        self.closeButton.clipsToBounds = true
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)
        
        // Table View
        self.tableView.backgroundColor = .clear
        self.tableView.separatorColor = UIColor(white: 1.0, alpha: 0.08)
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(ArtistTrackCell.self, forCellReuseIdentifier: "ArtistTrackCell")
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 60, right: 0)
        self.view.addSubview(self.tableView)
        
        // Setup Apple Music Header View
        self.setupHeaderView()
        
        // Activity Indicator
        self.activityIndicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        self.activityIndicator.color = .white
        self.activityIndicator.hidesWhenStopped = true
        self.view.addSubview(self.activityIndicator)
        self.activityIndicator.startAnimating()
        
        // Empty State Label
        self.emptyStateLabel.textColor = UIColor(white: 1.0, alpha: 0.55)
        self.emptyStateLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .medium)
        self.emptyStateLabel.textAlignment = .center
        self.emptyStateLabel.text = "Треки исполнителя не найдены"
        self.emptyStateLabel.isHidden = true
        self.view.addSubview(self.emptyStateLabel)
        
        // Pan gesture to allow smooth swipe-down to dismiss
        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanDismiss(_:)))
        pan.delegate = self
        self.view.addGestureRecognizer(pan)
        self.panGesture = pan
        
        self.loadArtistData()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.layoutHeader(width: self.view.bounds.width)
    }
    
    private func setupHeaderView() {
        self.headerView.clipsToBounds = false
        
        // Hero container
        self.heroContainer.clipsToBounds = true
        self.headerView.addSubview(self.heroContainer)
        
        // Banner Image View (Apple Music Style)
        self.bannerImageView.contentMode = .scaleAspectFill
        self.bannerImageView.clipsToBounds = true
        self.bannerImageView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        self.heroContainer.addSubview(self.bannerImageView)
        
        // Gradient overlay fading hero banner into dark background
        self.bannerGradient.colors = [
            UIColor.clear.cgColor,
            UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.40).cgColor,
            UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.90).cgColor,
            UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.00).cgColor
        ]
        self.bannerGradient.locations = [0.0, 0.45, 0.80, 1.0]
        self.bannerGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.bannerGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.heroContainer.layer.addSublayer(self.bannerGradient)
        
        // Verified Badge
        let badgeConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        self.verifiedBadge.image = UIImage(systemName: "checkmark.seal.fill", withConfiguration: badgeConfig)
        self.verifiedBadge.tintColor = UIColor(red: 0.18, green: 0.65, blue: 1.0, alpha: 1.0)
        self.verifiedBadge.contentMode = .scaleAspectFit
        self.headerView.addSubview(self.verifiedBadge)
        
        // Name Label (Apple Music Large Title)
        self.nameLabel.text = self.artistName
        self.nameLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        self.nameLabel.textColor = .white
        self.nameLabel.numberOfLines = 2
        self.nameLabel.shadowColor = UIColor.black.withAlphaComponent(0.6)
        self.nameLabel.shadowOffset = CGSize(width: 0, height: 1.5)
        self.headerView.addSubview(self.nameLabel)
        
        // Subtitle Label
        self.subtitleLabel.text = "Исполнитель • Apple Music"
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.70)
        self.headerView.addSubview(self.subtitleLabel)
        
        // Play All Button (Apple Music Red Capsule)
        let playCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        self.playAllButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playCfg), for: .normal)
        self.playAllButton.setTitle("  Слушать", for: .normal)
        self.playAllButton.tintColor = .white
        self.playAllButton.setTitleColor(.white, for: .normal)
        self.playAllButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.playAllButton.backgroundColor = UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 0.90)
        self.playAllButton.layer.cornerRadius = 20
        self.playAllButton.layer.cornerCurve = .continuous
        self.playAllButton.addTarget(self, action: #selector(self.playAllPressed), for: .touchUpInside)
        self.headerView.addSubview(self.playAllButton)
        
        // Shuffle Button (Glass Capsule)
        let shufCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        self.shuffleButton.setImage(UIImage(systemName: "shuffle", withConfiguration: shufCfg), for: .normal)
        self.shuffleButton.setTitle("  Перемешать", for: .normal)
        self.shuffleButton.tintColor = .white
        self.shuffleButton.setTitleColor(.white, for: .normal)
        self.shuffleButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.shuffleButton.backgroundColor = UIColor(white: 1.0, alpha: 0.15)
        self.shuffleButton.layer.cornerRadius = 20
        self.shuffleButton.layer.cornerCurve = .continuous
        self.shuffleButton.layer.borderWidth = 0.5
        self.shuffleButton.layer.borderColor = UIColor(white: 1.0, alpha: 0.20).cgColor
        self.shuffleButton.addTarget(self, action: #selector(self.shufflePressed), for: .touchUpInside)
        self.headerView.addSubview(self.shuffleButton)
        
        // Albums Section
        let collLayout = UICollectionViewFlowLayout()
        collLayout.scrollDirection = .horizontal
        collLayout.itemSize = CGSize(width: 125, height: 170)
        collLayout.minimumLineSpacing = 14
        collLayout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        
        self.albumsSectionLabel.text = "Альбомы и синглы"
        self.albumsSectionLabel.font = UIFont.systemFont(ofSize: 19, weight: .bold)
        self.albumsSectionLabel.textColor = .white
        self.albumsSectionLabel.isHidden = true
        self.headerView.addSubview(self.albumsSectionLabel)
        
        self.albumsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: collLayout)
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
        
        let heroH = self.heroBannerHeight
        self.heroContainer.frame = CGRect(x: 0, y: 0, width: screenW, height: heroH)
        self.bannerImageView.frame = self.heroContainer.bounds
        self.bannerGradient.frame = self.heroContainer.bounds
        
        let contentY = heroH - 95.0
        let nameW = screenW - 70.0
        self.nameLabel.frame = CGRect(x: 20, y: contentY, width: nameW, height: 32)
        self.verifiedBadge.frame = CGRect(x: min(screenW - 40, self.nameLabel.intrinsicContentSize.width + 24), y: contentY + 6, width: 20, height: 20)
        self.subtitleLabel.frame = CGRect(x: 20, y: self.nameLabel.frame.maxY + 2, width: screenW - 40, height: 18)
        
        let btnW = (screenW - 48 - 12) * 0.5
        let btnH: CGFloat = 40.0
        let btnY = self.subtitleLabel.frame.maxY + 14
        
        self.playAllButton.frame = CGRect(x: 20, y: btnY, width: btnW, height: btnH)
        self.shuffleButton.frame = CGRect(x: self.playAllButton.frame.maxX + 12, y: btnY, width: btnW, height: btnH)
        
        let hasAlbums = !self.albums.isEmpty
        self.albumsSectionLabel.isHidden = !hasAlbums
        self.albumsCollectionView.isHidden = !hasAlbums
        
        let collY = btnY + btnH + 20
        let totalH: CGFloat
        if hasAlbums {
            self.albumsSectionLabel.frame = CGRect(x: 20, y: collY, width: screenW - 40, height: 24)
            self.albumsCollectionView.frame = CGRect(x: 0, y: collY + 30, width: screenW, height: 175)
            totalH = collY + 30 + 175 + 14
        } else {
            totalH = collY + 8
        }
        self.headerView.frame = CGRect(x: 0, y: 0, width: screenW, height: totalH)
        self.tableView.tableHeaderView = self.headerView
    }
    
    // Parallax stretching on scroll
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == self.tableView {
            let offsetY = scrollView.contentOffset.y
            if offsetY < 0 {
                let stretch = abs(offsetY)
                self.heroContainer.frame = CGRect(x: 0, y: offsetY, width: self.view.bounds.width, height: self.heroBannerHeight + stretch)
                self.bannerImageView.frame = self.heroContainer.bounds
                self.bannerGradient.frame = self.heroContainer.bounds
            }
        }
    }
    
    // Smooth pull-down to dismiss handler
    @objc private func handlePanDismiss(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self.view)
        let velocity = recognizer.velocity(in: self.view)
        
        switch recognizer.state {
        case .changed:
            if translation.y > 0 && self.tableView.contentOffset.y <= 0 {
                let dismissFraction = min(1.0, translation.y / (self.view.bounds.height * 0.7))
                self.view.transform = CGAffineTransform(translationX: 0, y: translation.y)
                self.view.alpha = 1.0 - dismissFraction * 0.4
            }
        case .ended, .cancelled:
            if (translation.y > 110.0 || velocity.y > 450.0) && self.tableView.contentOffset.y <= 0 {
                self.dismiss(animated: true, completion: nil)
            } else {
                UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.4, options: [.curveEaseOut], animations: {
                    self.view.transform = .identity
                    self.view.alpha = 1.0
                })
            }
        default:
            break
        }
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == self.panGesture && otherGestureRecognizer == self.tableView.panGestureRecognizer {
            return self.tableView.contentOffset.y <= 0
        }
        return false
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
                        guard let self = self, let loadedImage = loadedImage else { return }
                        UIView.transition(with: self.bannerImageView, duration: 0.35, options: [.transitionCrossDissolve], animations: {
                            self.bannerImageView.image = loadedImage
                        })
                    }
                } else {
                    self.bannerImageView.image = UIImage(systemName: "music.mic")
                    self.bannerImageView.tintColor = .white
                }
                
                self.emptyStateLabel.isHidden = !(self.topTracks.isEmpty && self.albums.isEmpty)
                self.layoutHeader(width: self.view.bounds.width)
                self.albumsCollectionView.reloadData()
                self.tableView.reloadData()
            }
        }
    }
    
    @objc private func closePressed() {
        self.dismiss(animated: true, completion: nil)
    }
    
    private func performSuperDismiss(completion: (() -> Void)? = nil) {
        super.dismiss(animated: false, completion: completion)
    }
    
    public override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if flag {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn], animations: {
                self.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                self.view.alpha = 0.0
            }) { [weak self] _ in
                guard let self = self else { return }
                if let navigationController = self.navigationController as? NavigationController {
                    navigationController.filterController(self, animated: false)
                    completion?()
                } else {
                    self.performSuperDismiss(completion: completion)
                }
            }
        } else {
            if let navigationController = self.navigationController as? NavigationController {
                navigationController.filterController(self, animated: false)
                completion?()
            } else {
                self.performSuperDismiss(completion: completion)
            }
        }
    }
    
    @objc private func playAllPressed() {
        guard !self.topTracks.isEmpty else { return }
        var list = self.topTracks
        let first = list.removeFirst()
        SGDoxMusicManager.shared.play(track: first, queue: list)
        self.tableView.reloadData()
        self.openPlayer()
    }
    
    @objc private func shufflePressed() {
        guard !self.topTracks.isEmpty else { return }
        var list = self.topTracks
        list.shuffle()
        let first = list.removeFirst()
        SGDoxMusicManager.shared.play(track: first, queue: list)
        self.tableView.reloadData()
        self.openPlayer()
    }
    
    private func openPlayer() {
        if let navigationController = self.navigationController as? NavigationController {
            if let _ = navigationController.viewControllers.first(where: { $0 is SGDoxMusicPlayerController }) {
                navigationController.filterController(self, animated: true)
                return
            }
            let playerController = SGDoxMusicPlayerController(context: self.context)
            playerController.navigationPresentation = .modal
            navigationController.pushViewController(playerController)
        } else {
            let playerController = SGDoxMusicPlayerController(context: self.context)
            playerController.navigationPresentation = .modal
            self.present(playerController, in: .window(.root))
        }
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
        guard indexPath.row < self.topTracks.count else { return }
        let track = self.topTracks[indexPath.row]
        let upcoming = Array(self.topTracks.dropFirst(indexPath.row + 1))
        SGDoxMusicManager.shared.play(track: track, queue: upcoming)
        tableView.reloadData()
        self.openPlayer()
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
        guard indexPath.item < self.albums.count else { return }
        let album = self.albums[indexPath.item]
        let albumVc = SGDoxAlbumViewController(context: self.context, album: album)
        if let nav = self.navigationController as? NavigationController {
            nav.pushViewController(albumVc)
        } else {
            self.present(albumVc, in: .window(.root))
        }
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
    
    private var currentTrackId: String?
    
    func configure(track: SGDoxMusicTrack, index: Int, isCurrent: Bool) {
        self.currentTrackId = track.id
        self.indexLabel.text = "\(index)"
        self.titleLabel.text = track.title
        self.titleLabel.textColor = isCurrent ? UIColor(red: 0.98, green: 0.20, blue: 0.35, alpha: 1.0) : .white
        
        let durM = Int(track.duration) / 60
        let durS = Int(track.duration) % 60
        let durStr = track.duration > 0 ? String(format: "%d:%02d", durM, durS) : ""
        let sub = track.album.isEmpty ? durStr : (durStr.isEmpty ? track.album : "\(track.album) • \(durStr)")
        self.subtitleLabel.text = sub
        
        self.playingIndicator.isHidden = !isCurrent
        
        self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
        if let artUrl = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artUrl) { [weak self] image in
                if self?.currentTrackId == track.id, let image = image {
                    self?.artworkImageView.image = image
                }
            }
        }
    }
}

// MARK: - ArtistAlbumCell

private final class ArtistAlbumCell: UICollectionViewCell {
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var currentAlbumId: String?
    
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
        self.currentAlbumId = album.id
        self.titleLabel.text = album.title
        var subParts: [String] = []
        if let rel = album.releaseDate, rel.count >= 4 {
            subParts.append(String(rel.prefix(4)))
        }
        if album.trackCount > 0 {
            subParts.append("\(album.trackCount) тр.")
        }
        self.subtitleLabel.text = subParts.joined(separator: " • ")
        
        self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
        if let artUrl = album.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artUrl) { [weak self] image in
                if self?.currentAlbumId == album.id, let image = image {
                    self?.artworkImageView.image = image
                }
            }
        }
    }
}
