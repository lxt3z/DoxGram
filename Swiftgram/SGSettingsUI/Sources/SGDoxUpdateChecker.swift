import Foundation
import UIKit
import Display
import AccountContext
import SGSimpleSettings
import OverlayStatusController
import PresentationDataUtils
import TelegramPresentationData
import UndoUI

public struct SGDoxReleaseInfo: Sendable {
    public let tagName: String
    public let name: String
    public let body: String
    public let htmlUrl: String
    public let downloadUrl: URL?
    
    public init(tagName: String, name: String, body: String, htmlUrl: String, downloadUrl: URL?) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlUrl = htmlUrl
        self.downloadUrl = downloadUrl
    }
}

public final class SGDoxUpdateChecker: @unchecked Sendable {
    public static let shared = SGDoxUpdateChecker()
    
    private let repoEndpoint = "https://api.github.com/repos/lxt3z/DoxGram/releases/latest"
    private var isChecking = false
    private let lock = NSLock()
    
    private init() {}
    
    public var currentAppVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return "1.0.0"
    }
    
    /// Checks for updates on app launch or foregrounding if enabled and throttled
    public func checkOnLaunchIfNeeded(context: AccountContext) {
        guard SGSimpleSettings.shared.doxCheckForUpdates else {
            return
        }
        
        let now = Date().timeIntervalSince1970
        let lastCheck = SGSimpleSettings.shared.doxLastUpdateCheckTimestamp
        // Check at most once every 4 hours automatically
        if now - lastCheck < 4 * 3600 {
            return
        }
        
        self.performCheck(isManual: false) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(release):
                if let release = release {
                    // Check if user already dismissed this specific version
                    if SGSimpleSettings.shared.doxLastDismissedVersion == release.tagName {
                        return
                    }
                    DispatchQueue.main.async {
                        self.presentUpdateModal(context: context, release: release)
                    }
                }
            case .failure:
                break
            }
        }
    }
    
    /// Manual check triggered by user in DoxGram Settings
    public func checkManually(context: AccountContext, presentationData: PresentationData, present: @escaping (ViewController) -> Void) {
        let isRu = presentationData.strings.baseLanguageCode.hasPrefix("ru")
        let hud = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
        present(hud)
        
        self.performCheck(isManual: true) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                hud.dismiss()
                switch result {
                case let .success(release):
                    if let release = release {
                        self.presentUpdateModal(context: context, release: release)
                    } else {
                        let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: isRu ? "У вас последняя версия" : "Up to date", text: isRu ? "Установлена актуальная версия DoxGram (\(self.currentAppVersion))" : "You have the latest version of DoxGram (\(self.currentAppVersion))", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
                        present(overlay)
                    }
                case let .failure(error):
                    let overlay = UndoOverlayController(presentationData: presentationData, content: .info(title: isRu ? "Ошибка проверки" : "Check failed", text: error.localizedDescription, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
                    present(overlay)
                }
            }
        }
    }
    
    private func presentUpdateModal(context: AccountContext, release: SGDoxReleaseInfo) {
        let modal = SGDoxUpdateModalController(context: context, releaseInfo: release)
        if let mainWindow = context.sharedContext.mainWindow {
            mainWindow.present(modal, on: .root)
        }
    }
    
    private func performCheck(isManual: Bool, completion: @escaping (Result<SGDoxReleaseInfo?, Error>) -> Void) {
        self.lock.lock()
        if self.isChecking {
            self.lock.unlock()
            return
        }
        self.isChecking = true
        self.lock.unlock()
        
        guard let url = URL(string: self.repoEndpoint) else {
            self.lock.lock()
            self.isChecking = false
            self.lock.unlock()
            completion(.failure(NSError(domain: "SGDoxUpdateChecker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid endpoint URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12.0
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("DoxGram-iOS/\(self.currentAppVersion)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            self.lock.lock()
            self.isChecking = false
            self.lock.unlock()
            
            SGSimpleSettings.shared.doxLastUpdateCheckTimestamp = Date().timeIntervalSince1970
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(NSError(domain: "SGDoxUpdateChecker", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid response data"])))
                return
            }
            
            guard let tagName = json["tag_name"] as? String else {
                completion(.failure(NSError(domain: "SGDoxUpdateChecker", code: -3, userInfo: [NSLocalizedDescriptionKey: "No releases found"])))
                return
            }
            
            let name = (json["name"] as? String) ?? tagName
            let body = (json["body"] as? String) ?? ""
            let htmlUrl = (json["html_url"] as? String) ?? "https://github.com/lxt3z/DoxGram/releases"
            
            var directDownloadUrl: URL? = nil
            if let assets = json["assets"] as? [[String: Any]] {
                // Find .ipa asset if present
                for asset in assets {
                    if let assetName = asset["name"] as? String, assetName.lowercased().hasSuffix(".ipa"),
                       let downloadStr = asset["browser_download_url"] as? String,
                       let assetUrl = URL(string: downloadStr) {
                        directDownloadUrl = assetUrl
                        break
                    }
                }
            }
            
            let isNewer = self.isVersion(tagName, newerThan: self.currentAppVersion)
            if isNewer {
                let info = SGDoxReleaseInfo(tagName: tagName, name: name, body: body, htmlUrl: htmlUrl, downloadUrl: directDownloadUrl)
                completion(.success(info))
            } else {
                completion(.success(nil))
            }
        }.resume()
    }
    
    /// Compares two semver-like version strings, e.g. "v1.2.3" vs "1.2.0"
    public func isVersion(_ remoteVersion: String, newerThan currentVersion: String) -> Bool {
        let cleanRemote = remoteVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let cleanCurrent = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        
        let remoteParts = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let currentParts = cleanCurrent.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(remoteParts.count, currentParts.count)
        for i in 0..<maxCount {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c {
                return true
            } else if r < c {
                return false
            }
        }
        
        return false
    }
}
