import Foundation
import UIKit
import AVFoundation

public enum SGDoxPlaybackEffect: String, CaseIterable, Codable, Sendable {
    case normal = "normal"
    case slowed = "slowed"
    case nightcore = "nightcore"
    case speed125 = "speed125"
    case speed150 = "speed150"
    
    public var title: String {
        switch self {
        case .normal: return "1.0x (Обычный)"
        case .slowed: return "Slowed + Reverb (0.85x)"
        case .nightcore: return "Nightcore (1.20x)"
        case .speed125: return "1.25x Ускорение"
        case .speed150: return "1.50x Ускорение"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .normal: return "Оригинальное студийное звучание"
        case .slowed: return "Атмосферное замедление и глубокий бас"
        case .nightcore: return "Быстрый динамичный темп и драйв"
        case .speed125: return "Ускоренное воспроизведение без сдвига тона"
        case .speed150: return "Максимальный темп для подкастов и речи"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .normal: return "1.0x"
        case .slowed: return "Slowed"
        case .nightcore: return "Nightcore"
        case .speed125: return "1.25x"
        case .speed150: return "1.50x"
        }
    }
    
    public var icon: String {
        switch self {
        case .normal: return "gauge.medium"
        case .slowed: return "tortoise.fill"
        case .nightcore: return "hare.fill"
        case .speed125, .speed150: return "bolt.fill"
        }
    }
    
    public var rate: Float {
        switch self {
        case .normal: return 1.0
        case .slowed: return 0.85
        case .nightcore: return 1.20
        case .speed125: return 1.25
        case .speed150: return 1.50
        }
    }
    
    public var pitchAlgorithm: AVAudioTimePitchAlgorithm {
        switch self {
        case .slowed, .nightcore:
            // Authentic vintage tape / slowed / nightcore analog pitch glide
            return .varispeed
        case .normal, .speed125, .speed150:
            // High-fidelity natural vocal preservation
            return .spectral
        }
    }
    
    public var badgeColor: UIColor {
        switch self {
        case .normal:
            return UIColor(white: 1.0, alpha: 0.85)
        case .slowed:
            return UIColor(red: 0.72, green: 0.45, blue: 1.0, alpha: 1.0)
        case .nightcore:
            return UIColor(red: 1.0, green: 0.32, blue: 0.60, alpha: 1.0)
        case .speed125, .speed150:
            return UIColor(red: 0.25, green: 0.78, blue: 1.0, alpha: 1.0)
        }
    }
    
    public var badgeBackgroundColor: UIColor {
        switch self {
        case .normal:
            return UIColor(white: 1.0, alpha: 0.12)
        case .slowed:
            return UIColor(red: 0.60, green: 0.25, blue: 0.95, alpha: 0.24)
        case .nightcore:
            return UIColor(red: 0.95, green: 0.18, blue: 0.50, alpha: 0.24)
        case .speed125, .speed150:
            return UIColor(red: 0.15, green: 0.65, blue: 0.95, alpha: 0.24)
        }
    }
}
