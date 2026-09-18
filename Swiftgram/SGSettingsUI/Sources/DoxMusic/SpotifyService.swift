import Foundation
import UIKit
import AuthenticationServices
import CommonCrypto
import AVFoundation
import SGLogging

public final class SpotifyService: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = SpotifyService()
    
    // Default DoxGram client id (or user-configurable via settings)
    private let defaultClientId = "0d20d778d91c4be8bf97825529f798be"
    private let redirectUri = "tg://spotify-callback"
    
    private let tokenKey = "dox_spotify_access_token"
    private let refreshTokenKey = "dox_spotify_refresh_token"
    private let tokenExpiryKey = "dox_spotify_token_expiry"
    
    private var authSession: ASWebAuthenticationSession?
    private var codeVerifier: String?
    private var avPlayer: AVPlayer?
    
    public var customClientId: String {
        get {
            return UserDefaults.standard.string(forKey: "dox_spotify_custom_client_id") ?? self.defaultClientId
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "dox_spotify_custom_client_id")
        }
    }
    
    public var isAuthorized: Bool {
        return self.accessToken != nil
    }
    
    public var accessToken: String? {
        get {
            guard let token = UserDefaults.standard.string(forKey: self.tokenKey) else {
                return nil
            }
            let expiry = UserDefaults.standard.double(forKey: self.tokenExpiryKey)
            if Date().timeIntervalSince1970 > expiry {
                self.refreshAccessToken()
            }
            return token
        }
        set {
            UserDefaults.standard.set(newValue, forKey: self.tokenKey)
        }
    }
    
    private var refreshToken: String? {
        get {
            return UserDefaults.standard.string(forKey: self.refreshTokenKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: self.refreshTokenKey)
        }
    }
    
    private override init() {
        super.init()
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if #available(iOS 15.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let window = windowScene.keyWindow ?? windowScene.windows.first {
                return window
            }
        }
        if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
    
    // MARK: - PKCE OAuth Flow
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var buffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &buffer)
        }
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    public func startAuthorization(completion: @escaping (Bool, String?) -> Void) {
        let verifier = self.generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = self.generateCodeChallenge(from: verifier)
        
        let clientId = self.customClientId
        let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing user-top-read user-library-read"
        
        guard let encodedScopes = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let authUrl = URL(string: "https://accounts.spotify.com/authorize?client_id=\(clientId)&response_type=code&redirect_uri=\(self.redirectUri)&code_challenge_method=S256&code_challenge=\(challenge)&scope=\(encodedScopes)") else {
            completion(false, "Invalid authorization URL")
            return
        }
        
        self.authSession = ASWebAuthenticationSession(url: authUrl, callbackURLScheme: "tg") { [weak self] callbackUrl, error in
            guard let self = self else { return }
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            guard let callbackUrl = callbackUrl,
                  let components = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                completion(false, "Authorization cancelled or code not found")
                return
            }
            
            self.exchangeCodeForToken(code: code, completion: completion)
        }
        
        self.authSession?.presentationContextProvider = self
        self.authSession?.prefersEphemeralWebBrowserSession = false
        self.authSession?.start()
    }
    
    private func exchangeCodeForToken(code: String, completion: @escaping (Bool, String?) -> Void) {
        guard let verifier = self.codeVerifier,
              let tokenUrl = URL(string: "https://accounts.spotify.com/api/token") else {
            completion(false, "Verifier missing")
            return
        }
        
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let clientId = self.customClientId
        let bodyParams = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": self.redirectUri,
            "code_verifier": verifier
        ]
        
        request.httpBody = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                DispatchQueue.main.async { completion(false, "Failed to parse token") }
                return
            }
            
            let expiresIn = json["expires_in"] as? Double ?? 3600.0
            let refreshToken = json["refresh_token"] as? String
            
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            UserDefaults.standard.set(Date().timeIntervalSince1970 + expiresIn - 60.0, forKey: self.tokenExpiryKey)
            
            DispatchQueue.main.async {
                completion(true, nil)
            }
        }.resume()
    }
    
    public func refreshAccessToken(completion: ((Bool) -> Void)? = nil) {
        guard let refreshToken = self.refreshToken,
              let tokenUrl = URL(string: "https://accounts.spotify.com/api/token") else {
            completion?(false)
            return
        }
        
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let clientId = self.customClientId
        let bodyParams = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else {
                completion?(false)
                return
            }
            let expiresIn = json["expires_in"] as? Double ?? 3600.0
            if let newRefresh = json["refresh_token"] as? String {
                self.refreshToken = newRefresh
            }
            self.accessToken = newAccessToken
            UserDefaults.standard.set(Date().timeIntervalSince1970 + expiresIn - 60.0, forKey: self.tokenExpiryKey)
            completion?(true)
        }.resume()
    }
    
    public func logout() {
        UserDefaults.standard.removeObject(forKey: self.tokenKey)
        UserDefaults.standard.removeObject(forKey: self.refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: self.tokenExpiryKey)
    }
    
    // MARK: - Search & Wave Recommendations
    
    public func search(query: String, completion: @escaping ([SGDoxMusicTrack], String?) -> Void) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion([], nil)
            return
        }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.spotify.com/v1/search?q=\(encoded)&type=track&limit=25") else {
            completion([], "Invalid search query")
            return
        }
        
        self.makeAuthenticatedRequest(url: url) { [weak self] data, error in
            guard let self = self else { return }
            if let error = error {
                completion([], error)
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tracksObj = json["tracks"] as? [String: Any],
                  let items = tracksObj["items"] as? [[String: Any]] else {
                completion([], "Failed to parse Spotify results")
                return
            }
            
            let tracks = self.parseTracks(from: items)
            completion(tracks, nil)
        }
    }
    
    public func fetchWaveTracks(basedOn track: SGDoxMusicTrack?, completion: @escaping ([SGDoxMusicTrack]) -> Void) {
        var endpoint = "https://api.spotify.com/v1/recommendations?limit=25"
        if let trackId = track?.id, track?.source == .spotify {
            endpoint += "&seed_tracks=\(trackId)"
        } else {
            endpoint += "&seed_genres=pop,hip-hop,electronic"
        }
        
        guard let url = URL(string: endpoint) else {
            completion([])
            return
        }
        
        self.makeAuthenticatedRequest(url: url) { [weak self] data, _ in
            guard let self = self,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["tracks"] as? [[String: Any]] else {
                completion([])
                return
            }
            let tracks = self.parseTracks(from: items)
            completion(tracks)
        }
    }
    
    private func parseTracks(from items: [[String: Any]]) -> [SGDoxMusicTrack] {
        var result: [SGDoxMusicTrack] = []
        for item in items {
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String else {
                continue
            }
            let artistsList = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let artistName = artistsList.joined(separator: ", ")
            
            let albumObj = item["album"] as? [String: Any]
            let albumName = (albumObj?["name"] as? String) ?? ""
            let images = (albumObj?["images"] as? [[String: Any]])
            let artworkUrl = images?.first?["url"] as? String
            
            let durationMs = (item["duration_ms"] as? Double) ?? 0.0
            let previewUrl = item["preview_url"] as? String
            let uri = item["uri"] as? String
            
            result.append(SGDoxMusicTrack(
                id: id,
                title: name,
                artist: artistName,
                album: albumName,
                artworkUrl: artworkUrl,
                duration: durationMs / 1000.0,
                previewUrl: previewUrl,
                source: .spotify,
                spotifyUri: uri
            ))
        }
        return result
    }
    
    private func makeAuthenticatedRequest(url: URL, completion: @escaping (Data?, String?) -> Void) {
        guard let token = self.accessToken else {
            completion(nil, "Not logged in to Spotify")
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                self.refreshAccessToken { success in
                    if success {
                        self.makeAuthenticatedRequest(url: url, completion: completion)
                    } else {
                        DispatchQueue.main.async { completion(nil, "Session expired, please log in again") }
                    }
                }
                return
            }
            
            if let error = error {
                DispatchQueue.main.async { completion(nil, error.localizedDescription) }
                return
            }
            DispatchQueue.main.async { completion(data, nil) }
        }.resume()
    }
    
    public func play(track: SGDoxMusicTrack, completion: @escaping (Bool) -> Void) {
        if let preview = track.previewUrl, let url = URL(string: preview) {
            self.avPlayer?.pause()
            let playerItem = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: playerItem)
            self.avPlayer = player
            player.play()
            completion(true)
            return
        }
        
        // Universal deep link / Spotify app launcher
        if let uri = track.spotifyUri, let url = URL(string: uri), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
            return
        }
        completion(false)
    }
    
    public func pause() {
        self.avPlayer?.pause()
    }
    
    public func resume() {
        self.avPlayer?.play()
    }
}
