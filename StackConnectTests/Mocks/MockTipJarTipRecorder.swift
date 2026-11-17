import Foundation
@testable import StackConnect

/// Counts the completed tips reported by the tip jar.
@MainActor
final class MockTipJarTipRecorder: TipJarTipRecording {

    private(set) var recordedTipCount = 0

    func recordCompletedTip() {
        recordedTipCount += 1
    }
}
