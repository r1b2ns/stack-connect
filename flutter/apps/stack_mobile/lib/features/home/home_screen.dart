import 'package:flutter/material.dart';
import 'package:stack_core_dart/stack_core_dart.dart' show AppLocalizations;

import '../accounts/accounts_screen.dart';

/// Home shell: a single bottom [NavigationBar] with the Accounts tab and a
/// Settings placeholder. The selected tab swaps the body in place; deeper
/// navigation (apps, reviews) pushes full routes on top of this shell.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final body = switch (_index) {
      0 => const AccountsScreen(),
      _ => const _SettingsPlaceholder(),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.account_circle_outlined),
            selectedIcon: const Icon(Icons.account_circle),
            label: l10n.accountsTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.settingsTitle,
          ),
        ],
      ),
    );
  }
}

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: Center(child: Text(l10n.settingsComingSoon)),
    );
  }
}
