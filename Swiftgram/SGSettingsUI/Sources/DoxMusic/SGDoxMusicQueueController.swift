import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import TelegramPresentationData
import AppBundle

public final class SGDoxMusicQueueController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let headerLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    
    private var queue: [SGDoxMusicTrack] = []
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: nil)
        self.modalPresentationStyle = .pageSheet
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .clear
        
        self.blurView.frame = self.view.bounds
        self.blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.blurView)
        
        // Grabber
        let grabber = UIView(frame: CGRect(x: (self.view.bounds.width - 36) * 0.5, y: 8, width: 36, height: 5))
        grabber.backgroundColor = UIColor(white: 1.0, alpha: 0.3)
        grabber.layer.cornerRadius = 2.5
        grabber.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        self.view.addSubview(grabber)
        
        // Header
        self.headerLabel.text = "Далее в очереди"
        self.headerLabel.textColor = .white
        self.headerLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        self.view.addSubview(self.headerLabel)
        
        self.subtitleLabel.textColor = UIColor(white: 1.0, alpha: 0.6)
        self.subtitleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.view.addSubview(self.subtitleLabel)
        
        self.closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        self.closeButton.tintColor = UIColor(white: 1.0, alpha: 0.6)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.view.addSubview(self.closeButton)
        
        self.clearButton.setTitle("Очистить", for: .normal)
        self.clearButton.setTitleColor(UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0), for: .normal)
        self.clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        self.clearButton.addTarget(self, action: #selector(self.clearPressed), for: .touchUpInside)
        self.view.addSubview(self.clearButton)
        
        self.tableView.backgroundColor = .clear
        self.tableView.separatorStyle = .none
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.register(SGDoxQueueItemCell.self, forCellReuseIdentifier: "QueueCell")
        self.view.addSubview(self.tableView)
        
        self.reloadQueue()
        
        SGDoxMusicManager.shared.addStateListener { [weak self] in
            self?.reloadQueue()
        }
    }
    
    private func reloadQueue() {
        self.queue = SGDoxMusicManager.shared.queue
        self.subtitleLabel.text = self.queue.isEmpty ? "Очередь пуста" : "\(self.queue.count) трек\(self.pluralEnding(self.queue.count))"
        self.clearButton.isHidden = self.queue.isEmpty
        self.tableView.reloadData()
    }
    
    private func pluralEnding(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 { return "ов" }
        if mod10 == 1 { return "" }
        if mod10 >= 2 && mod10 <= 4 { return "а" }
        return "ов"
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = self.view.bounds
        
        self.headerLabel.frame = CGRect(x: 20, y: 24, width: bounds.width - 120, height: 26)
        self.subtitleLabel.frame = CGRect(x: 20, y: 50, width: bounds.width - 120, height: 18)
        
        self.clearButton.frame = CGRect(x: bounds.width - 130, y: 24, width: 70, height: 30)
        self.closeButton.frame = CGRect(x: bounds.width - 50, y: 22, width: 34, height: 34)
        
        self.tableView.frame = CGRect(x: 0, y: 76, width: bounds.width, height: bounds.height - 76)
    }
    
    @objc private func closePressed() {
        self.dismiss()
    }
    
    @objc private func clearPressed() {
        // Clear remaining queue
        if !self.queue.isEmpty {
            let track = SGDoxMusicManager.shared.currentTrack
            if let track = track {
                SGDoxMusicManager.shared.play(track: track, queue: [])
            }
            self.reloadQueue()
        }
    }
    
    // MARK: - Table View
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.queue.count
    }
    
    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 58.0
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "QueueCell", for: indexPath) as! SGDoxQueueItemCell
        let track = self.queue[indexPath.row]
        cell.titleLabel.text = track.title
        cell.artistLabel.text = track.artist
        cell.indexLabel.text = "\(indexPath.row + 1)"
        
        if let artwork = track.artworkUrl {
            SGDoxImageLoader.shared.loadImage(urlString: artwork) { [weak cell] img in
                cell?.artworkView.image = img
            }
        } else {
            cell.artworkView.image = UIImage(bundleImageName: "Media Editor/SmallAudio")
        }
        
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < self.queue.count else { return }
        let selectedTrack = self.queue[indexPath.row]
        let remaining = Array(self.queue.suffix(from: indexPath.row + 1))
        SGDoxMusicManager.shared.play(track: selectedTrack, queue: remaining)
        self.dismiss()
    }
}

private final class SGDoxQueueItemCell: UITableViewCell {
    let indexLabel = UILabel()
    let artworkView = UIImageView()
    let titleLabel = UILabel()
    let artistLabel = UILabel()
    let separatorView = UIView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        
        self.indexLabel.textColor = UIColor(white: 1.0, alpha: 0.4)
        self.indexLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        self.indexLabel.textAlignment = .center
        self.contentView.addSubview(self.indexLabel)
        
        self.artworkView.layer.cornerRadius = 6
        self.artworkView.clipsToBounds = true
        self.artworkView.contentMode = .scaleAspectFill
        self.artworkView.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        self.contentView.addSubview(self.artworkView)
        
        self.titleLabel.textColor = .white
        self.titleLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        self.contentView.addSubview(self.titleLabel)
        
        self.artistLabel.textColor = UIColor(white: 1.0, alpha: 0.7)
        self.artistLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        self.contentView.addSubview(self.artistLabel)
        
        self.separatorView.backgroundColor = UIColor(white: 1.0, alpha: 0.1)
        self.contentView.addSubview(self.separatorView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.contentView.bounds
        
        self.indexLabel.frame = CGRect(x: 8, y: 19, width: 24, height: 20)
        self.artworkView.frame = CGRect(x: 36, y: 9, width: 40, height: 40)
        
        let textWidth = bounds.width - 86 - 16
        self.titleLabel.frame = CGRect(x: 86, y: 10, width: textWidth, height: 20)
        self.artistLabel.frame = CGRect(x: 86, y: 30, width: textWidth, height: 18)
        
        self.separatorView.frame = CGRect(x: 86, y: bounds.height - 0.5, width: bounds.width - 86, height: 0.5)
    }
}
