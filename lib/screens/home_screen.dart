import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_repository.dart';
import '../services/preferences_service.dart';
import '../widgets/app_list_tile.dart';
import '../widgets/permission_banner.dart';
import '../widgets/section_card.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repo, required this.prefs});

  final AppRepository repo;
  final PreferencesService prefs;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final AppRepository _repo = widget.repo;
  late final PreferencesService _prefs = widget.prefs;

  // App data
  List<AppInfo> _allApps = const [];
  List<AppInfo> _filteredApps = const [];
  final Set<String> _selectedApps = {};

  // Settings
  bool _serviceEnabled = false;
  String _webhookUrl = '';
  final TextEditingController _webhookUrlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  // Permissions
  bool _hasNotificationAccess = false;
  bool _hasAppNotificationsEnabled = false;
  bool _hasLocationAlwaysEnabled = false;

  // Loading state
  bool _isLoading = true;

  // Debounce timers
  Timer? _searchDebounce;
  Timer? _webhookDebounce;
  Timer? _selectionDebounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _webhookDebounce?.cancel();
    _selectionDebounce?.cancel();
    _webhookUrlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------- Init flow ----------------
  Future<void> _loadInitial() async {
    // 1. Settings (synchronous prefs reads, no await needed but kept for clarity)
    _serviceEnabled = _prefs.serviceEnabled;
    _webhookUrl = _prefs.webhookUrl;
    _webhookUrlController.text = _webhookUrl;
    _selectedApps.addAll(_prefs.selectedApps);

    // 2. Cached apps (instant if available)
    final cached = await _repo.getCachedApps();
    if (cached.isNotEmpty) {
      _allApps = cached;
      _applyFilter();
      if (mounted) setState(() => _isLoading = false);
      _preloadIconsFor(cached.take(40).map((a) => a.packageName).toList());
    }

    // 3. Permissions + fresh installed apps (in parallel)
    await Future.wait([
      _checkPermissions(),
      _loadInstalledApps(),
    ]);

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadInstalledApps() async {
    try {
      final apps = await _repo.getInstalledApps();
      if (!mounted) return;
      // Merge-update: preserve selection state; replace the list with the
      // fresh data (already sorted with selected apps first on the Kotlin
      // side). If the cached list was already showing, this just refreshes
      // without a visible flicker because the leading entries match.
      final previous = {for (final a in _allApps) a.packageName: a};
      bool changed = apps.length != _allApps.length;
      final merged = <AppInfo>[];
      for (final a in apps) {
        merged.add(a);
        if (previous[a.packageName]?.appName != a.appName) {
          changed = true;
        }
      }
      if (changed || _allApps.isEmpty) {
        _allApps = merged;
        _applyFilter();
        if (mounted) setState(() {});
      }
      _preloadIconsFor(merged.take(40).map((a) => a.packageName).toList());
    } on Exception {
      // Swallow — cached list (if any) stays visible.
    }
  }

  Future<void> _preloadIconsFor(List<String> packages) async {
    await _repo.preloadIcons(packages);
    // Preload is async; notifiers fire and affected tiles rebuild themselves.
  }

  // ---------------- Permissions ----------------
  Future<void> _checkPermissions() async {
    final notif = await _repo.isNotificationListenerAccessEnabled();
    final appNotif = await _repo.isAppNotificationEnabled();
    final loc = await _repo.isLocationAlwaysEnabled();

    if (!mounted) return;
    setState(() {
      _hasNotificationAccess = notif;
      _hasAppNotificationsEnabled = appNotif;
      _hasLocationAlwaysEnabled = loc;
    });

    if (_hasNotificationAccess && _serviceEnabled) {
      await _repo.rebindListener();
    }
    await _syncSettingsToAndroid();
  }

  Future<void> _requestAppNotifications() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      final result = await Permission.notification.request();
      if (!result.isGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Notification permission is required to show the enabled pop-up.')),
        );
      }
    }
  }

  Future<void> _requestLocationAlways() async {
    PermissionStatus status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        AppSettings.openAppSettings();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Location permission is required for precise tracking.')),
        );
      }
      return;
    }

    status = await Permission.locationAlways.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) {
        AppSettings.openAppSettings();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'For background location, allow "All the time" in settings.')),
        );
      }
    }
  }

  Future<void> _requestAllMissingPermissions() async {
    if (!_hasAppNotificationsEnabled) {
      await _requestAppNotifications();
    }
    if (!_hasNotificationAccess) {
      await _repo.requestNotificationListenerAccess();
    }
    if (!_hasLocationAlwaysEnabled) {
      await _requestLocationAlways();
    }
    await _checkPermissions();
  }

  // ---------------- Settings changes ----------------
  Future<void> _onServiceToggled(bool value) async {
    setState(() => _serviceEnabled = value);
    await _prefs.setServiceEnabled(value);
    if (value &&
        (!_hasNotificationAccess ||
            !_hasLocationAlwaysEnabled ||
            !_hasAppNotificationsEnabled)) {
      await _requestAllMissingPermissions();
    }
    await _syncSettingsToAndroid();
    await _checkPermissions();
  }

  void _onWebhookChanged(String value) {
    _webhookUrl = value;
    _webhookDebounce?.cancel();
    _webhookDebounce = Timer(const Duration(milliseconds: 500), () async {
      await _prefs.setWebhookUrl(value);
      await _syncSettingsToAndroid();
    });
  }

  void _onAppToggled(String packageName, bool value) {
    setState(() {
      if (value) {
        _selectedApps.add(packageName);
      } else {
        _selectedApps.remove(packageName);
      }
    });
    _scheduleSelectionSave();
  }

  void _selectAll() {
    setState(() {
      for (final a in _filteredApps) {
        _selectedApps.add(a.packageName);
      }
    });
    _scheduleSelectionSave();
  }

  void _deselectAll() {
    setState(() {
      for (final a in _filteredApps) {
        _selectedApps.remove(a.packageName);
      }
    });
    _scheduleSelectionSave();
  }

  /// Debounce selection saves so rapid toggles coalesce into a single
  /// broadcast + prefs write.
  void _scheduleSelectionSave() {
    _selectionDebounce?.cancel();
    _selectionDebounce = Timer(const Duration(milliseconds: 400), () async {
      await _prefs.setSelectedApps(_selectedApps);
      await _syncSettingsToAndroid();
    });
  }

  Future<void> _syncSettingsToAndroid() async {
    final map = {for (final p in _selectedApps) p: true};
    await _repo.sendSettingsToAndroid(
      serviceEnabled: _serviceEnabled,
      webhookUrl: _webhookUrl,
      selectedApps: map,
    );
  }

  // ---------------- Search ----------------
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _activeQuery = value;
      _applyFilter();
      if (mounted) setState(() {});
    });
  }

  void _applyFilter() {
    final q = _activeQuery.trim().toLowerCase();
    if (q.isEmpty) {
      _filteredApps = _allApps;
      return;
    }
    _filteredApps = _allApps
        .where((a) =>
            a.appName.toLowerCase().contains(q) ||
            a.packageName.toLowerCase().contains(q))
        .toList(growable: false);
  }

  // ---------------- Build ----------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsAppNotif = !_hasAppNotificationsEnabled;
    final needsLocation = !_hasLocationAlwaysEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(prefs: _prefs),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (needsAppNotif || needsLocation) ...[
                  PermissionBanner(
                    needsAppNotifications: needsAppNotif,
                    needsLocation: needsLocation,
                    onGrant: _requestAllMissingPermissions,
                  ),
                  const SizedBox(height: 16),
                ],
                _listenerCard(theme),
                const SizedBox(height: 16),
                _webhookCard(theme),
                const SizedBox(height: 16),
                _appsCard(theme),
              ],
            ),
    );
  }

  Widget _listenerCard(ThemeData theme) {
    final listenerMissing = !_hasNotificationAccess && _serviceEnabled;
    return SectionCard(
      icon: Icons.notifications_active_outlined,
      title: 'Notification listener',
      subtitle: listenerMissing
          ? 'Notification access required'
          : 'Capture transaction notifications from selected apps',
      child: Row(
        children: [
          Expanded(
            child: Text(
              _serviceEnabled ? 'Enabled' : 'Disabled',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _serviceEnabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch(
            value: _serviceEnabled,
            onChanged: _onServiceToggled,
          ),
        ],
      ),
    );
  }

  Widget _webhookCard(ThemeData theme) {
    return SectionCard(
      icon: Icons.webhook_outlined,
      title: 'Webhook URL',
      subtitle: 'Where transaction events are forwarded',
      child: TextField(
        controller: _webhookUrlController,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          hintText: 'https://example.com/webhook',
          prefixIcon: Icon(Icons.link_outlined),
        ),
        onChanged: _onWebhookChanged,
      ),
    );
  }

  Widget _appsCard(ThemeData theme) {
    return SectionCard(
      icon: Icons.apps_outlined,
      title: 'Apps to monitor',
      subtitle:
          '${_selectedApps.length} of ${_allApps.length} apps selected',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search apps...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _selectAll,
                icon: const Icon(Icons.select_all_outlined, size: 18),
                label: const Text('Select all'),
              ),
              TextButton.icon(
                onPressed: _deselectAll,
                icon: const Icon(Icons.deselect_outlined, size: 18),
                label: const Text('Deselect'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Bounded scrollable list inside the card.
          SizedBox(
            height: 360,
            child: _filteredApps.isEmpty
                ? Center(
                    child: Text(
                      'No apps match "${_searchController.text}".',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredApps.length,
                    itemExtent: 56,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      final app = _filteredApps[index];
                      return AppListTile(
                        key: ValueKey(app.packageName),
                        appName: app.appName,
                        packageName: app.packageName,
                        selected: _selectedApps.contains(app.packageName),
                        iconNotifier: _repo.iconNotifier(app.packageName),
                        onToggle: (v) => _onAppToggled(app.packageName, v),
                        onLoadIcon: () => _repo.loadIcon(app.packageName),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
