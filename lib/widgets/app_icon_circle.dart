import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_repository.dart';

/// A circular app launcher icon. Reads the icon synchronously from the
/// [AppRepository] icon notifier (cached), kicking off a lazy load if it's
/// not yet cached. Falls back to a generic apps icon.
class AppIconCircle extends StatefulWidget {
  const AppIconCircle({
    super.key,
    required this.packageName,
    required this.repo,
    this.size = 40,
  });

  final String packageName;
  final AppRepository repo;
  final double size;

  @override
  State<AppIconCircle> createState() => _AppIconCircleState();
}

class _AppIconCircleState extends State<AppIconCircle> {
  late final ValueNotifier<Uint8List?> _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = widget.repo.iconNotifier(widget.packageName);
    _notifier.addListener(_onChanged);
    if (_notifier.value == null) {
      widget.repo.loadIcon(widget.packageName);
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _notifier.value;
    final image = bytes != null ? MemoryImage(bytes) : null;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image(image: image, fit: BoxFit.cover)
          : Icon(Icons.apps_outlined,
              size: widget.size * 0.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
    );
  }
}
