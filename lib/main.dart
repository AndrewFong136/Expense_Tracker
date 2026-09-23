import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_repository.dart';
import 'services/preferences_service.dart';
import 'theme.dart';

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
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _repo = AppRepository();
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
          home: HomeScreen(repo: _repo, prefs: _prefs),
        );
      },
    );
  }
}
