import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A single app row in the monitor list. Reads its icon synchronously from a
/// [ValueNotifier] so it never blocks on a [Future] during build. If the icon
/// is not yet cached, the tile asks the parent (via [onLoadIcon]) to fetch it
/// and the notifier will update when bytes arrive.
class AppListTile extends StatefulWidget {
  const AppListTile({
    super.key,
    required this.appName,
    required this.packageName,
    required this.selected,
    required this.iconNotifier,
    required this.onToggle,
    this.onLoadIcon,
  });

  final String appName;
  final String packageName;
  final bool selected;
  final ValueNotifier<Uint8List?> iconNotifier;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onLoadIcon;

  @override
  State<AppListTile> createState() => _AppListTileState();
}

class _AppListTileState extends State<AppListTile> {
  @override
  void initState() {
    super.initState();
    widget.iconNotifier.addListener(_onIconChanged);
    // If there's no icon yet, kick off a lazy load.
    if (widget.iconNotifier.value == null) {
      widget.onLoadIcon?.call();
    }
  }

  @override
  void didUpdateWidget(covariant AppListTile oldWidget) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = widget.iconNotifier.value;
    final image = bytes != null ? MemoryImage(bytes) : null;

    return InkWell(
      onTap: () => widget.onToggle(!widget.selected),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: image != null
                  ? Image(image: image, fit: BoxFit.cover)
                  : Icon(Icons.apps_outlined,
                      size: 22,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    widget.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Checkbox(
              value: widget.selected,
              onChanged: (v) => widget.onToggle(v ?? false),
            ),
          ],
        ),
      ),
    );
  }
}
