import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';

/// Maps a [ServiceStatus] to its UI label and indicator color.
/// Shared by [StatusCard] and the permissions screen rows.
(String label, Color color) statusVisual(
  BuildContext context,
  ServiceStatus status,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    ServiceStatus.idle => ('Idle', scheme.onSurfaceVariant),
    ServiceStatus.granted => ('Granted', scheme.primary),
    ServiceStatus.denied => ('Denied', scheme.error),
    ServiceStatus.running => ('Active', scheme.primary),
    ServiceStatus.error => ('Error', scheme.error),
  };
}

/// Compact dashboard card showing one pipeline stage's status:
/// icon, title, and a colored status dot + label.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
  });

  final IconData icon;
  final String title;
  final ServiceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = statusVisual(context, status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.primary),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
