import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/api_client.dart';
import '../services/app_repository.dart';
import '../services/preferences_service.dart';
import '../theme.dart';
import '../widgets/app_status_tile.dart';
import '../widgets/permission_banner.dart';
import '../widgets/section_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.repo, required this.prefs, required this.api, required this.dashboardRev});

  final AppRepository repo;
  final PreferencesService prefs;
  final ApiClient api;
  final ValueNotifier<int> dashboardRev;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late final AppRepository _repo = widget.repo;
  late final PreferencesService _prefs = widget.prefs;
  late final ApiClient _api = widget.api;

  // App data
  List<AppInfo> _allApps = const [];

  // Settings
  final TextEditingController _searchController = TextEditingController();

  // Package statuses (server-synced).
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

  // User settings (budget / income)
  String _userId = '';
  bool _incomeManual = false; // incomeMode == "manual"
  final TextEditingController _incomeController = TextEditingController();
  MonthSummary? _monthSummary;
  String _currency = '';
  bool _isMiui = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitial();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _incomeController.dispose();
    super.dispose();
  }

  // ---------------- Init flow ----------------
  Future<void> _loadInitial() async {

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
    // Fire-and-forget: don't block the Settings screen on the network. The
    // Monthly Income card shows defaults until this returns (or times out).
    _loadUserSettings();
    _loadMonth();
    _checkMiui();
  }

  Future<void> _loadMonth() async {
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      final d = await _api.getDashboard(_userId);
      if (!mounted) return;
      setState(() {
        _monthSummary = d?.month;
        _currency = d?.currency ?? '';
      });
    } catch (_) {}
  }

  Future<void> _checkMiui() async {
    final mi = await _repo.isMiui();
    if (mounted) setState(() => _isMiui = mi);
  }

  // ---------------- User settings (income) ----------------
  Future<void> _loadUserSettings() async {
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      final s = await _api.getUserSettings(_userId);
      if (!mounted) return;
      setState(() {
        _incomeManual = s?.isManual ?? false;
        _incomeController.text = s?.monthlyIncome ?? '';
      });
    } catch (_) {
      // Swallow — budget card just shows defaults.
    }
  }

  Future<void> _onIncomeModeToggled() async {
    final newManual = !_incomeManual;
    setState(() => _incomeManual = newManual);
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      if (newManual) {
        await _api.postUserSettings(_userId, {'incomeMode': 'manual'});
      } else {
        await _api.postUserSettings(_userId, {'incomeMode': 'transactions', 'monthlyIncome': '0'});
      }
      widget.dashboardRev.value = widget.dashboardRev.value + 1;
    } catch (_) {
      if (mounted) setState(() => _incomeManual = !newManual);
    }
  }

  /// Save the manual monthly income (tick button), POST it, and trigger a
  /// dashboard refresh so the new budget shows on the Home tab.
  Future<void> _saveIncome() async {
    final value = _incomeController.text.trim();
    if (value.isEmpty) return;
    try {
      if (_userId.isEmpty) _userId = await _repo.getUserId();
      await _api.postUserSettings(_userId, {
        'incomeMode': 'manual',
        'monthlyIncome': value,
      });
      widget.dashboardRev.value = widget.dashboardRev.value + 1;
    } catch (_) {}
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

    if (_hasNotificationAccess) {
      await _repo.rebindListener();
    }
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
    await Permission.ignoreBatteryOptimizations.request();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recheckBatteryExemption();
    }
  }

  Future<void> _recheckBatteryExemption() async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (!mounted) return;
    if (status.isGranted != _hasBatteryExemption) {
      setState(() => _hasBatteryExemption = status.isGranted);
    }
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
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                // Appearance — Light/Dark/System only, no description.
                SectionCard(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: _prefs.themeMode,
                    builder: (context, mode, _) {
                      return _ThemeSegmentedControl(
                        current: mode,
                        onChanged: (m) => _prefs.setThemeMode(m),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _incomeCard(theme),
                const SizedBox(height: 16),
                if (needsAppNotif || needsLocation) ...[
                  PermissionBanner(
                    needsAppNotifications: needsAppNotif,
                    needsLocation: needsLocation,
                    onGrant: _requestAllMissingPermissions,
                  ),
                  const SizedBox(height: 16),
                ],
                _listenerCard(theme),
                if (!_hasBatteryExemption) ...[
                  const SizedBox(height: 16),
                  _batteryExemptionCard(theme),
                ],
                if (_isMiui) ...[
                  const SizedBox(height: 16),
                  _miuiCard(theme),
                ],
                const SizedBox(height: 16),
                _appsCard(theme),
              ],
            ),
    );
  }

  Widget _incomeCard(ThemeData theme) {
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return SectionCard(
      icon: Icons.payments_outlined,
      title: 'Monthly Income',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _incomeManual ? 'Manual' : 'Auto',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: _incomeManual ? theme.colorScheme.primary : muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: _onIncomeModeToggled,
                child: Text(_incomeManual ? 'Switch to Auto' : 'Switch to Manual'),
              ),
            ],
          ),
          if (_incomeManual) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _incomeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      hintText: 'Monthly income',
                      prefixIcon: Icon(Icons.attach_money),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.check),
                  onPressed: _saveIncome,
                  tooltip: 'Save',
                ),
              ],
            ),
          ],
          if (_monthSummary != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Income received',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                const Spacer(),
                Text(
                  _monthSummary!.isFulfilled ? 'Fulfilled' : 'Not fulfilled',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _monthSummary!.isFulfilled ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _monthSummary!.incomeExpectedNum > 0
                    ? (_monthSummary!.incomeReceivedNum /
                            _monthSummary!.incomeExpectedNum)
                        .clamp(0.0, 1.0)
                    : 0.0,
                minHeight: 8,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                color: _monthSummary!.isFulfilled ? Colors.green : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_monthSummary!.incomeReceivedNum.toStringAsFixed(2)} / ${_monthSummary!.incomeExpectedNum.toStringAsFixed(2)} $_currency',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miuiCard(ThemeData theme) {
    return SectionCard(
      icon: Icons.security_outlined,
      title: 'Autostart',
      subtitle: 'Required on Xiaomi / HyperOS to keep the listener alive',
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Enable autostart for this app in MIUI settings so the system doesn\'t kill the listener.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => _repo.openMiuiAutostart(),
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }

  Widget _listenerCard(ThemeData theme) {
    final listenerMissing = !_hasNotificationAccess;
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
              _hasNotificationAccess ? 'Connected' : 'Not connected',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: _hasNotificationAccess
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _hasNotificationAccess
                ? () => _repo.rebindListener()
                : () => _repo.requestNotificationListenerAccess(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(_hasNotificationAccess ? 'Rebind' : 'Enable'),
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

class _ThemeSegmentedControl extends StatelessWidget {
  const _ThemeSegmentedControl({required this.current, required this.onChanged});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined),
          label: Text('Light'),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined),
          label: Text('Dark'),
        ),
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto_outlined),
          label: Text('System'),
        ),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).colorScheme.primary;
          }
          return null;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBackground
                : Colors.white;
          }
          return null;
        }),
        visualDensity: VisualDensity.comfortable,
      ),
    );
  }
}
