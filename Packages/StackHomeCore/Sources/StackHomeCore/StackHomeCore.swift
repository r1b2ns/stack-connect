import Foundation

// StackHomeCore — the Foundation-pure shared Home logic core.
//
// The original skeleton declared a placeholder `enum StackHomeCore {}` so the
// empty target would compile. That has been removed: the module now carries
// real public types (Home value models, widget value types + the pure
// `HomeWidget` protocol, the 3 widget data types). The placeholder also
// shadowed the module name, so `StackHomeCore.InReviewWidget` (the iOS
// observable adapter qualifying the core type) failed to resolve — dropping it
// lets module-qualified references resolve to the module.
