import Foundation
import SGLogging
import SwiftSignalKit


extension SGLogger {
    public func collectLogs(prefix: String? = nil) -> Signal<[(String, String)], NoError> {
        return .single([])
    }
    
    public func collectLogs(basePath: String) -> Signal<[(String, String)], NoError> {
        return .single([])
    }
}
