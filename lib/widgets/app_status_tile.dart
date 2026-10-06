import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A display-only grid cell for an app. Shows the launcher icon (bordered by
/// status colour), the app name, and a status badge. The status comes from the
/// server (delta sync); the cell is not interactive.
///
/// Reads its icon synchronously from a [ValueNotifier] so it never blocks on a
/// [Future] during build; if the icon isn't cached yet it asks the parent (via
/// [onLoadIcon]) to fetch it.
class AppStatusTile extends StatefulWidget {
  const AppStatusTile({
    super.key,
    required this.appName,
    required this.packageName,
    required this.status,
    required this.iconNotifier,
    this.onLoadIcon,
  });

  final String appName;
  final String packageName;
  final String status; // FINANCIAL / NON_FINANCIAL / UNKNOWN
  final ValueNotifier<Uint8List?> iconNotifier;
  final VoidCallback? onLoadIcon;

  @override
  State<AppStatusTile> createState() => _AppStatusTileState();
}

class _AppStatusTileState extends State<AppStatusTile> {
  @override
  void initState() {
    super.initState();
    widget.iconNotifier.addListener(_onIconChanged);
    if (widget.iconNotifier.value == null) {
      widget.onLoadIcon?.call();
    }
  }

  @override
  void didUpdateWidget(covariant AppStatusTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iconNotifier != widget.iconNotifier) {
      oldWidget.iconNotifier.removeListener(_onIconChanged);
      widget.iconNotifier.addListener(_onIconChanged);
    }
  }

  @override
  void dispose() {
    widget.iconNotifier.removeListener(_onIconChanged);
    super.dispose();
  }

  void _onIconChanged() {
    if (mounted) setState(() {});
  }

  Color _statusColor(ThemeData theme) {
    switch (widget.status) {
      case 'FINANCIAL':
        return Colors.green;
      case 'NON_FINANCIAL':
        return Colors.red;
      default:
        return theme.colorScheme.onSurface.withValues(alpha: 0.35);
    }
  }

  String get _statusLabel {
    switch (widget.status) {
      case 'FINANCIAL':
        return 'Financial';
      case 'NON_FINANCIAL':
        return 'Non-financial';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = widget.iconNotifier.value;
    final image = bytes != null ? MemoryImage(bytes) : null;
    final color = _statusColor(theme);

    return Card(
      margin: const EdgeInsets.all(3),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: color, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: image != null
                  ? Image(image: image, fit: BoxFit.cover)
                  : Icon(Icons.apps_outlined,
                      size: 22,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 6),
            Text(
              widget.appName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
