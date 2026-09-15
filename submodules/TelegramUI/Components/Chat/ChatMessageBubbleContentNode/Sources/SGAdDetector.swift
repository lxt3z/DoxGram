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
        "промо пост",
        "на правах рекламы",
        "партнёрский материал",
        "партнерский материал",
        "партнёрский пост",
        "партнерский пост",
        "спонсорский пост",
        "рекламная интеграция",
        "рекламная публикация",
        "рекламная пауза"
    ]
    
    private static let brandPromoTokens: [String] = [
        "@alfabank",
        "alfa.me",
        "alfabank.ru",
        "альфа-карта",
        "альфа карта",
        "альфакарта",
        "алиса ai",
        "алиса ии",
        "яндекс алиса",
        "яндекс станция",
        "chat.alice.yandex",
        "alice.yandex",
        "алису ai",
        "алисой ai"
    ]
    
    private static let personalAndChannelPromoKeywords: [String] = [
        "теперь в telegram",
        "теперь в телеграм",
        "теперь в тг",
        "теперь и в telegram",
        "теперь и в телеграм",
        "теперь и в тг",
        "переехал в telegram",
        "переехал в телеграм",
        "переехал в тг",
        "переходи в telegram",
        "переходите в telegram",
        "переходи в телеграм",
        "переходите в телеграм",
        "переходи в мой тг",
        "переходите в мой тг",
        "переходи в мой",
        "переходите в мой",
        "подписывайся на мой",
        "подписывайтесь на мой",
        "подпишись на мой",
        "создал свой канал",
        "создала свой канал",
        "открыл свой канал",
        "открыла свой канал",
        "завёл свой канал",
        "завел свой канал",
        "завела свой канал",
        "запустил свой канал",
        "запустила свой канал",
        "веду свой канал",
        "веду свой тг",
        "мой личный канал",
        "мой авторский канал",
        "в моем личном канале",
        "в моём личном канале",
        "в моем авторском",
        "в моём авторском",
        "авторский канал",
        "авторский блог",
        "мой личный блог",
        "выкладываю туторы",
        "выкладывает туторы",
        "делюсь туторами",
        "мои туторы",
        "бесплатные туторы",
        "туториалы по",
        "сливаю курсы",
        "сливы курсов",
        "слив курса",
        "авторский курс",
        "авторские курсы",
        "бесплатный курс",
        "бесплатный интенсив",
        "бесплатный вебинар",
        "бесплатный марафон",
        "записаться на курс",
        "записаться на интенсив",
        "научу зарабатывать",
        "научит зарабатывать",
        "беру на наставничество",
        "возьму на наставничество",
        "наставничество до результата",
        "мест на обучение",
        "места на обучение",
        "обучаю заработку",
        "вход бесплатный первые",
        "вход свободный еще",
        "вход свободный ещё",
        "только первые 100",
        "ссылка в закрепе",
        "ссылка в описании канала",
        "ссылка в профиле"
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
        
        for attribute in message.attributes {
            if let textEntities = attribute as? TextEntitiesMessageAttribute {
                for entity in textEntities.entities {
                    if case let .TextUrl(url) = entity.type {
                        fullText += " " + url.lowercased()
                    }
                }
            }
        }
        
        // 1. Official ad token / ERID marker
        for token in officialAdTokens {
            if fullText.contains(token) {
                return true
            }
        }
        
        // 2. Brand promos (Alfa-Bank, Alice AI, etc.)
        for token in brandPromoTokens {
            if fullText.contains(token) {
                return true
            }
        }
        
        let isAlfaBankMention = fullText.contains("альфа-банк") || fullText.contains("альфа банк") || fullText.contains("альфабанк")
        if isAlfaBankMention {
            let bankPromoTerms = ["карт", "кешбэк", "кэшбэк", "бонус", "оформи", "заказ", "скидк", "бесплатн", "процент", "акци", "ссылк", "рубл"]
            for term in bankPromoTerms {
                if fullText.contains(term) {
                    return true
                }
            }
        }
        
        if fullText.contains("алиса") && (fullText.contains("нейросеть") || fullText.contains("искусственный интеллект") || fullText.contains("чат-бот") || fullText.contains("чат бот") || fullText.contains("попробуй") || fullText.contains("яндекс")) {
            return true
        }
        
        // 3. Personal channel, courses, tutors & creator promo
        for keyword in personalAndChannelPromoKeywords {
            if fullText.contains(keyword) {
                return true
            }
        }
        
        // 4. MAX ads & City channel selections & Scam folders
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
                            if urlLower.contains("gamewin") || urlLower.contains("max.ru") || urlLower.contains("luckyjet") || urlLower.contains("alfa.me") || urlLower.contains("alfabank") || urlLower.contains("alice.yandex") {
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
