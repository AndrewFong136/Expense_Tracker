import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Lightweight value object for an installed launcher app.
class AppInfo {
  const AppInfo({required this.packageName, required this.appName});

  final String packageName;
  final String appName;

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String,
    );
  }

  Map<String, String> toMap() => {
        'packageName': packageName,
        'appName': appName,
      };
}

/// Thin wrapper around the `com.example.expense_tracker/settings` platform
/// channel.
///
/// Owns an in-memory icon cache keyed by package name. Icons are fetched in a
/// single batched call ([preloadIcons]) and exposed synchronously via
/// [getIconBytes] / [iconNotifier] so list rows never block on a future.
class AppRepository {
  AppRepository();

  static const MethodChannel _channel =
      MethodChannel('com.example.expense_tracker/settings');

  // Synchronous byte cache: packageName -> PNG bytes.
  final Map<String, Uint8List> _iconBytesCache = {};
  // Per-package notifier so individual tiles can rebuild when their icon
  // arrives without invalidating the whole list.
  final Map<String, ValueNotifier<Uint8List?>> _iconNotifiers = {};
  // Packages currently being loaded (avoids duplicate in-flight calls).
  final Set<String> _loading = {};

  // ---------------- Apps ----------------
  Future<List<AppInfo>> getCachedApps() async {
    final raw = await _channel.invokeMethod<List>('getCachedApps');
    if (raw == null) return const [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(AppInfo.fromMap)
        .toList(growable: false);
  }

  Future<List<AppInfo>> getInstalledApps() async {
    final raw = await _channel.invokeMethod<List>('getInstalledApps');
    if (raw == null) return const [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map(AppInfo.fromMap)
        .toList(growable: false);
  }

  // ---------------- Icons ----------------

  /// Returns the cached bytes for [packageName] if available, otherwise null.
  /// Synchronous — safe to call from [Widget.build].
  Uint8List? getIconBytes(String packageName) => _iconBytesCache[packageName];

  /// Returns a notifier for [packageName]'s icon. The notifier is seeded with
  /// the current cache value (possibly null) and updated when an async load
  /// completes. Repeated calls return the same notifier instance.
  ValueNotifier<Uint8List?> iconNotifier(String packageName) {
    return _iconNotifiers.putIfAbsent(
      packageName,
      () => ValueNotifier<Uint8List?>(_iconBytesCache[packageName]),
    );
  }

  /// Preload icons for [packageNames] in a single batched channel call.
  /// Already-cached packages are skipped. Safe to call repeatedly.
  Future<void> preloadIcons(List<String> packageNames) async {
    final missing = packageNames
        .where((p) =>
            !_iconBytesCache.containsKey(p) && !_loading.contains(p))
        .toList(growable: false);
    if (missing.isEmpty) return;

    _loading.addAll(missing);
    try {
      final result = await _channel.invokeMethod<Map>('getAppIcons', {
        'packageNames': missing,
      });
      if (result != null) {
        result.forEach((pkg, bytes) {
          if (bytes is Uint8List) {
            final key = pkg as String;
            _iconBytesCache[key] = bytes;
            final notifier = _iconNotifiers[key];
            if (notifier != null) notifier.value = bytes;
          }
        });
      }
    } on PlatformException {
      // Ignore — tiles will fall back to the placeholder.
    } finally {
      _loading.removeAll(missing);
    }
  }

  /// Lazily load a single icon (e.g. for a tile scrolled into view before
  /// [preloadIcons] reaches it). Updates the notifier if one exists.
  Future<void> loadIcon(String packageName) async {
    if (_iconBytesCache.containsKey(packageName) ||
        _loading.contains(packageName)) {
      return;
    }
    _loading.add(packageName);
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('getAppIcon', {
        'packageName': packageName,
      });
      if (bytes != null) {
        _iconBytesCache[packageName] = bytes;
        final notifier = _iconNotifiers[packageName];
        if (notifier != null) notifier.value = bytes;
      }
    } on PlatformException {
      // Leave notifier at null → placeholder stays.
    } finally {
      _loading.remove(packageName);
    }
  }

  // ---------------- Permissions ----------------
  Future<bool> isAppNotificationEnabled() async {
    final result =
        await _channel.invokeMethod<bool>('isAppNotificationEnabled') ?? true;
    return result;
  }

  Future<bool> isNotificationListenerAccessEnabled() async {
    final result =
        await _channel.invokeMethod<bool>('isNotificationListenerAccessEnabled') ??
            false;
    return result;
  }

  Future<bool> isLocationAlwaysEnabled() async {
    final result =
        await _channel.invokeMethod<bool>('isLocationAlwaysEnabled') ?? true;
    return result;
  }

  Future<void> requestNotificationListenerAccess() async {
    await _channel.invokeMethod<void>('requestNotificationListenerAccess');
  }

  Future<void> rebindListener() async {
    await _channel.invokeMethod<void>('rebindListener');
  }

  // ---------------- Settings sync ----------------
  Future<void> sendSettingsToAndroid({
    required bool serviceEnabled,
  }) async {
    try {
      await _channel.invokeMethod<void>('updateSettings', {
        'service_enabled': serviceEnabled,
      });
    } on PlatformException {
      // Swallow — the service may simply not be ready.
    }
  }

  // ---------------- Package statuses (filter system) ----------------

  /// Returns the local package -> status map + last sync version from the
  /// Android side (written by DeltaSyncWorker). Does not hit the network.
  Future<Map<String, dynamic>> getStatuses() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStatuses');
      if (result == null) {
        return {'statuses': <String, String>{}, 'version': 0};
      }
      final raw = result['statuses'];
      final statuses = raw is Map
          ? raw.map((k, v) => MapEntry(k as String, v as String))
          : <String, String>{};
      final version = (result['version'] as num?)?.toInt() ?? 0;
      return {'statuses': statuses, 'version': version};
    } on PlatformException {
      return {'statuses': <String, String>{}, 'version': 0};
    }
  }

  /// Triggers a one-time delta pull from the API (wake-and-sync).
  Future<void> syncStatuses() async {
    try {
      await _channel.invokeMethod<void>('syncStatuses');
    } on PlatformException {
      // Swallow.
    }
  }
}
