import 'package:flutter/material.dart';

import 'screens/add_screen.dart';
import 'screens/balance_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/transactions_screen.dart';
import 'services/api_client.dart';
import 'services/app_repository.dart';
import 'services/preferences_service.dart';
import 'theme.dart';
import 'widgets/floating_nav_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExpenseTrackerApp());
}

class ExpenseTrackerApp extends StatefulWidget {
  const ExpenseTrackerApp({super.key});

  @override
  State<ExpenseTrackerApp> createState() => _ExpenseTrackerAppState();
}

class _ExpenseTrackerAppState extends State<ExpenseTrackerApp> {
  late final PreferencesService _prefs;
  late final AppRepository _repo;
  late final ApiClient _api;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _repo = AppRepository();
    _api = ApiClient();
    _init();
  }

  Future<void> _init() async {
    _prefs = await PreferencesService.create();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _prefs.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Expense Tracker',
          debugShowCheckedModeBanner: false,
          theme: lightTheme(),
          darkTheme: darkTheme(),
          themeMode: mode,
          home: MainScaffold(repo: _repo, prefs: _prefs, api: _api),
        );
      },
    );
  }
}

/// Root shell with a floating bottom nav bar switching between the five pages.
class MainScaffold extends StatefulWidget {
  const MainScaffold({
    super.key,
    required this.repo,
    required this.prefs,
    required this.api,
  });

  final AppRepository repo;
  final PreferencesService prefs;
  final ApiClient api;

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;
  late final List<Widget> _pages;
  // Bumped by Settings after a user-settings save; Home listens and re-fetches.
  final ValueNotifier<int> _dashboardRev = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeScreen(repo: widget.repo, api: widget.api, dashboardRev: _dashboardRev),
      const BalanceScreen(),
      const AddScreen(),
      const TransactionsScreen(),
      SettingsScreen(repo: widget.repo, prefs: widget.prefs, api: widget.api, dashboardRev: _dashboardRev),
    ];
    _ensureUserSettings();
  }

  /// POST /user-settings once on first launch with the device's timezone +
  /// currency so /dashboard doesn't return 404. Fire-and-forget; if it fails
  /// (e.g. API unreachable) it retries on the next launch.
  Future<void> _ensureUserSettings() async {
    if (widget.prefs.userSettingsInitialized) return;
    try {
      final userId = await widget.repo.getUserId();
      if (userId.isEmpty) return;
      await widget.api.ensureUserSettings(userId);
      await widget.prefs.setUserSettingsInitialized(true);
    } catch (_) {
      // Retry next launch.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: FloatingNavBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
