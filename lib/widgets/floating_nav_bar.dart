import 'package:flutter/material.dart';

/// A floating, rounded bottom navigation bar with a raised circular "Add"
/// button in the centre. Four labelled items (Home, Balance, History,
/// Settings) flank the raised Add (index 2). Brand-coloured selection.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final surface = theme.colorScheme.surface;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SizedBox(
          height: 88, // 64 bar + 24 raised overlap for the centre button
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The bar itself.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _item(0, Icons.home_outlined, Icons.home, 'Home',
                          primary, muted),
                      _item(1, Icons.account_balance_wallet_outlined,
                          Icons.account_balance_wallet, 'Balance', primary, muted),
                      const SizedBox(width: 64), // gap for the raised Add
                      _item(3, Icons.receipt_long_outlined, Icons.receipt_long,
                          'History', primary, muted),
                      _item(4, Icons.settings_outlined, Icons.settings,
                          'Settings', primary, muted),
                    ],
                  ),
                ),
              ),
              // Raised centre Add button.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => onTap(2),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primary,
                        boxShadow: [
                          BoxShadow(
                            color: primary.withValues(alpha: 0.40),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    int index,
    IconData unselected,
    IconData selected,
    String label,
    Color primary,
    Color muted,
  ) {
    final isSelected = currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? selected : unselected,
              size: 22,
              color: isSelected ? primary : muted,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? primary : muted,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
