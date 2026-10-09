import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_repository.dart';

/// A circular app launcher icon. Reads the icon synchronously from the
/// [AppRepository] icon notifier (cached), kicking off a lazy load if it's
/// not yet cached. Falls back to a coloured circle with the first letter of
/// [fallbackName] (or a generic apps icon if no name given).
class AppIconCircle extends StatefulWidget {
  const AppIconCircle({
    super.key,
    required this.packageName,
    required this.repo,
    this.size = 40,
    this.fallbackName = '',
  });

  final String packageName;
  final AppRepository repo;
  final double size;

  /// Used for the letter-based fallback avatar when the icon isn't available.
  final String fallbackName;

  @override
  State<AppIconCircle> createState() => _AppIconCircleState();
}

class _AppIconCircleState extends State<AppIconCircle> {
  late final ValueNotifier<Uint8List?> _notifier;

  // Stable colour derived from the package name for the fallback avatar.
  late final Color _fallbackColor;

  @override
  void initState() {
    super.initState();
    _notifier = widget.repo.iconNotifier(widget.packageName);
    _notifier.addListener(_onChanged);
    if (_notifier.value == null) {
      widget.repo.loadIcon(widget.packageName);
    }
    _fallbackColor = _colorFromString(widget.packageName);
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  static Color _colorFromString(String s) {
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = (hash * 31 + c) & 0xFFFFFF;
    }
    final hues = [0.0, 30.0, 60.0, 120.0, 180.0, 210.0, 260.0, 290.0, 330.0];
    final hue = hues[hash % hues.length];
    return HSLColor.fromAHSL(1.0, hue, 0.55, 0.45).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _notifier.value;
    final image = bytes != null ? MemoryImage(bytes) : null;

    // Fallback: letter avatar if we have a name, generic icon otherwise.
    Widget child;
    if (image != null) {
      child = Image(image: image, fit: BoxFit.cover);
    } else if (widget.fallbackName.isNotEmpty) {
      child = Center(
        child: Text(
          widget.fallbackName[0].toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: widget.size * 0.42,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else {
      child = Icon(Icons.apps_outlined,
          size: widget.size * 0.5,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4));
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: image != null
            ? theme.colorScheme.surfaceContainerHighest
            : _fallbackColor,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
