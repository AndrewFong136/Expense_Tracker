import 'package:flutter/material.dart';

import '../services/preferences_service.dart';
import '../theme.dart';
import '../widgets/section_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.prefs});

  final PreferencesService prefs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: 'Appearance',
            subtitle: 'Choose how the app looks',
            icon: Icons.palette_outlined,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: prefs.themeMode,
              builder: (context, mode, _) {
                return _ThemeSegmentedControl(
                  current: mode,
                  onChanged: (m) => prefs.setThemeMode(m),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'About',
            icon: Icons.info_outline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(context, 'App', 'Expense Tracker'),
                const SizedBox(height: 8),
                _infoRow(context, 'Version', '1.0.0'),
                const SizedBox(height: 8),
                _infoRow(context, 'Purpose',
                    'Captures transaction notifications from selected apps and forwards them to your webhook.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'How it works',
            icon: Icons.bolt_outlined,
            child: Text(
              '1. Enable the notification listener on the home screen.\n'
              '2. Grant the required permissions.\n'
              '3. Pick the apps you want to monitor.\n'
              '4. Set your webhook URL — every transaction notification from the selected apps will be forwarded there with location data.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
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
