import Foundation
import SwiftSignalKit
import ManagedFile

private let queue = DispatchQueue(label: "app.swiftgram.ios.trace", qos: .utility)

private var sharedLogger: SGLogger?

private let binaryEventMarker: UInt64 = 0xcadebabef00dcafe

private func rootPathForBasePath(_ appGroupPath: String) -> String {
    return appGroupPath + "/telegram-data"
}

public class SGLogger {
    public let queue = Queue(name: "app.swiftgram.ios.log", qos: .utility)
    private let maxLength: Int = 2 * 1024 * 1024
    private let maxShortLength: Int = 1 * 1024 * 1024
    private let maxFiles: Int = 20
    
    public let rootPath: String
    public let basePath: String
    private var file: (ManagedFile, Int)?
    private var shortFile: (ManagedFile, Int)?
    
    public static let sgLogsPath = "/logs/app-logs-sg"
    
    public var logToFile: Bool = false
    public var logToConsole: Bool = false
    public var redactSensitiveData: Bool = true
    
    public static func setSharedLogger(_ logger: SGLogger) {
        sharedLogger = logger
    }
    
    public static var shared: SGLogger {
        if let sharedLogger = sharedLogger {
            return sharedLogger
        } else {
            let dummy = SGLogger(rootPath: "", basePath: "")
            dummy.logToFile = false
            dummy.logToConsole = false
            self.setSharedLogger(dummy)
            return dummy
        }
    }
    
    public init(rootPath: String, basePath: String) {
        self.rootPath = rootPath
        self.basePath = basePath
        self.logToFile = false
        self.logToConsole = false
    }
    
    public func log(_ tag: String, _ what: @autoclosure () -> String) {
        return
    }
}
