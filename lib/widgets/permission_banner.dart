import 'package:flutter/material.dart';

import '../theme.dart';

/// Orange warning banner shown when required runtime permissions are missing.
/// Calls [onGrant] when the user taps the grant button (the parent re-checks
/// permissions after the request flows complete).
class PermissionBanner extends StatelessWidget {
  const PermissionBanner({
    super.key,
    required this.needsAppNotifications,
    required this.needsLocation,
    required this.onGrant,
  });

  final bool needsAppNotifications;
  final bool needsLocation;
  final Future<void> Function() onGrant;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.warningBgDark : AppColors.warningBgLight;
    final fg = isDark ? AppColors.darkPrimary : AppColors.lightPrimary;

    final missing = <String>[];
    if (needsAppNotifications) missing.add('app notifications');
    if (needsLocation) missing.add('background location');

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fg.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: fg, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permission required',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'To capture transactions, allow ${missing.join(" and ")}. '
                  'Location is recommended for precise tracking.',
                  style: TextStyle(
                    fontSize: 13,
                    color: fg.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await onGrant();
                    } on Exception {
                      // permission_handler / platform errors are surfaced by
                      // the parent's re-check; nothing more to do here.
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: fg,
                    foregroundColor:
                        isDark ? AppColors.darkBackground : Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: const Text('Allow permissions'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
