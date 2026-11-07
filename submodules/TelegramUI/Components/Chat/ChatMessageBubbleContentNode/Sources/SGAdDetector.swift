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
    
    public func hide(_ id: MessageId) {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.revealedMessageIds.remove(id)
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
        "#erid",
        "реклама. ооо",
        "реклама. ип",
        "реклама. пао",
        "реклама. ао",
        "реклама. зао",
        "реклама. тоо",
        "реклама. чао",
        "реклама: ооо",
        "реклама: ип",
        "реклама: пао",
        "реклама: ао",
        "реклама: зао",
        "реклама. инн",
        "реклама: инн",
        "информация о рекламодателе",
        "сведения о рекламодателе",
        "рекламодатель:",
        "рекламодатель ооо",
        "рекламодатель ип",
        "рекламодатель ао",
        "рекламодатель пао",
        "рекламодатель инн",
        "инн: ",
        " инн: ",
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
    
    private static let vpnHookKeywords: [String] = [
        "не работает тг",
        "не работает телеграм",
        "не работает telegram",
        "глушат тг",
        "глушат телеграм",
        "глушат telegram",
        "блокируют тг",
        "блокируют телеграм",
        "блокируют telegram",
        "замедляют тг",
        "замедляют телеграм",
        "замедляют telegram",
        "сбои в тг",
        "сбои в телеграм",
        "сбои в telegram",
        "сбой в тг",
        "сбой в телеграм",
        "сбой в telegram",
        "тг не грузит",
        "телеграм не грузит",
        "telegram не грузит",
        "тг зависает",
        "телеграм зависает",
        "плохо работает тг",
        "плохо работает телеграм",
        "если тормозит тг",
        "если тормозит телеграм",
        "если не грузит тг",
        "если не грузит телеграм"
    ]

    private static let vpnDirectKeywords: [String] = [
        "freenet",
        "фринет",
        "создай собственный ускоритель интернета",
        "собственный ускоритель интернета",
        "ускоритель интернета",
        "ускоритель тг",
        "ускоритель телеграм",
        "ускоритель telegram",
        "быстрый впн",
        "лучший впн",
        "бесплатный впн",
        "впн для тг",
        "впн для телеграм",
        "впн для telegram",
        "впн, который работает",
        "скачать впн",
        "подключить впн",
        "наш впн",
        "личный впн",
        "впн бот",
        "vpn бот",
        "vpn bot",
        "бесплатный vpn",
        "лучший vpn",
        "быстрый vpn",
        "outline vpn",
        "протокол vless",
        "конфиг vless",
        "ключ vless",
        "ключи vless",
        "подписка vless",
        "shadowsocks vpn",
        "v2ray vpn"
    ]

    private static let bookmakerKeywords: [String] = [
        "fonbet",
        "фонбет",
        "фон бет",
        "winline",
        "винлайн",
        "вин лайн",
        "betboom",
        "бетбум",
        "бет бум",
        "лига ставок",
        "лигаставок",
        "ligastavok",
        "олимпбет",
        "олимп бет",
        "olimpbet",
        "paribet",
        "парибет",
        "бк леон",
        "leonbets",
        "leonbet",
        "marathonbet",
        "марафонбет",
        "1xставка",
        "1xstavka",
        "betcity",
        "бетсити",
        "тенниси",
        "tennisi"
    ]

    private static let sportsAndBettingKeywords: [String] = [
        "фрибет",
        "фрибеты",
        "фрибетов",
        "freebet",
        "freebets",
        "ставка на матч",
        "ставки на матч",
        "ставка на спорт",
        "ставки на спорт",
        "ставка на футбол",
        "ставки на футбол",
        "прогноз на матч",
        "прогнозы на матч",
        "прогноз на футбол",
        "прогнозы на футбол",
        "прогнозы на спорт",
        "прогноз на спорт",
        "железобетонный экспресс",
        "жб экспресс",
        "жб прогноз",
        "экспресс на сегодня",
        "экспресс на матч",
        "проходной экспресс",
        "договорной матч",
        "договорные матчи",
        "договорной исход",
        "линия на матч",
        "коэффициент на матч",
        "кэф на матч",
        "тотал на матч",
        "фора на матч",
        "купон на матч",
        "поднял на матче",
        "поднял на футболе",
        "занос на матче",
        "занос на ставках",
        "поднял на ставках",
        "выигрыш со ставки",
        "бесплатная ставка",
        "бесплатные ставки",
        "прямая трансляция матча",
        "трансляция матча",
        "трансляция футбола",
        "смотреть матч онлайн",
        "смотреть матч бесплатно",
        "где смотреть матч",
        "ссылка на трансляцию матча",
        "смотреть футбол онлайн",
        "смотреть футбол бесплатно",
        "прямой эфир матча",
        "футбольная трансляция",
        "футбольные трансляции",
        "трансляция боя",
        "смотреть бой онлайн",
        "ufc прямая трансляция"
    ]

    private static let bookmakerUrlDomains: [String] = [
        "fon.bet", "fonbet", "winline", "betboom", "ligastavok",
        "olimp.bet", "olimpbet", "pari.ru", "paribet", "leon.ru",
        "leonbets", "leonbet", "marathonbet", "1xstavka", "betcity",
        "tennisi"
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
        "вступить",
        "забрать фрибет",
        "получить фрибет",
        "сделать ставку",
        "смотреть матч",
        "трансляция",
        "прямой эфир",
        "смотреть онлайн",
        "подключить vpn",
        "подключить впн",
        "скачать vpn",
        "скачать впн"
    ]

    private static let adultAndLeakPromoKeywords: [String] = [
        "ai-игрушка",
        "ai игрушка",
        "ии-игрушка",
        "ии игрушка",
        "твоя личная ai",
        "твоя личная ии",
        "виртуальная девушка",
        "ai девушка",
        "ии девушка",
        "нейросеть без цензуры",
        "чат-бот 18+",
        "чат бот 18+",
        "раздеватор",
        "раздень подругу",
        "раздевает по фото",
        "раздеть по фото",
        "найти девушку мечты в ии",
        "найти девушку мечты",
        "девушку мечты в ии",
        "девушка мечты в ии",
        "девушка мечты",
        "все фуллы будут в старом канале",
        "все фуллы будут старом канале",
        "все фулы будут",
        "фуллы в старом канале",
        "фуллы в старом",
        "с этой шлюшкой",
        "этой шлюшкой",
        "шлюшкой",
        "как эту s#x-ии еще не удалили",
        "как эту sex-ии еще не удалили",
        "как эту секс-ии еще не удалили",
        "s#x-ии",
        "s#x ии",
        "sex-ии",
        "секс-ии",
        "sex ии",
        "секс ии",
        "s#x",
        "s*x",
        "слив тик-токерши",
        "слив тиктокерши",
        "сливы тиктокерш",
        "слив онлифанс",
        "слив onlyfans",
        "сливы онлифанс",
        "сливы блогерш",
        "слив стримерш",
        "сливы стримерш",
        "сливы школьниц",
        "слитые фото",
        "слитый архив",
        "слив переписок",
        "слив домашнего",
        "слив архива",
        "сливы малолеток",
        "слив малолетки",
        "интимки",
        "интим фото",
        "интим видео",
        "фулл в закрепе",
        "фулл по ссылке",
        "полное видео в закрепе",
        "продолжение в источнике",
        "продолжение по ссылке",
        "без цензуры в закрепе",
        "видео без цензуры",
        "запрещенка",
        "запрещёнка",
        "порно видео",
        "порнуха"
    ]

    private static func mapMathScalarToAscii(_ val: UInt32) -> Character? {
        let ranges: [(ClosedRange<UInt32>, UInt32)] = [
            (0x1D400...0x1D419, 65), // Bold A-Z
            (0x1D41A...0x1D433, 97), // Bold a-z
            (0x1D434...0x1D44D, 65), // Italic A-Z
            (0x1D44E...0x1D467, 97), // Italic a-z
            (0x1D468...0x1D481, 65), // Bold Italic A-Z
            (0x1D482...0x1D49B, 97), // Bold Italic a-z
            (0x1D49C...0x1D4B5, 65), // Script A-Z
            (0x1D4B6...0x1D4CF, 97), // Script a-z
            (0x1D4D0...0x1D4E9, 65), // Bold Script A-Z
            (0x1D4EA...0x1D503, 97), // Bold Script a-z
            (0x1D504...0x1D51D, 65), // Fraktur A-Z
            (0x1D51E...0x1D537, 97), // Fraktur a-z
            (0x1D538...0x1D551, 65), // Double-struck A-Z
            (0x1D552...0x1D56B, 97), // Double-struck a-z
            (0x1D56C...0x1D585, 65), // Bold Fraktur A-Z
            (0x1D586...0x1D59F, 97), // Bold Fraktur a-z
            (0x1D5A0...0x1D5B9, 65), // Sans-serif A-Z
            (0x1D5BA...0x1D5D3, 97), // Sans-serif a-z
            (0x1D5D4...0x1D5ED, 65), // Sans-serif Bold A-Z
            (0x1D5EE...0x1D607, 97), // Sans-serif Bold a-z
            (0x1D608...0x1D621, 65), // Sans-serif Italic A-Z
            (0x1D622...0x1D63B, 97), // Sans-serif Italic a-z
            (0x1D63C...0x1D655, 65), // Sans-serif Bold Italic A-Z
            (0x1D656...0x1D66F, 97), // Sans-serif Bold Italic a-z
            (0x1D670...0x1D689, 65), // Monospace A-Z
            (0x1D68A...0x1D6A3, 97), // Monospace a-z
            (0x1D7CE...0x1D7D7, 48), // Digits 0-9
            (0x1D7D8...0x1D7E1, 48),
            (0x1D7E2...0x1D7EB, 48),
            (0x1D7EC...0x1D7F5, 48),
            (0x1D7F6...0x1D7FF, 48)
        ]
        for (range, base) in ranges {
            if range.contains(val) {
                if let scalar = UnicodeScalar(base + (val - range.lowerBound)) {
                    return Character(scalar)
                }
            }
        }
        return nil
    }

    private static func normalizeFontsAndHomoglyphs(_ text: String) -> (asciiText: String, cyrillicText: String) {
        var asciiChars: [Character] = []
        asciiChars.reserveCapacity(text.count)
        
        for scalar in text.unicodeScalars {
            let val = scalar.value
            if val >= 0x1D400 && val <= 0x1D7FF {
                if let mapped = mapMathScalarToAscii(val) {
                    asciiChars.append(mapped)
                    continue
                }
            } else if val >= 0xFF01 && val <= 0xFF5E {
                if let scalarAscii = UnicodeScalar(val - 0xFEE0) {
                    asciiChars.append(Character(scalarAscii))
                    continue
                }
            } else if val >= 0x24B6 && val <= 0x24CF {
                if let scalarAscii = UnicodeScalar(val - 0x24B6 + 65) {
                    asciiChars.append(Character(scalarAscii))
                    continue
                }
            } else if val >= 0x24D0 && val <= 0x24E9 {
                if let scalarAscii = UnicodeScalar(val - 0x24D0 + 97) {
                    asciiChars.append(Character(scalarAscii))
                    continue
                }
            }
            asciiChars.append(Character(scalar))
        }
        
        var lowered = String(asciiChars).lowercased()
        
        // Collapse symbol insertion like s#x -> sex, s*x -> sex, v.p.n -> vpn, v_p_n -> vpn
        let symbolsToCollapse: [Character] = ["#", "*", "_", "-", ".", "/", "@", "$", "!", "—"]
        for sym in symbolsToCollapse {
            lowered = lowered.replacingOccurrences(of: String(sym), with: "")
        }
        
        // Homoglyphs to Cyrillic
        let latinToCyr: [Character: Character] = [
            "a": "а", "b": "б", "c": "с", "e": "е", "k": "к", "m": "м",
            "h": "н", "o": "о", "p": "р", "t": "т", "x": "х", "y": "у"
        ]
        var cyrChars: [Character] = []
        cyrChars.reserveCapacity(lowered.count)
        for ch in lowered {
            cyrChars.append(latinToCyr[ch] ?? ch)
        }
        let cyrillicFolded = String(cyrChars)
        
        return (lowered, cyrillicFolded)
    }

    private static func normalizeLeetspeak(_ text: String) -> String {
        let hasPotentialLeetspeak = text.unicodeScalars.contains { scalar in
            let v = scalar.value
            return (v >= 48 && v <= 57) || (v >= 97 && v <= 122) || (v >= 65 && v <= 90)
        }
        if !hasPotentialLeetspeak {
            return text
        }
        
        var result = text.lowercased()
        
        let digitMap: [Character: Character] = [
            "0": "о",
            "1": "и",
            "3": "з",
            "4": "ч",
            "6": "б",
            "8": "в"
        ]
        var chars: [Character] = []
        chars.reserveCapacity(result.count)
        for ch in result {
            if let mapped = digitMap[ch] {
                chars.append(mapped)
            } else {
                chars.append(ch)
            }
        }
        result = String(chars)
        
        let latinToCyrillic: [(String, String)] = [
            ("sl", "сл"),
            ("sh", "ш"),
            ("ch", "ч"),
            ("a", "а"),
            ("b", "б"),
            ("c", "с"),
            ("e", "е"),
            ("k", "к"),
            ("m", "м"),
            ("h", "н"),
            ("o", "о"),
            ("p", "р"),
            ("r", "р"),
            ("s", "с"),
            ("t", "т"),
            ("u", "у"),
            ("x", "х"),
            ("y", "у")
        ]
        for (lat, cyr) in latinToCyrillic {
            if result.contains(lat) {
                result = result.replacingOccurrences(of: lat, with: cyr)
            }
        }
        
        return result
    }

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

        // Do not cache false if webpage preview is still pending
        var hasPendingWebpage = false
        for media in message.media {
            if let webpage = media as? TelegramMediaWebpage, case .Pending = webpage.content {
                hasPendingWebpage = true
                break
            }
        }

        if !hasPendingWebpage || result {
            cacheLock.lock()
            if adCheckCache.count > 1000 {
                adCheckCache.removeAll()
            }
            adCheckCache[message.id] = result
            cacheLock.unlock()
        }

        return result
    }

    private static func evaluateIsAd(_ message: Message) -> Bool {
        let isChannel = message.id.peerId.namespace == Namespaces.Peer.CloudChannel
        let isGroup = message.id.peerId.namespace == Namespaces.Peer.CloudGroup
        guard isChannel || isGroup else {
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
        
        let normalizedText = normalizeLeetspeak(fullText)
        let (fontAscii, cyrillicFolded) = normalizeFontsAndHomoglyphs(fullText)
        let allVariants = [fullText, normalizedText, fontAscii, cyrillicFolded]
        
        // Adult, leaks & AI girlfriend spam (with font, homoglyphs and leetspeak normalization)
        for keyword in adultAndLeakPromoKeywords {
            if allVariants.contains(where: { $0.contains(keyword) }) {
                return true
            }
        }

        // White lists / "Белые списки" spam check (with context check to avoid false positives on legitimate mentions)
        let hasWhiteListsMention = allVariants.contains(where: { $0.contains("белые списки") || $0.contains("белый список") || $0.contains("белых списков") || $0.contains("белых списках") })
        if hasWhiteListsMention {
            let whiteListPromoContext = [
                "обход", "блокировк", "доступ", "инструкци", "подключ", "vpn", "впн", "vless", "outline",
                "бот", "bot", "ссылк", "переходи", "канал", "вступай", "t.me/", "трафик", "сервер", "конфиг",
                "купить", "бесплатно", "забирай", "настройк", "прокси", "proxy"
            ]
            let hasPromoAction = allVariants.contains(where: { text in
                whiteListPromoContext.contains(where: { text.contains($0) })
            }) || message.attributes.contains(where: { $0 is ReplyMarkupMessageAttribute })
            if hasPromoAction {
                return true
            }
        }

        // VPN promotion check
        let hasVpnWord = allVariants.contains(where: { $0.contains("vpn ") || $0.contains(" vpn") || $0.contains("впн ") || $0.contains(" впн") })
        if hasVpnWord {
            let vpnPromoContext = [
                "подключ", "бот", "bot", "скачать", "быстрый", "бесплатн", "лучший", "vless", "outline", "shadowsocks",
                "wireguard", "v2ray", "amnezia", "сервер", "конфиг", "доступ", "трафик", "интернет", "прокси", "proxy",
                "канал", "ссылк", "переходи", "t.me/", "забирай", "скидк", "рубл", "руб/", "руб.", "месяц", "год", "безлимит"
            ]
            if allVariants.contains(where: { text in vpnPromoContext.contains(where: { text.contains($0) }) })
                || message.attributes.contains(where: { $0 is ReplyMarkupMessageAttribute }) {
                return true
            }
        }
        
        let hasLeakOrAdultTerm = normalizedText.contains("слив") || normalizedText.contains("порн") || normalizedText.contains("интим") || normalizedText.contains("онлифанс") || normalizedText.contains("раздеват")
        if hasLeakOrAdultTerm {
            let spamContext = ["ссылк", "переход", "канал", "закреп", "источник", "бот", "bot", "t.me", "http", "👉", "👇", "доступ", "архив", "папк", "бесплатн", "продолжен"]
            for ctx in spamContext {
                if fullText.contains(ctx) || normalizedText.contains(ctx) {
                    return true
                }
            }
            if message.attributes.contains(where: { $0 is ReplyMarkupMessageAttribute }) {
                return true
            }
        }
        
        // 1. Official ad token / ERID marker
        for token in officialAdTokens {
            if allVariants.contains(where: { $0.contains(token) }) {
                return true
            }
        }
        
        for rawLine in fullText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if line == "реклама" || line == "реклама." || line == "реклама:" || line == "#реклама" || line == "реклама от автора" {
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
        
        // 5. VPN ads & disguised "TG not working?" promos
        for keyword in vpnDirectKeywords {
            if allVariants.contains(where: { $0.contains(keyword) }) {
                return true
            }
        }
        
        for hook in vpnHookKeywords {
            if fullText.contains(hook) {
                let vpnRelatedIndicators = ["?", "vpn", "впн", "proxy", "прокси", "vless", "outline", "shadowsocks", "wireguard", "v2ray", "бот", "bot", "подключ", "забирай", "ссылк", "переходи", "решение", "настроить", "инструкци", "канал"]
                for indicator in vpnRelatedIndicators {
                    if fullText.contains(indicator) {
                        return true
                    }
                }
                if !message.media.isEmpty || message.attributes.contains(where: { $0 is ReplyMarkupMessageAttribute }) {
                    return true
                }
            }
        }
        
        // 6. Bookmakers, sports betting, match live streams & sports casino
        for bookmaker in bookmakerKeywords {
            if fullText.contains(bookmaker) {
                return true
            }
        }
        
        for keyword in sportsAndBettingKeywords {
            if fullText.contains(keyword) {
                return true
            }
        }
        
        // 7. Slot machine emoji check
        let hasSlotEmoji = fullText.contains("🎰")
        
        // 8. Casino brand names
        var hasCasinoBrand = false
        for brand in casinoKeywords {
            if fullText.contains(brand) {
                hasCasinoBrand = true
                break
            }
        }
        
        // 9. Gambling promo words
        var hasGamblingPromo = false
        for promo in gamblingPromoKeywords {
            if fullText.contains(promo) {
                hasGamblingPromo = true
                break
            }
        }
        
        // 10. Schemes and bot scams
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
        
        // 11. Check inline reply markup buttons
        for attribute in message.attributes {
            if let replyMarkup = attribute as? ReplyMarkupMessageAttribute {
                for row in replyMarkup.rows {
                    for button in row.buttons {
                        let buttonTitle = button.title.lowercased()
                        
                        let instantAdButtons = [
                            "🎰", "забрать фрибет", "получить фрибет", "сделать ставку",
                            "подключить vpn", "подключить впн", "скачать vpn", "скачать впн",
                            "смотреть матч", "смотреть онлайн"
                        ]
                        for btn in instantAdButtons {
                            if buttonTitle.contains(btn) {
                                return true
                            }
                        }
                        
                        for btnKeyword in adButtonKeywords {
                            if buttonTitle.contains(btnKeyword) {
                                if hasSlotEmoji || hasCasinoBrand || hasGamblingPromo {
                                    return true
                                }
                                if fullText.contains("бонус") || fullText.contains("канал") || fullText.contains("ссылк") || fullText.contains("город") || fullText.contains("рубл") || fullText.contains("матч") || fullText.contains("футбол") || fullText.contains("vpn") || fullText.contains("впн") || fullText.contains("тг") || fullText.contains("телеграм") {
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
                            for bookmaker in bookmakerUrlDomains {
                                if urlLower.contains(bookmaker) {
                                    return true
                                }
                            }
                            if urlLower.contains("gamewin") || urlLower.contains("max.ru") || urlLower.contains("luckyjet") || urlLower.contains("alfa.me") || urlLower.contains("alfabank") || urlLower.contains("alice.yandex") || urlLower.contains("vless") || urlLower.contains("outline") {
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
