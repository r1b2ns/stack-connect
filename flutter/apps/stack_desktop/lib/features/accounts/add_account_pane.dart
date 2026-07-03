import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
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
/// ([ServiceKind.appStoreConnect]); there is no service selector. It exposes the
/// account in two interchangeable ways via a tab strip:
///
///   * **Form** — the manual credential form. Fields are rendered dynamically
///     from [credentialSchema]. The only single-line fields are the Issuer ID
///     and Key ID identifiers, shown in plain text (never obscured); the
///     `multiline` private key is a multi-line `.p8` box that can be typed in or
///     loaded from disk via the "Select .p8 file…" picker beneath it. The
///     `secret` flag still governs storage semantics in the core, it is just not
///     used to obscure these inputs.
///   * **Import .scexport** — picks an encrypted StackConnect export (`.scexport`)
///     plus its password, decrypts it through the core ([CoreGateway.decryptScexport])
///     into an [AccountExport] (whose `credentials` are already keyed to the App
///     Store Connect schema), then feeds it through the very same
///     validate-and-persist path as the form. Only Apple exports are accepted;
///     other provider types are rejected with a friendly message.
///
/// Both tabs share one submission/error model: the action row reads
/// `[Cancel] [Connect]` on the Form tab and `[Cancel] [Import]` on the Import
/// tab, the trailing primary action shows a progress ring while the controller
/// validates against the live service, and any [StackError] (a connect/validate
/// failure, a wrong `.scexport` password, or an unsupported export format) is
/// mapped via [stackErrorMessage] and surfaced in an [InfoBar]; the modal stays
/// put on failure and pops itself on success.
class AddAccountDialog extends ConsumerStatefulWidget {
  const AddAccountDialog({super.key});

  @override
  ConsumerState<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<AddAccountDialog> {
  final _labelController = TextEditingController();
  final _fieldControllers = <String, TextEditingController>{};

  /// Password for the `.scexport` import tab.
  final _passwordController = TextEditingController();

  static const _kind = ServiceKind.appStoreConnect;

  /// Active tab: 0 = Form, 1 = Import. Drives both the body and the action row.
  int _tabIndex = 0;

  /// Bytes of the picked `.scexport` file, or null until one is chosen.
  Uint8List? _scexportBytes;

  /// Display name of the picked `.scexport` file, or null until one is chosen.
  String? _scexportFileName;

  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _labelController.dispose();
    _passwordController.dispose();
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

  /// Whether the Import tab has everything it needs to attempt a decrypt.
  bool get _canImport =>
      _scexportBytes != null && _passwordController.text.isNotEmpty;

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

  /// Lets the user pick a `.p8` key file from disk and loads its text contents
  /// into the [fieldKey]'s controller, replacing whatever was there.
  ///
  /// Uses the sandbox-friendly [openFile] picker; the macOS
  /// `com.apple.security.files.user-selected.read-only` entitlement grants the
  /// read. A cancelled pick is a no-op. Read failures surface in [_errorMessage]
  /// rather than throwing, keeping the modal usable.
  Future<void> _pickP8File(String fieldKey) async {
    const group = XTypeGroup(
      label: 'App Store Connect key',
      extensions: ['p8'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    try {
      final contents = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _controllerFor(fieldKey).text = contents.trim();
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not read the selected file.');
    }
  }

  /// Lets the user pick a `.scexport` export from disk, reading its raw bytes
  /// into [_scexportBytes] (the decrypt happens later, in [_import]).
  ///
  /// Uses the same sandbox-friendly [openFile] picker as [_pickP8File]. A
  /// cancelled pick is a no-op; a read failure surfaces in [_errorMessage].
  Future<void> _pickScexportFile() async {
    const group = XTypeGroup(
      label: 'StackConnect export',
      extensions: ['scexport'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _scexportBytes = bytes;
        _scexportFileName = file.name;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not read the selected file.');
    }
  }

  /// Decrypts the picked `.scexport` through the core, then runs the imported
  /// credentials through the same validate-and-persist path as the manual form.
  ///
  /// The decrypt is a synchronous core call that throws [StackError] (`.auth` on
  /// a wrong password, `.decode` on an unsupported/invalid format), so it is
  /// guarded. Only Apple exports are importable here; other provider types are
  /// rejected before any account is created. On a successful add the modal pops.
  Future<void> _import() async {
    if (!_canImport) {
      setState(() => _errorMessage =
          'Select a .scexport file and enter its password before importing.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      // Synchronous core call; throws StackError on bad password / bad format.
      final export = ref.read(coreGatewayProvider).decryptScexport(
            bytes: _scexportBytes!,
            password: _passwordController.text,
          );

      if (export.providerType != 'apple') {
        if (mounted) {
          setState(() => _errorMessage =
              'Only App Store Connect accounts can be imported.');
        }
        return;
      }

      // The decrypted credentials are already keyed to the App Store Connect
      // schema, so they flow straight through the same validate-and-persist
      // path the manual form uses (live validation, then Keychain storage).
      await ref.read(accountsControllerProvider.notifier).addAccount(
            kind: _kind,
            label: export.name,
            secrets: export.credentials,
          );
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
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 660),
      title: const Text('Add account'),
      content: _buildTabs(schemaAsync),
      // The action row adapts to the active tab; see [_buildActions].
      actions: _buildActions(schema),
    );
  }

  /// The two-tab body: Form + Import.
  ///
  /// [TabView]'s body is laid out inside an `Expanded` of an internal `Column`,
  /// so it requires a bounded height from its parent. Inside [ContentDialog] the
  /// content sizes to its child (no incoming height constraint), so the
  /// [TabView] is wrapped in a fixed-height [SizedBox] to avoid an unbounded
  /// height assertion. The strip is configured to read as in-content tabs rather
  /// than closable document tabs: close buttons are never shown, the "new tab"
  /// (+) button is omitted (no `onNewPressed`), and tabs share width equally.
  Widget _buildTabs(AsyncValue<List<CredentialField>> schemaAsync) {
    return SizedBox(
      height: 460,
      child: TabView(
        currentIndex: _tabIndex,
        onChanged: _submitting
            ? null
            : (index) => setState(() {
                  _tabIndex = index;
                  // Reset the shared error so a stale message from one tab does
                  // not bleed into the other.
                  _errorMessage = null;
                }),
        closeButtonVisibility: CloseButtonVisibilityMode.never,
        tabWidthBehavior: TabWidthBehavior.equal,
        showScrollButtons: false,
        tabs: [
          Tab(
            text: const Text('Form'),
            body: schemaAsync.when(
              loading: () => const Center(child: ProgressRing()),
              error: (error, _) =>
                  Center(child: Text(stackErrorMessage(error))),
              data: _buildForm,
            ),
          ),
          Tab(
            text: const Text('Import .scexport'),
            body: _buildImportTab(),
          ),
        ],
      ),
    );
  }

  /// Builds the action row for the active tab.
  ///
  ///   * Tab 0 (Form): `[Cancel] [Connect]` — Connect is enabled once the schema
  ///     has resolved and no submission is in flight.
  ///   * Tab 1 (Import): `[Cancel] [Import]` — Import is enabled once a file is
  ///     picked and a password entered, and no submission is in flight.
  ///
  /// The trailing primary action shows a progress ring while submitting; Cancel
  /// is disabled mid-submission in both tabs.
  List<Widget> _buildActions(List<CredentialField>? schema) {
    final cancel = Button(
      onPressed: _submitting ? null : () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );

    final ring = const SizedBox(
      height: 18,
      width: 18,
      child: ProgressRing(strokeWidth: 2),
    );

    if (_tabIndex == 0) {
      return [
        cancel,
        FilledButton(
          onPressed: (schema != null && !_submitting)
              ? () => _submit(schema)
              : null,
          child: _submitting ? ring : const Text('Connect'),
        ),
      ];
    }

    return [
      cancel,
      FilledButton(
        onPressed: (_canImport && !_submitting) ? _import : null,
        child: _submitting ? ring : const Text('Import'),
      ),
    ];
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
            // The multiline field is the `.p8` private key. Offer a file picker
            // directly beneath it so the key can be loaded from disk instead of
            // being pasted by hand.
            if (field.multiline) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Button(
                  onPressed:
                      _submitting ? null : () => _pickP8File(field.key),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.open_file),
                      SizedBox(width: 8),
                      Text('Select .p8 file…'),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  /// The Import tab: pick a `.scexport`, enter its password, then [_import].
  ///
  /// Shares the single [_errorMessage]/[_submitting] model with the form, so the
  /// same [InfoBar] surfaces decrypt/validate failures here. The actual import
  /// is driven by the `[Import]` action in the footer (see [_buildActions]).
  Widget _buildImportTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            InfoBar(
              title: const Text('Could not import'),
              content: Text(_errorMessage!),
              severity: InfoBarSeverity.error,
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'A .scexport file is an encrypted StackConnect account export. '
            'Pick one and enter its password to import the account.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Button(
              onPressed: _submitting ? null : _pickScexportFile,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.open_file),
                  SizedBox(width: 8),
                  Text('Select .scexport file'),
                ],
              ),
            ),
          ),
          if (_scexportFileName != null) ...[
            const SizedBox(height: 8),
            Text(
              _scexportFileName!,
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
          const SizedBox(height: 16),
          InfoLabel(
            label: 'Password',
            child: TextBox(
              controller: _passwordController,
              obscureText: true,
              placeholder: 'Export password',
              enabled: !_submitting,
              // Keep the Import button's enabled state in sync as the user
              // types, since [_canImport] depends on the password.
              onChanged: (_) => setState(() {}),
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
