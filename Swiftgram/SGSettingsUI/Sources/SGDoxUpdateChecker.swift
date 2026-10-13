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
    
    public var currentAppBuild: Int {
        if let buildStr = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           let build = Int(buildStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return build
        }
        return 0
    }
    
    public var currentDisplayVersion: String {
        let version = self.currentAppVersion
        let build = self.currentAppBuild
        if build > 0 {
            return "\(version) (\(build))"
        }
        return version
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
                        let overlay = UndoOverlayController(presentationData: presentationData, content: .actionSucceeded(title: isRu ? "У вас последняя версия" : "Up to date", text: isRu ? "Установлена актуальная версия DoxGram (\(self.currentDisplayVersion))" : "You have the latest version of DoxGram (\(self.currentDisplayVersion))", cancel: nil, destructive: false), elevatedLayout: false, action: { _ in return false })
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
        request.setValue("DoxGram-iOS/\(self.currentDisplayVersion)", forHTTPHeaderField: "User-Agent")
        
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
            
            let isNewer = self.isReleaseNewer(tagName: tagName, releaseName: name)
            if isNewer {
                let info = SGDoxReleaseInfo(tagName: tagName, name: name, body: body, htmlUrl: htmlUrl, downloadUrl: directDownloadUrl)
                completion(.success(info))
            } else {
                completion(.success(nil))
            }
        }.resume()
    }
    
    /// Extracts a build number (e.g. 3929 from "build-3929" or "DoxGram 12.9.2 (3929)")
    public func extractBuildNumber(from text: String) -> Int? {
        // 1. Matches like (3923) or (3929)
        if let match = text.range(of: #"\(([0-9]{3,7})\)"#, options: .regularExpression) {
            let digits = text[match].trimmingCharacters(in: CharacterSet(charactersIn: "() \t\n\r"))
            if let b = Int(digits) { return b }
        }
        // 2. Matches like build-3923, build_3923, build 3923, build3923
        if let range = text.range(of: #"(?i)build[-_ ]?([0-9]{3,7})"#, options: .regularExpression) {
            let matched = String(text[range])
            let digits = matched.replacingOccurrences(of: #"(?i)build[-_ ]?"#, with: "", options: .regularExpression)
            if let b = Int(digits) { return b }
        }
        // 3. Matches like b3923 or b 3923
        if let range = text.range(of: #"(?i)\bb[-_ ]?([0-9]{3,7})\b"#, options: .regularExpression) {
            let matched = String(text[range])
            let digits = matched.replacingOccurrences(of: #"(?i)[b-_ ]"#, with: "", options: .regularExpression)
            if let b = Int(digits) { return b }
        }
        // 4. Standalone 3-6 digit number if it looks like a build number (>= 100)
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for token in tokens {
            if token.count >= 3 && token.count <= 7, let val = Int(token), val >= 100 {
                return val
            }
        }
        return nil
    }

    /// Extracts semantic version components, e.g. [12, 9, 2] from "12.9.2" or "DoxGram 12.9.2 (3923)"
    public func extractSemanticVersion(from text: String) -> [Int]? {
        if let range = text.range(of: #"\b[0-9]+(\.[0-9]+)+\b"#, options: .regularExpression) {
            let verStr = String(text[range])
            let parts = verStr.split(separator: ".").compactMap { Int($0) }
            if !parts.isEmpty {
                return parts
            }
        }
        return nil
    }

    private func compareSemver(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        let maxCount = max(a.count, b.count)
        for i in 0..<maxCount {
            let valA = i < a.count ? a[i] : 0
            let valB = i < b.count ? b[i] : 0
            if valA > valB {
                return .orderedDescending
            } else if valA < valB {
                return .orderedAscending
            }
        }
        return .orderedSame
    }

    /// Determines if a GitHub release is newer than the currently installed app
    public func isReleaseNewer(tagName: String, releaseName: String) -> Bool {
        let remoteBuild = self.extractBuildNumber(from: tagName) ?? self.extractBuildNumber(from: releaseName)
        let currentBuild = self.currentAppBuild

        let remoteSemver = self.extractSemanticVersion(from: releaseName) ?? self.extractSemanticVersion(from: tagName)
        let currentSemver = self.extractSemanticVersion(from: self.currentAppVersion) ?? self.currentAppVersion.split(separator: ".").compactMap { Int($0) }

        // 1. If both have build numbers and they are valid (> 0):
        if let rBuild = remoteBuild, rBuild > 0, currentBuild > 0 {
            // If semver is also present in both, check if remote semver is distinctly older or newer
            if let rSem = remoteSemver, !currentSemver.isEmpty {
                let cmp = self.compareSemver(rSem, currentSemver)
                if cmp == .orderedDescending {
                    return true
                } else if cmp == .orderedAscending {
                    return false
                }
                // Same semver: rely on build number
                return rBuild > currentBuild
            }
            // Semver not present: compare build numbers directly
            return rBuild > currentBuild
        }

        // 2. If build number is not available, fallback to semver comparison
        if let rSem = remoteSemver, !currentSemver.isEmpty {
            return self.compareSemver(rSem, currentSemver) == .orderedDescending
        }

        // 3. Fallback to basic string version comparison if anything else
        return self.isVersion(tagName, newerThan: self.currentAppVersion)
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
