import 'package:flutter/material.dart';

import 'simulated_page_detector.dart';

/// A dev panel (§5.2) that lists a manifest's pages as tappable rows; a tap
/// feeds that page's `page_id` into the [SimulatedPageDetector], emitting it
/// through the same seam a native detector will use. Reusable and intentionally
/// minimal; not wired into navigation.
class SimulatedPagePanel extends StatelessWidget {
  const SimulatedPagePanel({super.key, required this.detector});

  final SimulatedPageDetector detector;

  @override
  Widget build(BuildContext context) {
    final targets = detector.targets;
    if (targets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Nothing to scan'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: targets.length,
      itemBuilder: (context, i) {
        final target = targets[i];
        return ListTile(
          leading: CircleAvatar(child: Text('${target.pageNumber}')),
          title: Text('Page ${target.pageNumber}'),
          subtitle: Text(target.pageId),
          onTap: () => detector.simulateDetection(target.pageId),
        );
      },
    );
  }
}
