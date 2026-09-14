import Foundation

public final class SGUrlSanitizer {

    // Tracking query parameter names to remove
    private static let knownTrackingParams: Set<String> = [
        "fbclid", "fbadid",
        "gclid", "gclsrc", "dclid", "gad_source", "gbraid", "wbraid",
        "yclid", "ym_debug", "_openstat",
        "igshid",
        "si", "feature",
        "ref_src", "ref_url",
        "mc_cid", "mc_eid", "mkt_tok",
        "_r", "_d", "tt_from", "is_from_webapp",
        "spm", "scm", "aff_platform", "aff_trace_key", "track_id",
        "msclkid", "epik", "rdt_cid", "zanpid"
    ]

    // Known IP loggers and grabbers
    private static let ipLoggerDomains: Set<String> = [
        "iplogger.org", "iplogger.com", "iplogger.ru", "iplogger.io", "iplogger.net", "iplogger.info",
        "2ip.ru", "2ip.io", "ip-tracker.org", "whatismyipaddress.com",
        "grabify.link", "grabify.org", "grabify.icu",
        "yip.su", "iplis.ru", "02ip.ru", "ezstat.ru",
        "blasze.tk", "linkdrop.ru", "ps3cfw.com", "curiouscat.qa",
        "ip-score.com", "whoer.net", "speedtest.net", "iplocation.net"
    ]

    // Known URL shorteners that can mask IP grabbers
    private static let shortenerDomains: Set<String> = [
        "bit.ly", "tinyurl.com", "cutt.ly", "is.gd", "clck.ru",
        "t.co", "goo.gl", "ow.ly", "buff.ly", "adf.ly", "bc.vc",
        "v.gd", "shorturl.at", "rb.gy", "qr.ae", "s.id"
    ]

    public struct SuspiciousCheckResult {
        public let isSuspicious: Bool
        public let isIpGrabber: Bool
        public let isShortener: Bool
        public let domain: String
        public let warningDescription: String?

        public init(isSuspicious: Bool, isIpGrabber: Bool, isShortener: Bool, domain: String, warningDescription: String?) {
            self.isSuspicious = isSuspicious
            self.isIpGrabber = isIpGrabber
            self.isShortener = isShortener
            self.domain = domain
            self.warningDescription = warningDescription
        }
    }

    /// Checks if the URL is an IP logger, suspicious shortener, or dangerous domain
    public static func checkSuspicious(urlString: String, checkIpLoggers: Bool = true, warnOnAllExternal: Bool = false) -> SuspiciousCheckResult {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
            return SuspiciousCheckResult(isSuspicious: false, isIpGrabber: false, isShortener: false, domain: "", warningDescription: nil)
        }

        if checkIpLoggers {
            // Match against known IP grabbers
            for grabber in ipLoggerDomains {
                if host == grabber || host.hasSuffix("." + grabber) {
                    return SuspiciousCheckResult(
                        isSuspicious: true,
                        isIpGrabber: true,
                        isShortener: false,
                        domain: host,
                        warningDescription: "IP-logger / Grabber"
                    )
                }
            }

            // Match against shorteners
            for shortener in shortenerDomains {
                if host == shortener || host.hasSuffix("." + shortener) {
                    return SuspiciousCheckResult(
                        isSuspicious: true,
                        isIpGrabber: false,
                        isShortener: true,
                        domain: host,
                        warningDescription: "URL Shortener"
                    )
                }
            }
        }

        if warnOnAllExternal {
            // Telegram-internal domains are safe
            let telegramHosts = ["t.me", "telegram.org", "telegram.me", "telegram.dog", "fragment.com"]
            let isTelegram = telegramHosts.contains { host == $0 || host.hasSuffix("." + $0) }
            if !isTelegram {
                return SuspiciousCheckResult(
                    isSuspicious: true,
                    isIpGrabber: false,
                    isShortener: false,
                    domain: host,
                    warningDescription: "External Link"
                )
            }
        }

        return SuspiciousCheckResult(isSuspicious: false, isIpGrabber: false, isShortener: false, domain: host, warningDescription: nil)
    }

    /// Strips tracking parameters and unwraps redirect proxies
    public static func sanitize(urlString: String) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }

        // 1. Unwrap redirects if applicable
        if let unwrapped = unwrapRedirect(components: components) {
            return sanitize(urlString: unwrapped)
        }

        // 2. Clean query items
        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return urlString
        }

        let cleanedItems = queryItems.filter { item in
            let lowerName = item.name.lowercased()
            if lowerName.hasPrefix("utm_") {
                return false
            }
            if knownTrackingParams.contains(lowerName) {
                return false
            }
            return true
        }

        components.queryItems = cleanedItems.isEmpty ? nil : cleanedItems

        return components.url?.absoluteString ?? urlString
    }

    /// Unwraps Google, VK, YouTube and other redirect wrappers
    private static func unwrapRedirect(components: URLComponents) -> String? {
        guard let host = components.host?.lowercased() else {
            return nil
        }

        let path = components.path.lowercased()

        // Google: google.com/url?q=... or google.com/url?url=...
        if host.contains("google.") && path == "/url" {
            if let target = components.queryItems?.first(where: { $0.name == "q" || $0.name == "url" })?.value {
                return target
            }
        }

        // VK: vk.com/away.php?to=...
        if (host == "vk.com" || host == "m.vk.com") && path == "/away.php" {
            if let target = components.queryItems?.first(where: { $0.name == "to" })?.value {
                return target
            }
        }

        // YouTube: youtube.com/redirect?q=...
        if host.contains("youtube.com") && path == "/redirect" {
            if let target = components.queryItems?.first(where: { $0.name == "q" })?.value {
                return target
            }
        }

        // Facebook: l.facebook.com/l.php?u=... or lm.facebook.com/l.php?u=...
        if host.contains("facebook.com") && path == "/l.php" {
            if let target = components.queryItems?.first(where: { $0.name == "u" })?.value {
                return target
            }
        }

        // Instagram: l.instagram.com/?u=...
        if host.contains("instagram.com") {
            if let target = components.queryItems?.first(where: { $0.name == "u" })?.value {
                return target
            }
        }

        return nil
    }
}
