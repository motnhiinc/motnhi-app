import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class FloatingNavItem {
  const FloatingNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
}

/// Glassmorphism bottom navigation (design system: reserved for nav + AR
/// overlays). Floating pill with a soft warm shadow.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.items});

  final List<FloatingNavItem> items;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: t.glass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.line),
          boxShadow: [
            BoxShadow(color: t.shadow, blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final item in items)
              _NavItem(item: item),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.item});

  final FloatingNavItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.stitch;
    final color = item.active ? t.coral : t.inkMuted;
    return Semantics(
      button: true,
      selected: item.active,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 22, color: color),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: TextStyle(
                  fontFamily: AppTheme.sansFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
