import 'package:fluent_ui/fluent_ui.dart';
import 'package:stack_core_dart/stack_core_dart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shell/selection.dart';
import 'accounts_dialog.dart';
import 'app_info_provider.dart';
import 'license_dialog.dart';

/// The GitHub repository the About section links to.
final _githubUri = Uri.parse('https://github.com/r1b2ns/stack-connect');

/// Opens the Settings modal as a Fluent [ContentDialog].
///
/// Mirrors the native iOS `SettingsView`: a grouped list of General / About /
/// Danger sections plus a version footer. Nested sub-views (Accounts, License,
/// and confirmations) are themselves [ContentDialog]s shown on top, so the
/// Settings dialog acts as a small hub. Returns when the user dismisses it.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const SettingsDialog(),
  );
}

/// The Settings modal content. See [showSettingsDialog].
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
      title: Text(l10n.settingsTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGeneralSection(context),
            const SizedBox(height: 20),
            _buildAboutSection(context),
            const SizedBox(height: 20),
            _buildDangerSection(context, ref),
            const SizedBox(height: 24),
            _buildFooter(context, ref),
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }

  // MARK: - General

  Widget _buildGeneralSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SettingsSection(
      header: l10n.settingsGeneral,
      children: [
        _SettingsRow(
          icon: FluentIcons.people,
          iconColor: Colors.blue,
          label: l10n.accountsTitle,
          showChevron: true,
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const AccountsDialog(),
          ),
        ),
      ],
    );
  }

  // MARK: - About

  Widget _buildAboutSection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _SettingsSection(
      header: l10n.settingsAbout,
      children: [
        _SettingsRow(
          icon: FluentIcons.code,
          iconColor: Colors.purple,
          label: l10n.github,
          trailing: const Icon(FluentIcons.open_in_new_window, size: 12),
          onPressed: () => _openGitHub(context),
        ),
        _SettingsRow(
          icon: FluentIcons.page,
          iconColor: Colors.grey,
          label: l10n.license,
          showChevron: true,
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const LicenseDialog(),
          ),
        ),
      ],
    );
  }

  /// Opens the GitHub repo in the external browser. On failure surfaces an
  /// [InfoBar] rather than silently swallowing the error.
  Future<void> _openGitHub(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final launched =
        await launchUrl(_githubUri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      await displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: Text(l10n.couldNotOpenGitHub),
          content: Text('$_githubUri'),
          severity: InfoBarSeverity.warning,
          onClose: close,
        ),
      );
    }
  }

  // MARK: - Danger

  Widget _buildDangerSection(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _SettingsSection(
      header: l10n.settingsDanger,
      children: [
        _SettingsRow(
          icon: FluentIcons.delete,
          iconColor: Colors.red,
          label: l10n.deleteAllAccounts,
          labelColor: Colors.red,
          onPressed: () => _confirmDeleteAll(context, ref),
        ),
      ],
    );
  }

  /// Shows the destructive confirmation; on confirm removes every connected
  /// account, clears the selection, and closes the Settings modal.
  ///
  /// There is no bulk-delete API on [AccountsController], so this iterates the
  /// current records and calls `removeAccount(id)` for each — each call drops
  /// that account's secrets + record and rebuilds the controller state. The
  /// loop snapshots the record ids first so it does not iterate a list that is
  /// mutating underneath it.
  Future<void> _confirmDeleteAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(l10n.deleteAllAccounts),
        content: Text(l10n.deleteAllAccountsBody),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteAll),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final controller = ref.read(accountsControllerProvider.notifier);
    final ids = (ref.read(accountsControllerProvider).valueOrNull ??
            const <AccountRecord>[])
        .map((record) => record.id)
        .toList();

    for (final id in ids) {
      await controller.removeAccount(id);
    }

    // Drop any lingering detail selection so the shell falls back to the empty
    // placeholder rather than a now-deleted account.
    ref.read(selectionControllerProvider.notifier).clear();

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  // MARK: - Footer

  Widget _buildFooter(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final infoAsync = ref.watch(appInfoProvider);
    final text = infoAsync.maybeWhen(
      data: (info) => l10n.appVersionFooter(info.version, info.build),
      orElse: () => l10n.appName,
    );
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[100],
        ),
      ),
    );
  }
}

/// A titled group of [_SettingsRow]s, mirroring an iOS `Section`.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.header, required this.children});

  final String header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            header,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[100],
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// A single tappable settings row: a tinted leading icon, a label, and an
/// optional trailing chevron/glyph — the desktop equivalent of an iOS row.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onPressed,
    this.labelColor,
    this.showChevron = false,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback onPressed;
  final bool showChevron;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final effectiveTrailing = trailing ??
        (showChevron
            ? const Icon(FluentIcons.chevron_right, size: 12)
            : null);

    return HoverButton(
      onPressed: onPressed,
      builder: (context, states) {
        final hovered = states.isHovered || states.isPressed;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: hovered
                ? FluentTheme.of(context).resources.subtleFillColorSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: labelColor),
                ),
              ),
              ?effectiveTrailing,
            ],
          ),
        );
      },
    );
  }
}
