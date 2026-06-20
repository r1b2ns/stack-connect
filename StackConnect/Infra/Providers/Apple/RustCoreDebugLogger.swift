import Foundation
import StackCoreRust

/// Forwards the Rust core's HTTP debug traces (cURL + pretty-JSON request/response)
/// straight to the Xcode console. Used ONLY when the `useRustCoreDebugLogging`
/// launch flag is set. Uses `print` rather than `Log.print` (os.Logger) because the
/// unified logger truncates long messages — cURL bodies and JSON responses must
/// come through whole and unredacted for debugging.
final class RustCoreDebugLogger: DebugLogger {
    func log(message: String) {
        print(message)
    }
}
