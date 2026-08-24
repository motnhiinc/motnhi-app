import 'package:flutter/material.dart';

/// Asymmetric "hardback book" frame from the design system: heavy rounded
/// top corners (42px), softer bottom corners (22px).
class BookCoverFrame extends StatelessWidget {
  const BookCoverFrame({super.key, required this.child, this.radius = 42});

  final Widget child;

  /// Radius of the two top corners; bottom corners are [radius] - 20.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(radius),
        bottom: Radius.circular(radius - 20 < 0 ? 0 : radius - 20),
      ),
      child: child,
    );
  }
}
