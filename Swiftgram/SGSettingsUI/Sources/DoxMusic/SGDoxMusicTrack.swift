import Foundation
import UIKit
import TelegramCore

public enum SGDoxMusicSource: String, Codable, CaseIterable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case telegram = "Telegram"
    
    public var iconName: String {
        switch self {
        case .appleMusic: return "applelogo"
        case .spotify: return "music.note"
        case .telegram: return "paperplane.fill"
        }
    }
}

public struct SGDoxMusicTrack: Identifiable, Equatable, Hashable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let artworkUrl: String?
    public let duration: Double
    public let previewUrl: String?
    public let source: SGDoxMusicSource
    public let spotifyUri: String?
    public let appleMusicId: String?
    public let telegramFile: FileMediaReference?
    
    public init(
        id: String,
        title: String,
        artist: String,
        album: String = "",
        artworkUrl: String? = nil,
        duration: Double = 0.0,
        previewUrl: String? = nil,
        source: SGDoxMusicSource,
        spotifyUri: String? = nil,
        appleMusicId: String? = nil,
        telegramFile: FileMediaReference? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkUrl = artworkUrl
        self.duration = duration
        self.previewUrl = previewUrl
        self.source = source
        self.spotifyUri = spotifyUri
        self.appleMusicId = appleMusicId
        self.telegramFile = telegramFile
    }
    
    public static func == (lhs: SGDoxMusicTrack, rhs: SGDoxMusicTrack) -> Bool {
        return lhs.id == rhs.id && lhs.source == rhs.source
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
        hasher.combine(self.source)
    }
}
