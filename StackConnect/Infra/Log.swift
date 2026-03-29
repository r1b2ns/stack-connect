import Foundation
import os

//#if DEBUG
    enum Log {
        static let subsystem = Bundle.main.bundleIdentifier ?? "missing"

        static let print = Logger(subsystem: subsystem, category: "UI")
    }
//#else
//    /// Release builds: use the disabled OSLog sink so all log calls are dropped at runtime
//    /// while keeping the same call-site surface (privacy annotations still compile).
//    enum Log {
//        static let subsystem = Bundle.main.bundleIdentifier ?? "missing"
//
//        static let print = Logger(OSLog.disabled)
//    }
//#endif
