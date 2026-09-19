import Foundation
import UIKit
import TelegramCore

public enum SGDoxMusicSource: String, Codable, CaseIterable, Sendable {
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

public struct SGDoxMusicTrack: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
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
    
    private enum CodingKeys: String, CodingKey {
        case id, title, artist, album, artworkUrl, duration, previewUrl, source, spotifyUri, appleMusicId
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.artist = try container.decode(String.self, forKey: .artist)
        self.album = try container.decodeIfPresent(String.self, forKey: .album) ?? ""
        self.artworkUrl = try container.decodeIfPresent(String.self, forKey: .artworkUrl)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0.0
        self.previewUrl = try container.decodeIfPresent(String.self, forKey: .previewUrl)
        self.source = try container.decode(SGDoxMusicSource.self, forKey: .source)
        self.spotifyUri = try container.decodeIfPresent(String.self, forKey: .spotifyUri)
        self.appleMusicId = try container.decodeIfPresent(String.self, forKey: .appleMusicId)
        self.telegramFile = nil
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.artist, forKey: .artist)
        try container.encode(self.album, forKey: .album)
        try container.encodeIfPresent(self.artworkUrl, forKey: .artworkUrl)
        try container.encode(self.duration, forKey: .duration)
        try container.encodeIfPresent(self.previewUrl, forKey: .previewUrl)
        try container.encode(self.source, forKey: .source)
        try container.encodeIfPresent(self.spotifyUri, forKey: .spotifyUri)
        try container.encodeIfPresent(self.appleMusicId, forKey: .appleMusicId)
    }
}
