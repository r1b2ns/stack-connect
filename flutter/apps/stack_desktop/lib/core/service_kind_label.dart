import 'package:stack_core_dart/stack_core_dart.dart';

/// Human-readable label for a [ServiceKind] in the Fluent UI.
extension ServiceKindLabel on ServiceKind {
  String get label => switch (this) {
        ServiceKind.appStoreConnect => 'App Store Connect',
      };
}
