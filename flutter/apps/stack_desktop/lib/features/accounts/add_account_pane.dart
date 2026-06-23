import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/stack_error_message.dart';

/// Opens the "connect a new account" modal as a Fluent [ContentDialog].
///
/// Mirrors [showSettingsDialog]: a top-level entry point that calls [showDialog]
/// with a [ContentDialog]-based widget. Returns when the user dismisses the
/// modal — either by cancelling or after a successful connection. On success the
/// accounts rail rebuilds from [accountsControllerProvider] automatically, so the
/// new account appears without any explicit selection bookkeeping here.
Future<void> showAddAccountDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const AddAccountDialog(),
  );
}

/// The "connect a new account" modal content. See [showAddAccountDialog].
///
/// This modal always connects an App Store Connect account
/// ([ServiceKind.appStoreConnect]); there is no service selector. Credential
/// fields are rendered dynamically from [credentialSchema]. The only single-line
/// fields here are the Issuer ID and Key ID identifiers, which are shown in plain
/// text (never obscured); the `multiline` private key is rendered as a multi-line
/// `.p8` box. The `secret` flag still governs storage semantics in the core, it is
/// just not used to obscure these inputs. The action row reads `[Cancel] [Connect]`
/// left-to-right; Connect shows a progress ring while the controller validates
/// against the live service. On [StackError] the mapped message shows in an
/// [InfoBar] and the form stays put, on success the dialog pops itself.
class AddAccountDialog extends ConsumerStatefulWidget {
  const AddAccountDialog({super.key});

  @override
  ConsumerState<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<AddAccountDialog> {
  final _labelController = TextEditingController();
  final _fieldControllers = <String, TextEditingController>{};

  static const _kind = ServiceKind.appStoreConnect;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _labelController.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key) =>
      _fieldControllers.putIfAbsent(key, TextEditingController.new);

  bool _isComplete(List<CredentialField> schema) {
    if (_labelController.text.trim().isEmpty) return false;
    for (final field in schema) {
      if (_controllerFor(field.key).text.trim().isEmpty) return false;
    }
    return true;
  }

  Future<void> _submit(List<CredentialField> schema) async {
    if (!_isComplete(schema)) {
      setState(() => _errorMessage = 'Fill in every field before connecting.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final secrets = <String, String>{
      for (final field in schema)
        field.key: _controllerFor(field.key).text.trim(),
    };

    try {
      await ref.read(accountsControllerProvider.notifier).addAccount(
            kind: _kind,
            label: _labelController.text.trim(),
            secrets: secrets,
          );
      // On success close the modal; the accounts rail rebuilds from
      // [accountsControllerProvider] and surfaces the new account itself.
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = stackErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schemaAsync = ref.watch(_credentialSchemaProvider(_kind));
    // Resolved schema, or null while the provider is still loading/errored.
    // Connect stays disabled until this is non-null.
    final schema = schemaAsync.valueOrNull;

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
      title: const Text('Add account'),
      content: schemaAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(child: Text(stackErrorMessage(error))),
        data: _buildForm,
      ),
      // Rendered in order, so the row reads `[Cancel] [Connect]` left-to-right.
      actions: [
        Button(
          // Disable Cancel while a connection is in flight, matching the field
          // disabling below, so the modal cannot be dismissed mid-submission.
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Enabled only once the credential schema has resolved and no
          // submission is in flight. While submitting, show a progress ring.
          onPressed: (schema != null && !_submitting)
              ? () => _submit(schema)
              : null,
          child: _submitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Text('Connect'),
        ),
      ],
    );
  }

  Widget _buildForm(List<CredentialField> schema) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            InfoBar(
              title: const Text('Could not connect'),
              content: Text(_errorMessage!),
              severity: InfoBarSeverity.error,
            ),
            const SizedBox(height: 16),
          ],
          InfoLabel(
            label: 'Label',
            child: TextBox(
              controller: _labelController,
              placeholder: 'e.g. My Company',
              enabled: !_submitting,
            ),
          ),
          const SizedBox(height: 16),
          for (final field in schema) ...[
            InfoLabel(
              label: field.label,
              child: TextBox(
                controller: _controllerFor(field.key),
                // Issuer ID and Key ID are identifiers, not passwords, so they
                // are shown in plain text. The `.p8` key is multiline and was
                // never obscured either, so no field in this modal is masked.
                obscureText: false,
                minLines: field.multiline ? 4 : 1,
                maxLines: field.multiline ? 10 : 1,
                enabled: !_submitting,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

/// The credential schema for [kind], surfaced as a provider so the form can show
/// loading/error states uniformly.
final _credentialSchemaProvider =
    FutureProvider.family<List<CredentialField>, ServiceKind>((ref, kind) async {
  final gateway = ref.watch(coreGatewayProvider);
  return gateway.credentialSchema(kind);
});
