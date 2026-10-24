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
    private var isFavoriteArtist: Bool = false
    
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let grabber = UIView()
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let emptyStateLabel = UILabel()
    
    // Top Navigation Bar (Apple Music Frosted Circles)
    private let topNavBar = UIView()
    private let backButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)
    private let moreOptionsButton = UIButton(type: .system)
    
    // Apple Music Header View
    private let headerView = UIView()
    private let heroContainer = UIView()
    private let bannerImageView = UIImageView()
    private let backdropBlurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bannerGradient = CAGradientLayer()
    
    // Artist Title & Info
    private let nameLabel = UILabel()
    private let nameChevron = UIImageView()
    
    // Three Action Circles: ( i )  ( ▶ )  ( ★ )
    private let actionButtonsStack = UIStackView()
    private let infoCircleButton = UIButton(type: .system)
    private let playCircleButton = UIButton(type: .system)
    private let favoriteCircleButton = UIButton(type: .system)
    
    // Latest Release Hero Card ("ПОСЛЕДНИЙ РЕЛИЗ")
    private let latestReleaseHeader = UILabel()
    private let latestReleaseCard = UIButton(type: .custom)
    private let latestReleaseArtwork = UIImageView()
    private let latestReleaseYear = UILabel()
    private let latestReleaseTitle = UILabel()
    private let latestReleaseSubtitle = UILabel()
    private let latestReleaseActionIcon = UIImageView()
    private var latestAlbum: SGDoxAlbum?
    
    // Top Songs Section Header
    private let topSongsHeader = UILabel()
    
    // Albums Section
    private let albumsSectionHeader = UILabel()
    private var albumsCollectionView: UICollectionView!
    
    private let heroBannerHeight: CGFloat = 360.0
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
        self.grabber.frame = CGRect(x: (layout.size.width - 38) * 0.5, y: max(8, statusBarHeight - 22), width: 38, height: 5)
        
        // Layout Top Nav Bar (Frosted round buttons)
        let topBarY = inNav ? statusBarHeight : max(10.0, statusBarHeight - 16.0)
        self.topNavBar.frame = CGRect(x: 0, y: topBarY, width: layout.size.width, height: 44.0)
        let btnSide: CGFloat = 36.0
        self.backButton.frame = CGRect(x: 18.0, y: (44.0 - btnSide) * 0.5, width: btnSide, height: btnSide)
        self.backButton.layer.cornerRadius = btnSide * 0.5
        
        self.moreOptionsButton.frame = CGRect(x: layout.size.width - 18.0 - btnSide, y: (44.0 - btnSide) * 0.5, width: btnSide, height: btnSide)
        self.moreOptionsButton.layer.cornerRadius = btnSide * 0.5
        
        self.shareButton.frame = CGRect(x: self.moreOptionsButton.frame.minX - 10.0 - btnSide, y: (44.0 - btnSide) * 0.5, width: btnSide, height: btnSide)
        self.shareButton.layer.cornerRadius = btnSide * 0.5
        
        self.view.bringSubviewToFront(self.topNavBar)
        
        self.tableView.frame = CGRect(x: 0, y: 0, width: layout.size.width, height: layout.size.height)
        self.layoutHeader(width: layout.size.width)
        
        self.activityIndicator.center = CGPoint(x: layout.size.width * 0.5, y: max(220.0, layout.size.height * 0.45))
        self.view.bringSubviewToFront(self.activityIndicator)
        
        let headerBottom = self.headerView.frame.maxY
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
        
        // Table View
        self.tableView.backgroundColor = .clear
        self.tableView.separatorColor = UIColor(white: 1.0, alpha: 0.08)
        self.tableView.separatorInset = UIEdgeInsets(top: 0, left: 88, bottom: 0, right: 16)
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(ArtistTrackCell.self, forCellReuseIdentifier: "ArtistTrackCell")
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
        self.view.addSubview(self.tableView)
        
        // Setup Apple Music Header View
        self.setupHeaderView()
        
        // Setup Top Nav Bar
        self.setupTopNavBar()
        
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
    
    private func setupTopNavBar() {
        self.topNavBar.backgroundColor = .clear
        self.view.addSubview(self.topNavBar)
        
        let backConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        self.backButton.setImage(UIImage(systemName: "chevron.left", withConfiguration: backConfig), for: .normal)
        self.styleFrostedNavButton(self.backButton)
        self.backButton.addTarget(self, action: #selector(self.backPressed), for: .touchUpInside)
        self.topNavBar.addSubview(self.backButton)
        
        let shareConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        self.shareButton.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: shareConfig), for: .normal)
        self.styleFrostedNavButton(self.shareButton)
        self.shareButton.addTarget(self, action: #selector(self.sharePressed), for: .touchUpInside)
        self.topNavBar.addSubview(self.shareButton)
        
        let moreConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        self.moreOptionsButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: moreConfig), for: .normal)
        self.styleFrostedNavButton(self.moreOptionsButton)
        self.moreOptionsButton.addTarget(self, action: #selector(self.moreOptionsPressed), for: .touchUpInside)
        self.topNavBar.addSubview(self.moreOptionsButton)
    }
    
    private func styleFrostedNavButton(_ button: UIButton) {
        button.tintColor = .white
        button.backgroundColor = UIColor(white: 0.18, alpha: 0.70)
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(white: 1.0, alpha: 0.22).cgColor
        button.clipsToBounds = true
    }
    
    private func setupHeaderView() {
        self.headerView.clipsToBounds = false
        
        // Hero container
        self.heroContainer.clipsToBounds = true
        self.headerView.addSubview(self.heroContainer)
        
        self.bannerImageView.contentMode = .scaleAspectFill
        self.bannerImageView.clipsToBounds = true
        self.bannerImageView.backgroundColor = UIColor(white: 0.10, alpha: 1.0)
        self.heroContainer.addSubview(self.bannerImageView)
        
        self.backdropBlurView.clipsToBounds = true
        self.heroContainer.addSubview(self.backdropBlurView)
        
        self.bannerGradient.colors = [
            UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.15).cgColor,
            UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.50).cgColor,
            UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 0.90).cgColor,
            UIColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.00).cgColor
        ]
        self.bannerGradient.locations = [0.0, 0.40, 0.80, 1.0]
        self.bannerGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.bannerGradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.heroContainer.layer.addSublayer(self.bannerGradient)
        
        // Artist Title (Apple Music Large Title)
        self.nameLabel.text = self.artistName
        self.nameLabel.font = UIFont.systemFont(ofSize: 32, weight: .heavy)
        self.nameLabel.textColor = .white
        self.nameLabel.numberOfLines = 1
        self.nameLabel.textAlignment = .left
        self.headerView.addSubview(self.nameLabel)
        
        let chevConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        self.nameChevron.image = UIImage(systemName: "chevron.right", withConfiguration: chevConfig)
        self.nameChevron.tintColor = UIColor(white: 1.0, alpha: 0.45)
        self.nameChevron.contentMode = .scaleAspectFit
        self.headerView.addSubview(self.nameChevron)
        
        // Three Action Circular Buttons: ( i )  ( ▶ )  ( ★ )
        self.actionButtonsStack.axis = .horizontal
        self.actionButtonsStack.alignment = .center
        self.actionButtonsStack.distribution = .equalCentering
        self.actionButtonsStack.spacing = 32.0
        self.headerView.addSubview(self.actionButtonsStack)
        
        // Info Button ( i )
        let infoCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        self.infoCircleButton.setImage(UIImage(systemName: "info.circle", withConfiguration: infoCfg), for: .normal)
        self.styleActionCircleButton(self.infoCircleButton, side: 46.0, bg: UIColor(white: 0.20, alpha: 0.70), tint: .white)
        self.infoCircleButton.addTarget(self, action: #selector(self.infoPressed), for: .touchUpInside)
        self.actionButtonsStack.addArrangedSubview(self.infoCircleButton)
        
        // Play Button ( ▶ ) - prominent white circle
        let playCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .heavy)
        self.playCircleButton.setImage(UIImage(systemName: "play.fill", withConfiguration: playCfg), for: .normal)
        self.styleActionCircleButton(self.playCircleButton, side: 54.0, bg: .white, tint: .black)
        self.playCircleButton.addTarget(self, action: #selector(self.playAllPressed), for: .touchUpInside)
        self.actionButtonsStack.addArrangedSubview(self.playCircleButton)
        
        // Favorite Button ( ★ )
        let starCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        self.favoriteCircleButton.setImage(UIImage(systemName: "star", withConfiguration: starCfg), for: .normal)
        self.styleActionCircleButton(self.favoriteCircleButton, side: 46.0, bg: UIColor(white: 0.20, alpha: 0.70), tint: .white)
        self.favoriteCircleButton.addTarget(self, action: #selector(self.toggleFavoritePressed), for: .touchUpInside)
        self.actionButtonsStack.addArrangedSubview(self.favoriteCircleButton)
        
        // Featured / Latest Release Header & Hero Card
        self.latestReleaseHeader.text = "ПОСЛЕДНИЙ РЕЛИЗ"
        self.latestReleaseHeader.font = UIFont.systemFont(ofSize: 12.5, weight: .bold)
        self.latestReleaseHeader.textColor = UIColor(white: 1.0, alpha: 0.50)
        self.latestReleaseHeader.isHidden = true
        self.headerView.addSubview(self.latestReleaseHeader)
        
        self.setupLatestReleaseCard()
        
        // Top Songs Header
        self.topSongsHeader.text = "Лучшие песни  ›"
        self.topSongsHeader.font = UIFont.systemFont(ofSize: 21, weight: .bold)
        self.topSongsHeader.textColor = .white
        self.topSongsHeader.isHidden = true
        self.headerView.addSubview(self.topSongsHeader)
        
        // Albums Section
        let collLayout = UICollectionViewFlowLayout()
        collLayout.scrollDirection = .horizontal
        collLayout.itemSize = CGSize(width: 132, height: 180)
        collLayout.minimumLineSpacing = 16
        collLayout.sectionInset = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        
        self.albumsSectionHeader.text = "Альбомы  ›"
        self.albumsSectionHeader.font = UIFont.systemFont(ofSize: 21, weight: .bold)
        self.albumsSectionHeader.textColor = .white
        self.albumsSectionHeader.isHidden = true
        self.headerView.addSubview(self.albumsSectionHeader)
        
        self.albumsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: collLayout)
        self.albumsCollectionView.backgroundColor = .clear
        self.albumsCollectionView.showsHorizontalScrollIndicator = false
        self.albumsCollectionView.dataSource = self
        self.albumsCollectionView.delegate = self
        self.albumsCollectionView.register(ArtistAlbumCell.self, forCellReuseIdentifier: "ArtistAlbumCell")
        self.albumsCollectionView.isHidden = true
        self.headerView.addSubview(self.albumsCollectionView)
    }
    
    private func styleActionCircleButton(_ button: UIButton, side: CGFloat, bg: UIColor, tint: UIColor) {
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: side),
            button.heightAnchor.constraint(equalToConstant: side)
        ])
        button.layer.cornerRadius = side * 0.5
        button.backgroundColor = bg
        button.tintColor = tint
        button.layer.borderWidth = (bg == .white) ? 0.0 : 0.5
        button.layer.borderColor = UIColor(white: 1.0, alpha: 0.20).cgColor
        button.clipsToBounds = true
    }
    
    private func setupLatestReleaseCard() {
        self.latestReleaseCard.backgroundColor = UIColor(white: 1.0, alpha: 0.08)
        self.latestReleaseCard.layer.cornerRadius = 16.0
        self.latestReleaseCard.layer.cornerCurve = .continuous
        self.latestReleaseCard.layer.borderWidth = 0.5
        self.latestReleaseCard.layer.borderColor = UIColor(white: 1.0, alpha: 0.12).cgColor
        self.latestReleaseCard.clipsToBounds = true
        self.latestReleaseCard.addTarget(self, action: #selector(self.latestReleaseCardTapped), for: .touchUpInside)
        self.latestReleaseCard.isHidden = true
        self.headerView.addSubview(self.latestReleaseCard)
        
        self.latestReleaseArtwork.contentMode = .scaleAspectFill
        self.latestReleaseArtwork.clipsToBounds = true
        self.latestReleaseArtwork.layer.cornerRadius = 8.0
        self.latestReleaseArtwork.layer.cornerCurve = .continuous
        self.latestReleaseArtwork.backgroundColor = UIColor(white: 0.15, alpha: 1.0)
        self.latestReleaseCard.addSubview(self.latestReleaseArtwork)
        
        self.latestReleaseYear.font = UIFont.systemFont(ofSize: 12.0, weight: .regular)
        self.latestReleaseYear.textColor = UIColor(white: 1.0, alpha: 0.50)
        self.latestReleaseCard.addSubview(self.latestReleaseYear)
        
        self.latestReleaseTitle.font = UIFont.systemFont(ofSize: 15.0, weight: .bold)
        self.latestReleaseTitle.textColor = .white
        self.latestReleaseTitle.numberOfLines = 1
        self.latestReleaseCard.addSubview(self.latestReleaseTitle)
        
        self.latestReleaseSubtitle.font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        self.latestReleaseSubtitle.textColor = UIColor(white: 1.0, alpha: 0.50)
        self.latestReleaseSubtitle.numberOfLines = 1
        self.latestReleaseCard.addSubview(self.latestReleaseSubtitle)
        
        let downCfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        self.latestReleaseActionIcon.image = UIImage(systemName: "arrow.down.circle", withConfiguration: downCfg)
        self.latestReleaseActionIcon.tintColor = UIColor(white: 1.0, alpha: 0.65)
        self.latestReleaseActionIcon.contentMode = .scaleAspectFit
        self.latestReleaseCard.addSubview(self.latestReleaseActionIcon)
    }
    
    private func layoutHeader(width: CGFloat) {
        guard width > 0 else { return }
        let screenW = width
        
        // 1. Hero banner parallax container
        let heroH = self.heroBannerHeight
        self.heroContainer.frame = CGRect(x: 0, y: 0, width: screenW, height: heroH)
        self.bannerImageView.frame = self.heroContainer.bounds
        self.backdropBlurView.frame = self.heroContainer.bounds
        self.bannerGradient.frame = self.heroContainer.bounds
        
        // 2. Artist Title
        let nameY: CGFloat = 130.0
        let nameSize = self.nameLabel.sizeThatFits(CGSize(width: screenW - 64.0, height: 42.0))
        let nameW = min(screenW - 64.0, nameSize.width)
        self.nameLabel.frame = CGRect(x: 18.0, y: nameY, width: nameW, height: 38.0)
        self.nameChevron.frame = CGRect(x: self.nameLabel.frame.maxX + 4.0, y: nameY + 9.0, width: 14.0, height: 20.0)
        
        // 3. Action Buttons Row ( (i)  (▶)  (★) )
        let stackY = nameY + 46.0
        self.actionButtonsStack.frame = CGRect(x: (screenW - 220.0) * 0.5, y: stackY, width: 220.0, height: 56.0)
        
        var currentY = stackY + 66.0
        
        // 4. Latest Release Hero Card
        let hasLatest = (self.latestAlbum != nil)
        self.latestReleaseHeader.isHidden = !hasLatest
        self.latestReleaseCard.isHidden = !hasLatest
        
        if let album = self.latestAlbum {
            self.latestReleaseHeader.frame = CGRect(x: 18.0, y: currentY, width: screenW - 36.0, height: 18.0)
            currentY += 24.0
            
            let cardH: CGFloat = 82.0
            self.latestReleaseCard.frame = CGRect(x: 18.0, y: currentY, width: screenW - 36.0, height: cardH)
            
            let artSide: CGFloat = 66.0
            self.latestReleaseArtwork.frame = CGRect(x: 8.0, y: (cardH - artSide) * 0.5, width: artSide, height: artSide)
            
            let textX = self.latestReleaseArtwork.frame.maxX + 12.0
            let rightIconSide: CGFloat = 28.0
            let textW = self.latestReleaseCard.bounds.width - textX - rightIconSide - 16.0
            
            self.latestReleaseYear.frame = CGRect(x: textX, y: 12.0, width: textW, height: 16.0)
            self.latestReleaseTitle.frame = CGRect(x: textX, y: 30.0, width: textW, height: 20.0)
            self.latestReleaseSubtitle.frame = CGRect(x: textX, y: 52.0, width: textW, height: 16.0)
            
            self.latestReleaseActionIcon.frame = CGRect(x: self.latestReleaseCard.bounds.width - rightIconSide - 12.0, y: (cardH - rightIconSide) * 0.5, width: rightIconSide, height: rightIconSide)
            
            currentY += cardH + 28.0
        } else {
            currentY += 12.0
        }
        
        // 5. Top Songs Section Header
        let hasTracks = !self.topTracks.isEmpty
        self.topSongsHeader.isHidden = !hasTracks
        if hasTracks {
            self.topSongsHeader.frame = CGRect(x: 18.0, y: currentY, width: screenW - 36.0, height: 26.0)
            currentY += 34.0
        }
        
        self.headerView.frame = CGRect(x: 0, y: 0, width: screenW, height: currentY)
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
                self.backdropBlurView.frame = self.heroContainer.bounds
                self.bannerGradient.frame = self.heroContainer.bounds
            }
        }
    }
    
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
                self.albums = albums.sorted { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") }
                self.latestAlbum = self.albums.first
                self.artistImageUrl = artistImageUrl
                
                // Configure Latest Release Card
                if let latest = self.latestAlbum {
                    let yearStr = latest.releaseDate.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } ?? ""
                    self.latestReleaseYear.text = yearStr
                    self.latestReleaseTitle.text = latest.title
                    let countStr = latest.trackCount > 0 ? "\(latest.trackCount) треков" : "Сингл"
                    self.latestReleaseSubtitle.text = yearStr.isEmpty ? countStr : "Релиз • \(countStr)"
                    
                    self.latestReleaseArtwork.image = SGDoxImageLoader.shared.placeholderArtwork()
                    if let art = latest.artworkUrl {
                        SGDoxImageLoader.shared.loadImage(urlString: art) { [weak self] img in
                            if let img = img {
                                self?.latestReleaseArtwork.image = img
                            }
                        }
                    }
                }
                
                if let imgUrl = artistImageUrl {
                    SGDoxImageLoader.shared.loadImage(urlString: imgUrl) { [weak self] loadedImage in
                        guard let self = self, let loadedImage = loadedImage else { return }
                        UIView.transition(with: self.bannerImageView, duration: 0.35, options: [.transitionCrossDissolve], animations: {
                            self.bannerImageView.image = loadedImage
                        })
                    }
                }
                
                self.emptyStateLabel.isHidden = !(self.topTracks.isEmpty && self.albums.isEmpty)
                self.layoutHeader(width: self.view.bounds.width)
                self.albumsCollectionView.reloadData()
                self.tableView.reloadData()
            }
        }
    }
    
    @objc private func backPressed() {
        self.dismiss(animated: true, completion: nil)
    }
    
    @objc private func sharePressed() {
        let shareText = "\(self.artistName)\nСлушайте в DoxMusic"
        let activityVc = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        activityVc.popoverPresentationController?.sourceView = self.shareButton
        activityVc.popoverPresentationController?.sourceRect = self.shareButton.bounds
        self.present(activityVc, animated: true)
    }
    
    @objc private func moreOptionsPressed() {
        let alert = UIAlertController(title: self.artistName, message: nil, preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = self.moreOptionsButton
        alert.popoverPresentationController?.sourceRect = self.moreOptionsButton.bounds
        alert.addAction(UIAlertAction(title: "Поделиться артистом", style: .default, handler: { [weak self] _ in
            self?.sharePressed()
        }))
        alert.addAction(UIAlertAction(title: self.isFavoriteArtist ? "Удалить из избранных артистов" : "Добавить в избранные артисты", style: .default, handler: { [weak self] _ in
            self?.toggleFavoritePressed()
        }))
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @objc private func infoPressed() {
        let alert = UIAlertController(title: self.artistName, message: "Исполнитель Apple Music\nТреков: \(self.topTracks.count)\nАльбомов: \(self.albums.count)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true)
    }
    
    @objc private func toggleFavoritePressed() {
        self.isFavoriteArtist.toggle()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let starCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let starImg = UIImage(systemName: self.isFavoriteArtist ? "star.fill" : "star", withConfiguration: starCfg)
        self.favoriteCircleButton.setImage(starImg, for: .normal)
        self.favoriteCircleButton.tintColor = self.isFavoriteArtist ? UIColor(red: 1.0, green: 0.28, blue: 0.38, alpha: 1.0) : .white
    }
    
    @objc private func latestReleaseCardTapped() {
        guard let album = self.latestAlbum else { return }
        let albumVc = SGDoxAlbumViewController(context: self.context, album: album)
        if let nav = self.navigationController as? NavigationController {
            nav.pushViewController(albumVc)
        } else {
            self.present(albumVc, in: .window(.root))
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
    
    private func openPlayer() {
        SGDoxMusicPlayerController.present(context: self.context)
    }
    
    // MARK: - UITableViewDataSource & Delegate
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return self.albums.isEmpty ? 1 : 2
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return self.topTracks.count
        } else {
            return 1 // Albums Collection Row
        }
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 {
            return 56.0
        } else {
            return 210.0
        }
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "ArtistTrackCell", for: indexPath) as? ArtistTrackCell else {
                return UITableViewCell()
            }
            let track = self.topTracks[indexPath.row]
            let isCurrent = SGDoxMusicManager.shared.currentTrack?.id == track.id
            cell.configure(track: track, index: indexPath.row + 1, isCurrent: isCurrent)
            cell.onMoreTap = { [weak self] in
                guard let self = self else { return }
                let alert = UIAlertController(title: track.title, message: track.artist, preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: "Воспроизвести", style: .default, handler: { _ in
                    SGDoxMusicManager.shared.play(track: track)
                    self.openPlayer()
                }))
                alert.addAction(UIAlertAction(title: "Закрепить в профиле", style: .default, handler: { _ in
                    SGSimpleSettings.shared.doxProfileTrackId = track.id
                    SGSimpleSettings.shared.doxProfileTrackTitle = track.title
                    SGSimpleSettings.shared.doxProfileTrackArtist = track.artist
                    SGSimpleSettings.shared.doxProfileTrackArtworkUrl = track.artworkUrl
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
            return cell
        } else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            self.albumsCollectionView.frame = CGRect(x: 0, y: 10, width: tableView.bounds.width, height: 190)
            cell.contentView.addSubview(self.albumsCollectionView)
            self.albumsCollectionView.isHidden = false
            return cell
        }
    }
    
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == 1 && !self.albums.isEmpty {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 38.0))
            let lbl = UILabel(frame: CGRect(x: 18.0, y: 6.0, width: tableView.bounds.width - 36.0, height: 26.0))
            lbl.text = "Альбомы  ›"
            lbl.font = UIFont.systemFont(ofSize: 21, weight: .bold)
            lbl.textColor = .white
            container.addSubview(lbl)
            return container
        }
        return nil
    }
    
    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 1 && !self.albums.isEmpty {
            return 38.0
        }
        return 0.01
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0, indexPath.row < self.topTracks.count else { return }
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

// MARK: - ArtistTrackCell (Apple Music Numbered Track Row)

private final class ArtistTrackCell: UITableViewCell {
    var onMoreTap: (() -> Void)?
    
    private let indexLabel = UILabel()
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let explicitBadge = UILabel()
    private let subtitleLabel = UILabel()
    private let dolbyBadge = UILabel()
    private let losslessBadge = UILabel()
    private let playingIndicator = UIImageView()
    private let moreButton = UIButton(type: .system)
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        // Track number (Apple Music gray monospaced)
        self.indexLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        self.indexLabel.textColor = UIColor(white: 1.0, alpha: 0.40)
        self.indexLabel.textAlignment = .center
        self.contentView.addSubview(self.indexLabel)
        
        self.artworkImageView.layer.cornerRadius = 6.0
        self.artworkImageView.layer.cornerCurve = .continuous
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.backgroundColor = UIColor(white: 1.0, alpha: 0.10)
        self.contentView.addSubview(self.artworkImageView)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 15.5, weight: .semibold)
        self.titleLabel.textColor = .white
        self.contentView.addSubview(self.titleLabel)
        
        self.explicitBadge.text = "E"
        self.explicitBadge.font = UIFont.systemFont(ofSize: 8.5, weight: .bold)
        self.explicitBadge.textColor = UIColor(white: 0.0, alpha: 0.85)
        self.explicitBadge.backgroundColor = UIColor(white: 1.0, alpha: 0.75)
        self.explicitBadge.layer.cornerRadius = 2.0
        self.explicitBadge.clipsToBounds = true
        self.explicitBadge.textAlignment = .center
        self.explicitBadge.isHidden = true
        self.contentView.addSubview(self.explicitBadge)
        
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.50)
        self.contentView.addSubview(self.subtitleLabel)
        
        self.losslessBadge.text = "LOSSLESS"
        self.losslessBadge.font = UIFont.systemFont(ofSize: 7.5, weight: .bold)
        self.losslessBadge.textColor = UIColor(white: 1.0, alpha: 0.85)
        self.losslessBadge.backgroundColor = UIColor(white: 1.0, alpha: 0.14)
        self.losslessBadge.layer.cornerRadius = 2.5
        self.losslessBadge.clipsToBounds = true
        self.losslessBadge.textAlignment = .center
        self.losslessBadge.isHidden = true
        self.contentView.addSubview(self.losslessBadge)
        
        self.playingIndicator.image = UIImage(systemName: "waveform")
        self.playingIndicator.tintColor = UIColor(red: 1.0, green: 0.28, blue: 0.38, alpha: 1.0)
        self.playingIndicator.isHidden = true
        self.contentView.addSubview(self.playingIndicator)
        
        let moreCfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        self.moreButton.setImage(UIImage(systemName: "ellipsis", withConfiguration: moreCfg), for: .normal)
        self.moreButton.tintColor = UIColor(white: 1.0, alpha: 0.45)
        self.moreButton.addTarget(self, action: #selector(self.morePressed), for: .touchUpInside)
        self.contentView.addSubview(self.moreButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func morePressed() {
        self.onMoreTap?()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        
        self.indexLabel.frame = CGRect(x: 4.0, y: (bounds.height - 20.0) * 0.5, width: 28.0, height: 20.0)
        
        let artSide: CGFloat = 40.0
        self.artworkImageView.frame = CGRect(x: 34.0, y: (bounds.height - artSide) * 0.5, width: artSide, height: artSide)
        
        let rightSide: CGFloat = 34.0
        self.moreButton.frame = CGRect(x: bounds.width - rightSide - 6.0, y: (bounds.height - rightSide) * 0.5, width: rightSide, height: rightSide)
        self.playingIndicator.frame = CGRect(x: self.moreButton.frame.minX - 22.0, y: (bounds.height - 18.0) * 0.5, width: 18.0, height: 18.0)
        
        let textX: CGFloat = self.artworkImageView.frame.maxX + 12.0
        let rightLimit = self.playingIndicator.isHidden ? self.moreButton.frame.minX - 6.0 : self.playingIndicator.frame.minX - 6.0
        let textW = max(50.0, rightLimit - textX)
        
        let titleSize = self.titleLabel.sizeThatFits(CGSize(width: textW, height: 20.0))
        let titleW = min(textW, titleSize.width)
        self.titleLabel.frame = CGRect(x: textX, y: 8.0, width: titleW, height: 20.0)
        
        if !self.explicitBadge.isHidden {
            self.explicitBadge.frame = CGRect(x: textX + titleW + 5.0, y: 12.0, width: 13.0, height: 12.0)
        }
        
        var subBadgesW: CGFloat = 0.0
        if !self.losslessBadge.isHidden { subBadgesW += 54.0 }
        
        let subSize = self.subtitleLabel.sizeThatFits(CGSize(width: textW, height: 16.0))
        let subW = min(max(30.0, textW - subBadgesW), subSize.width)
        self.subtitleLabel.frame = CGRect(x: textX, y: 29.0, width: subW, height: 16.0)
        
        if !self.losslessBadge.isHidden {
            self.losslessBadge.frame = CGRect(x: textX + subW + 5.0, y: 31.0, width: 48.0, height: 12.5)
        }
    }
    
    private var currentTrackId: String?
    
    func configure(track: SGDoxMusicTrack, index: Int, isCurrent: Bool) {
        self.currentTrackId = track.id
        self.indexLabel.text = "\(index)"
        self.titleLabel.text = track.title
        self.titleLabel.textColor = isCurrent ? UIColor(red: 1.0, green: 0.28, blue: 0.38, alpha: 1.0) : .white
        
        let durM = Int(track.duration) / 60
        let durS = Int(track.duration) % 60
        let durStr = track.duration > 0 ? String(format: "%d:%02d", durM, durS) : ""
        let sub = track.artist.isEmpty ? durStr : (durStr.isEmpty ? track.artist : "\(track.artist) • \(durStr)")
        self.subtitleLabel.text = sub
        
        self.losslessBadge.isHidden = !track.isLossless
        self.playingIndicator.isHidden = !isCurrent
        
        self.artworkImageView.image = SGDoxImageLoader.shared.placeholderArtwork()
        if let artUrl = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artUrl) { [weak self] image in
                if self?.currentTrackId == track.id, let image = image {
                    self?.artworkImageView.image = image
                }
            }
        }
        self.setNeedsLayout()
    }
}

// MARK: - ArtistAlbumCell (Apple Music Album Card)

private final class ArtistAlbumCell: UICollectionViewCell {
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var currentAlbumId: String?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        
        self.artworkImageView.layer.cornerRadius = 10.0
        self.artworkImageView.layer.cornerCurve = .continuous
        self.artworkImageView.clipsToBounds = true
        self.artworkImageView.contentMode = .scaleAspectFill
        self.artworkImageView.backgroundColor = UIColor(white: 1.0, alpha: 0.10)
        self.contentView.addSubview(self.artworkImageView)
        
        self.titleLabel.font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        self.titleLabel.textColor = .white
        self.titleLabel.numberOfLines = 2
        self.titleLabel.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.titleLabel)
        
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 11.5, weight: .regular)
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.50)
        self.contentView.addSubview(self.subtitleLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = self.contentView.bounds.width
        self.artworkImageView.frame = CGRect(x: 0, y: 0, width: w, height: w)
        self.titleLabel.frame = CGRect(x: 0, y: w + 6, width: w, height: 32)
        self.subtitleLabel.frame = CGRect(x: 0, y: w + 40, width: w, height: 16)
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
