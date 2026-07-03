import 'package:stack_core_dart/stack_core_dart.dart';

/// A user-facing message derived from an [AsyncValue] error.
///
/// Branches on the [StackError] subclasses so the UI can show a friendly hint
/// instead of a raw exception. Non-[StackError] objects fall back to their
/// string form.
String stackErrorMessage(Object error) {
  return switch (error) {
    StackError_PendingAgreements() =>
      'Accept the App Store Connect agreements in the developer portal, then try again.',
    StackError_Auth(:final message) => 'Authentication failed: $message',
    StackError_InvalidCredentials() =>
      'Those credentials were rejected. Double-check the Key ID, Issuer ID and the .p8 contents.',
    StackError_Network() =>
      'Network error. Check your connection and try again.',
    StackError_Http(:final status, :final message) =>
      'Service error ($status): $message',
    StackError_Decode() =>
      'The service returned an unexpected response. Please try again.',
    StackError_Unsupported(:final message) => message,
    _ => error.toString(),
  };
}
