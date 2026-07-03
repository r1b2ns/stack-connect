import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:stack_core_dart/stack_core_dart.dart';

import '../../core/service_kind_label.dart';
import '../../core/stack_error_message.dart';

/// Full-screen form to connect a new account.
///
/// The service picker only offers `ServiceKind.appStoreConnect` today. The
/// credential fields are rendered dynamically from [credentialSchema]; `secret`
/// fields are obscured and `multiline` fields (the `.p8`) use a multi-line box.
///
/// On submit a spinner is shown while the controller validates the credentials
/// against the live service. On [StackError] the mapped message is shown via a
/// [SnackBar] and the form stays put; on success the route pops back to the
/// accounts list.
class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key});

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _fieldControllers = <String, TextEditingController>{};

  ServiceKind _kind = ServiceKind.appStoreConnect;
  bool _submitting = false;

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

  Future<void> _submit(List<CredentialField> schema) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    setState(() => _submitting = true);

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
      if (!mounted) return;
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(stackErrorMessage(error))),
        );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schemaAsync = ref.watch(
      _credentialSchemaProvider(_kind),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add account'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _submitting ? null : () => context.go('/'),
        ),
      ),
      body: schemaAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(stackErrorMessage(error))),
        data: (schema) => _buildForm(schema),
      ),
    );
  }

  Widget _buildForm(List<CredentialField> schema) {
    return AbsorbPointer(
      absorbing: _submitting,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<ServiceKind>(
              initialValue: _kind,
              decoration: const InputDecoration(
                labelText: 'Service',
                border: OutlineInputBorder(),
              ),
              items: ServiceKind.values
                  .map(
                    (kind) => DropdownMenuItem(
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. My Company',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            for (final field in schema) ...[
              _CredentialFieldInput(
                field: field,
                controller: _controllerFor(field.key),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: _submitting ? null : () => _submit(schema),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialFieldInput extends StatelessWidget {
  const _CredentialFieldInput({
    required this.field,
    required this.controller,
  });

  final CredentialField field;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: field.secret && !field.multiline,
      minLines: field.multiline ? 4 : 1,
      maxLines: field.multiline ? 10 : 1,
      decoration: InputDecoration(
        labelText: field.label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'Required' : null,
    );
  }
}

/// The credential schema for [kind], surfaced as a provider so the form can show
/// loading/error states uniformly. Reads the gateway directly (the schema is a
/// synchronous core call wrapped in a future for ergonomics).
final _credentialSchemaProvider =
    FutureProvider.family<List<CredentialField>, ServiceKind>((ref, kind) async {
  final gateway = ref.watch(coreGatewayProvider);
  return gateway.credentialSchema(kind);
});
