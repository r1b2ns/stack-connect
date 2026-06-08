import Foundation
import StackHomeCore

// Phase 4 · Block F · T-F08 — Add Account Options routing logic.
//
// Pure-logic model that encapsulates the routing decisions made by the
// WindowsAddAccountOptionsView. Extracted into WindowsAppCore so it can
// be unit-tested without depending on SwiftCrossUI views.
//
// The view delegates its "Create New" / "Import" / visibility decisions to
// this model; the coordinator push calls happen in the view layer but the
// _what to push_ decision lives here, fully testable.

/// The outcome of tapping "Create New" for a given provider.
public enum AddAccountCreateRoute: Hashable, Sendable {
    case createAppleAccount
    case createFirebaseAccount
}

/// Pure-logic model for the Add Account Options screen.
/// Determines which options are available and what navigation targets they
/// map to, based on the selected `ProviderType`.
public struct WindowsAddAccountOptionsModel: Sendable {

    /// The provider type this screen was invoked for.
    public let provider: ProviderType

    public init(provider: ProviderType) {
        self.provider = provider
    }

    /// Whether the "Import .scexport" option should be shown.
    /// Only Apple accounts support .scexport import (AC-1, TC-F020).
    public var showImportOption: Bool {
        provider == .apple
    }

    /// The route to push when "Create New" is tapped (AC-2, TC-F022, TC-F023).
    /// Returns `nil` for unsupported providers (e.g. `.googlePlay`).
    public var createRoute: AddAccountCreateRoute? {
        switch provider {
        case .apple:
            return .createAppleAccount
        case .firebase:
            return .createFirebaseAccount
        case .googlePlay:
            return nil
        }
    }
}
