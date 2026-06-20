import 'package:flutter/material.dart';

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
    final body = switch (_index) {
      0 => const AccountsScreen(),
      _ => const _SettingsPlaceholder(),
    };

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(child: Text('Settings coming soon')),
    );
  }
}
