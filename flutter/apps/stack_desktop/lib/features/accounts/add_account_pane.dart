import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/service_kind_label.dart';
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
/// The service combo only offers `ServiceKind.appStoreConnect` today. Credential
/// fields are rendered dynamically from [credentialSchema] (`secret` → obscured,
/// `multiline` → multi-line `.p8` box). Submitting shows a progress ring while
/// the controller validates against the live service; on [StackError] the mapped
/// message shows in an [InfoBar] and the form stays put, on success the dialog
/// pops itself.
class AddAccountDialog extends ConsumerStatefulWidget {
  const AddAccountDialog({super.key});

  @override
  ConsumerState<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<AddAccountDialog> {
  final _labelController = TextEditingController();
  final _fieldControllers = <String, TextEditingController>{};

  ServiceKind _kind = ServiceKind.appStoreConnect;
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

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
      title: const Text('Add account'),
      content: schemaAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (error, _) => Center(child: Text(stackErrorMessage(error))),
        data: _buildForm,
      ),
      actions: [
        Button(
          // Disable Cancel while a connection is in flight, matching the field
          // disabling below, so the modal cannot be dismissed mid-submission.
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
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
            label: 'Service',
            child: ComboBox<ServiceKind>(
              value: _kind,
              isExpanded: true,
              items: ServiceKind.values
                  .map(
                    (kind) => ComboBoxItem(
                      value: kind,
                      child: Text(kind.label),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (kind) {
                      if (kind != null) setState(() => _kind = kind);
                    },
            ),
          ),
          const SizedBox(height: 16),
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
                obscureText: field.secret && !field.multiline,
                minLines: field.multiline ? 4 : 1,
                maxLines: field.multiline ? 10 : 1,
                enabled: !_submitting,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _submitting ? null : () => _submit(schema),
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ),
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
