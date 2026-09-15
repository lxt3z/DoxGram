import Foundation
import Postbox
import TelegramCore
import SGSimpleSettings

public final class SGAdFilterState {
    public static let shared = SGAdFilterState()
    
    private var revealedMessageIds: Set<MessageId> = []
    private let lock = NSLock()
    
    private init() {}
    
    public func isRevealed(_ id: MessageId) -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.revealedMessageIds.contains(id)
    }
    
    public func reveal(_ id: MessageId) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.revealedMessageIds.insert(id)
    }
    
    public func reset() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.revealedMessageIds.removeAll()
    }
}

public struct SGAdDetector {
    
    private static let officialAdTokens: [String] = [
        "erid:",
        "erid=",
        "erid ",
        "реклама.",
        "реклама ",
        "рекламодатель",
        "инн ",
        "#промо",
        "#реклама",
        "#promo",
        "#ad",
        "промо-пост",
        "промо пост"
    ]
    
    private static let maxAndCityAdKeywords: [String] = [
        "нашли для вас каналы",
        "нашли каналы твоего",
        "нашли каналы вашего",
        "каналы твоего города",
        "канал твоего города",
        "каналы вашего города",
        "канал вашего города",
        "подборка каналов",
        "папка с каналами",
        "папка от админа",
        "забирай папку",
        "приватная папка",
        "эксклюзивная папка",
        "ссылка на макс",
        "в макс",
        "вход только для жителей",
        "только для жителей",
        "доступ по ссылке",
        "ссылка действительна 24",
        "ссылка сгорит через",
        "подали заявку",
        "заявки принимаются",
        "мест осталось",
        "партнёрский материал",
        "партнерский материал",
        "на правах рекламы",
        "спонсорский пост",
        "рекламная интеграция"
    ]
    
    private static let casinoKeywords: [String] = [
        "казино",
        "casino",
        "vavada",
        "вавада",
        "1win",
        "1вин",
        "1xbet",
        "1хбет",
        "stake",
        "стэйк",
        "стейк",
        "luckybear",
        "драгонмани",
        "dragonmoney",
        "up-x",
        "upx",
        "catcasino",
        "mostbet",
        "мостбет",
        "melbet",
        "мелбет",
        "pin-up",
        "pinup",
        "пинап",
        "jetton"
    ]
    
    private static let gamblingPromoKeywords: [String] = [
        "промокод",
        "промокоды",
        "promocode",
        "promo code",
        "фриспин",
        "фриспины",
        "фриспинов",
        "freespin",
        "free spins",
        "вейджер",
        "джекпот",
        "jackpot",
        "занос",
        "заносы",
        "бонус за депозит",
        "бонус на депозит",
        "бездепозитный",
        "депозит",
        "депозита",
        "поднять бабла",
        "легкие деньги",
        "быстрый куш",
        "отыгрыш",
        "кэшбэк 20%"
    ]
    
    private static let schemeAndScamKeywords: [String] = [
        "lucky jet",
        "rocket queen",
        "сигналы mines",
        "сигналы lucky jet",
        "сигналы на mines",
        "схема обыгрыша",
        "схема заработка",
        "схемы заработка",
        "взлом mines",
        "взлом lucky jet",
        "бот на mines",
        "mines bot",
        "авиатор сигналы",
        "aviator bot",
        "раскрутка счета",
        "договорной матч",
        "договорные матчи",
        "арбитраж крипты",
        "связка p2p"
    ]
    
    private static let adButtonKeywords: [String] = [
        "🎰",
        "играть",
        "play",
        "забрать бонус",
        "получить бонус",
        "забрать приз",
        "забрать куш",
        "регистрация",
        "крутить",
        "spin",
        "испытать удачу",
        "открыть кейс",
        "подать заявку",
        "получить доступ",
        "вступить"
    ]

    private static var adCheckCache: [MessageId: Bool] = [:]
    private static let cacheLock = NSLock()

    public static func isAd(_ message: Message) -> Bool {
        cacheLock.lock()
        if let cached = adCheckCache[message.id] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = evaluateIsAd(message)

        cacheLock.lock()
        if adCheckCache.count > 1000 {
            adCheckCache.removeAll()
        }
        adCheckCache[message.id] = result
        cacheLock.unlock()

        return result
    }

    private static func evaluateIsAd(_ message: Message) -> Bool {
        // Only target channel messages
        guard message.id.peerId.namespace == Namespaces.Peer.CloudChannel else {
            return false
        }
        
        // Sponsored message attribute
        if message.adAttribute != nil {
            return true
        }
        
        var fullText = message.text.lowercased()
        
        // Check webpage content text
        for media in message.media {
            if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
                if let title = content.title {
                    fullText += " " + title.lowercased()
                }
                if let text = content.text {
                    fullText += " " + text.lowercased()
                }
                if let websiteName = content.websiteName {
                    fullText += " " + websiteName.lowercased()
                }
            }
        }
        
        // 1. Official ad token / ERID marker
        for token in officialAdTokens {
            if fullText.contains(token) {
                return true
            }
        }
        
        // 2. MAX ads & City channel selections & Scam folders
        for keyword in maxAndCityAdKeywords {
            if fullText.contains(keyword) {
                return true
            }
        }
        
        // 3. Slot machine emoji check
        let hasSlotEmoji = fullText.contains("🎰")
        
        // 4. Casino brand names
        var hasCasinoBrand = false
        for brand in casinoKeywords {
            if fullText.contains(brand) {
                hasCasinoBrand = true
                break
            }
        }
        
        // 5. Gambling promo words
        var hasGamblingPromo = false
        for promo in gamblingPromoKeywords {
            if fullText.contains(promo) {
                hasGamblingPromo = true
                break
            }
        }
        
        // 6. Schemes and bot scams
        for scheme in schemeAndScamKeywords {
            if fullText.contains(scheme) {
                return true
            }
        }
        
        if hasSlotEmoji && (hasCasinoBrand || hasGamblingPromo) {
            return true
        }
        
        if hasCasinoBrand && hasGamblingPromo {
            return true
        }
        
        // 7. Check inline reply markup buttons
        for attribute in message.attributes {
            if let replyMarkup = attribute as? ReplyMarkupMessageAttribute {
                for row in replyMarkup.rows {
                    for button in row.buttons {
                        let buttonTitle = button.title.lowercased()
                        
                        if buttonTitle.contains("🎰") {
                            return true
                        }
                        
                        for btnKeyword in adButtonKeywords {
                            if buttonTitle.contains(btnKeyword) {
                                if hasSlotEmoji || hasCasinoBrand || hasGamblingPromo {
                                    return true
                                }
                                if fullText.contains("бонус") || fullText.contains("канал") || fullText.contains("ссылк") || fullText.contains("город") || fullText.contains("рубл") {
                                    return true
                                }
                            }
                        }
                        
                        if case let .url(url) = button.action {
                            let urlLower = url.lowercased()
                            for brand in casinoKeywords {
                                if urlLower.contains(brand) {
                                    return true
                                }
                            }
                            if urlLower.contains("gamewin") || urlLower.contains("max.ru") || urlLower.contains("luckyjet") {
                                return true
                            }
                        }
                    }
                }
            }
        }
        
        return false
    }
}
