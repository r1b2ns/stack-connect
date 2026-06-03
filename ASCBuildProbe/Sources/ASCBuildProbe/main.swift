import Foundation
import AppStoreConnect_Swift_SDK

// Reference a public type so the import is type-checked and linked, not stripped.
// Building/running this on Windows answers the phase-3 SDK gate.
let configurationType = APIConfiguration.self
print("AppStoreConnect-Swift-SDK imported and linked OK: \(configurationType)")
