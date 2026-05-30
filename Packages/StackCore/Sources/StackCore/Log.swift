import Foundation
import os

public enum Log {
    public static let subsystem = Bundle.main.bundleIdentifier ?? "missing"

    public static let print = Logger(subsystem: subsystem, category: "UI")
}
