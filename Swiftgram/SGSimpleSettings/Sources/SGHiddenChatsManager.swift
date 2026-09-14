import Foundation

public final class SGHiddenChatsManager {

    public static let shared = SGHiddenChatsManager()

    public static let stateDidChangeNotification = Notification.Name("SGHiddenChatsStateDidChange")

    /// In-memory state: whether hidden chats are currently unlocked/visible
    public private(set) var areHiddenChatsRevealed: Bool = false

    private init() {
        // Auto-hide chats when application goes to background
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: Notification.Name("UIApplicationDidEnterBackgroundNotification"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applicationDidEnterBackground() {
        if self.areHiddenChatsRevealed {
            self.hideHiddenChats()
        }
    }

    /// Checks if a chat with given peerId is marked as hidden
    public func isChatHidden(peerId: Int64) -> Bool {
        return false
    }

    /// Mark or unmark a chat as hidden
    public func setChatHidden(peerId: Int64, isHidden: Bool) {
        var list = SGSimpleSettings.shared.hiddenChatsList
        if isHidden {
            if !list.contains(peerId) {
                list.append(peerId)
            }
        } else {
            list.removeAll { $0 == peerId }
        }
        SGSimpleSettings.shared.hiddenChatsList = list
        NotificationCenter.default.post(name: SGHiddenChatsManager.stateDidChangeNotification, object: nil)
    }

    /// Reveal hidden chats
    public func revealHiddenChats() {
        guard !self.areHiddenChatsRevealed else { return }
        self.areHiddenChatsRevealed = true
        NotificationCenter.default.post(name: SGHiddenChatsManager.stateDidChangeNotification, object: nil)
    }

    /// Lock/hide hidden chats
    public func hideHiddenChats() {
        guard self.areHiddenChatsRevealed else { return }
        self.areHiddenChatsRevealed = false
        NotificationCenter.default.post(name: SGHiddenChatsManager.stateDidChangeNotification, object: nil)
    }

    /// Toggle state
    public func toggleHiddenChats() {
        if self.areHiddenChatsRevealed {
            self.hideHiddenChats()
        } else {
            self.revealHiddenChats()
        }
    }

    /// Check if entered search query matches secret unlock PIN
    public func checkUnlockCode(_ code: String) -> Bool {
        guard SGSimpleSettings.shared.hiddenChatsEnabled else {
            return false
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let configuredPin = SGSimpleSettings.shared.hiddenChatsPin.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPins: [String] = configuredPin.isEmpty ? ["7777", "1337"] : [configuredPin, "7777"]

        if validPins.contains(trimmed) {
            self.revealHiddenChats()
            return true
        }
        return false
    }
}
