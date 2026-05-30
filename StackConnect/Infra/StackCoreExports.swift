// Re-exports the StackCore shared module (storage layer, logging, App Group
// constant) across the entire app module so existing source files keep working
// without per-file `import StackCore` statements.
@_exported import StackCore
