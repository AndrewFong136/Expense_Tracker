import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/app_repository.dart';
import '../services/preferences_service.dart';
import '../widgets/app_status_tile.dart';
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

  // Settings
  bool _serviceEnabled = false;
  final TextEditingController _searchController = TextEditingController();

  // Package statuses (effective: server ⊕ local overrides).
  Map<String, String> _statuses = const {};
  String? _statusFilter; // null = all
  bool _syncing = false;

  // Permissions
  bool _hasNotificationAccess = false;
  bool _hasAppNotificationsEnabled = false;
  bool _hasLocationAlwaysEnabled = false;
  bool _hasBatteryExemption = false;

  // Loading state
  bool _isLoading = true;

  // Debounce timers
  Timer? _searchDebounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------- Init flow ----------------
  Future<void> _loadInitial() async {
    _serviceEnabled = _prefs.serviceEnabled;

    final cached = await _repo.getCachedApps();
    if (cached.isNotEmpty) {
      _allApps = cached;
      if (mounted) setState(() => _isLoading = false);
      _preloadIconsFor(cached.take(40).map((a) => a.packageName).toList());
    }

    await Future.wait([
      _checkPermissions(),
      _loadInstalledApps(),
    ]);

    await _loadStatuses();

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  // ---------------- Package statuses ----------------
  Future<void> _loadStatuses() async {
    final snapshot = await _repo.getStatuses();
    if (!mounted) return;
    setState(() {
      _statuses = (snapshot['statuses'] as Map).cast<String, String>();
    });
  }

  Future<void> _onSyncStatuses() async {
    setState(() => _syncing = true);
    try {
      await _repo.syncStatuses();
      // Give the worker a moment to pull, then reload.
      await Future.delayed(const Duration(seconds: 1));
      await _loadStatuses();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _statusFor(String packageName) =>
      _statuses[packageName] ?? 'UNKNOWN';

  List<AppInfo> _sortedFilteredApps() {
    final q = _activeQuery.trim().toLowerCase();
    const rank = {'FINANCIAL': 0, 'NON_FINANCIAL': 1, 'UNKNOWN': 2};
    final apps = _allApps.where((a) {
      if (_statusFilter != null && _statusFor(a.packageName) != _statusFilter) {
        return false;
      }
      if (q.isNotEmpty &&
          !a.appName.toLowerCase().contains(q) &&
          !a.packageName.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
    apps.sort((a, b) {
      final ra = rank[_statusFor(a.packageName)] ?? 2;
      final rb = rank[_statusFor(b.packageName)] ?? 2;
      if (ra != rb) return ra.compareTo(rb);
      return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
    });
    return apps;
  }

  Future<void> _loadInstalledApps() async {
    try {
      final apps = await _repo.getInstalledApps();
      if (!mounted) return;
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
        if (mounted) setState(() {});
      }
      _preloadIconsFor(merged.take(40).map((a) => a.packageName).toList());
    } on Exception {
      // Swallow — cached list (if any) stays visible.
    }
  }

  Future<void> _preloadIconsFor(List<String> packages) async {
    await _repo.preloadIcons(packages);
  }

  // ---------------- Permissions ----------------
  Future<void> _checkPermissions() async {
    final notif = await _repo.isNotificationListenerAccessEnabled();
    final appNotif = await _repo.isAppNotificationEnabled();
    final loc = await _repo.isLocationAlwaysEnabled();
    final battery = await Permission.ignoreBatteryOptimizations.status;

    if (!mounted) return;
    setState(() {
      _hasNotificationAccess = notif;
      _hasAppNotificationsEnabled = appNotif;
      _hasLocationAlwaysEnabled = loc;
      _hasBatteryExemption = battery.isGranted;
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

  Future<void> _requestBatteryExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (mounted) {
      setState(() => _hasBatteryExemption = status.isGranted);
    }
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Set this app to "Not optimized" so the listener isn\'t killed after a few hours.'),
        ),
      );
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

  Future<void> _syncSettingsToAndroid() async {
    await _repo.sendSettingsToAndroid(serviceEnabled: _serviceEnabled);
  }

  // ---------------- Search ----------------
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _activeQuery = value;
      if (mounted) setState(() {});
    });
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
                if (_serviceEnabled && !_hasBatteryExemption) ...[
                  const SizedBox(height: 16),
                  _batteryExemptionCard(theme),
                ],
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
          : 'Capture transaction notifications from financial apps',
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

  Widget _batteryExemptionCard(ThemeData theme) {
    return SectionCard(
      icon: Icons.battery_saver_outlined,
      title: 'Battery optimization',
      subtitle: 'Keep the listener alive in the background',
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Disable battery optimization for this app so the system doesn\'t '
              'kill the listener after a few hours.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _requestBatteryExemption,
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String? value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _statusFilter == value,
      onSelected: (_) {
        setState(() {
          _statusFilter = (_statusFilter == value) ? null : value;
        });
      },
    );
  }

  Widget _appsCard(ThemeData theme) {
    final apps = _sortedFilteredApps();
    return SectionCard(
      icon: Icons.apps_outlined,
      title: 'Apps',
      trailing: IconButton(
        icon: _syncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        onPressed: _syncing ? null : _onSyncStatuses,
        tooltip: 'Sync statuses',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(null, 'All'),
                const SizedBox(width: 6),
                _filterChip('FINANCIAL', 'Financial'),
                const SizedBox(width: 6),
                _filterChip('NON_FINANCIAL', 'Non-financial'),
                const SizedBox(width: 6),
                _filterChip('UNKNOWN', 'Unknown'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search apps...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 480,
            child: apps.isEmpty
                ? Center(
                    child: Text(
                      'No apps match.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.8,
                      mainAxisSpacing: 2,
                      crossAxisSpacing: 2,
                    ),
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return AppStatusTile(
                        key: ValueKey(app.packageName),
                        appName: app.appName,
                        packageName: app.packageName,
                        status: _statusFor(app.packageName),
                        iconNotifier: _repo.iconNotifier(app.packageName),
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
