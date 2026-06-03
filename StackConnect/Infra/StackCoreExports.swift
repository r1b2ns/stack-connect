// Re-exports the shared modules across the entire app module so existing source
// files keep working without per-file `import` statements.
// - StackCore: storage layer, logging, App Group constant.
// - StackProtocols: shared protocol definitions (PersistentStorable, etc.),
//   which moved here from StackCore so they can be reused on non-Apple platforms.
@_exported import StackCore
@_exported import StackProtocols
