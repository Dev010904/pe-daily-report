import 'package:flutter/material.dart';

import '../data/repo.dart';
import 'theme.dart';

/// Cloud icon in the top bar: saved / saving / waiting for internet.
class SyncBadge extends StatelessWidget {
  final Repo repo;
  const SyncBadge({super.key, required this.repo});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final pending = repo.pending;
        final (IconData icon, Color color, String tip) = switch (repo.state) {
          SyncState.syncing => (
            Icons.cloud_sync,
            Colors.white,
            'Saving to cloud...',
          ),
          SyncState.offline => (
            Icons.cloud_off,
            const Color(0xFFFFC857),
            pending > 0
                ? 'No internet - $pending change(s) saved on phone, will upload later'
                : 'No internet',
          ),
          SyncState.error => (
            Icons.error_outline,
            const Color(0xFFFF8A80),
            'Cloud problem',
          ),
          SyncState.idle when pending > 0 => (
            Icons.cloud_upload,
            const Color(0xFFFFC857),
            '$pending change(s) waiting to upload',
          ),
          SyncState.idle => (
            Icons.cloud_done,
            const Color(0xFF8BE3A6),
            'All saved to cloud',
          ),
        };
        return IconButton(
          key: const Key('syncBadge'),
          tooltip: tip,
          onPressed: () => _details(context),
          icon: Badge(
            isLabelVisible: pending > 0,
            backgroundColor: AppColors.gold,
            label: Text('$pending'),
            child: Icon(icon, color: color),
          ),
        );
      },
    );
  }

  void _details(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListenableBuilder(
        listenable: repo,
        builder: (ctx, _) {
          final pending = repo.pending;
          final (String title, String body, Color c) = switch (repo.state) {
            SyncState.syncing => (
              'Saving...',
              'Talking to the cloud.',
              AppColors.navy,
            ),
            SyncState.offline => (
              'No internet',
              pending > 0
                  ? '$pending change(s) are safely saved on this phone and will upload by themselves when internet comes back.'
                  : 'Everything was already uploaded. New changes will upload when internet comes back.',
              AppColors.amber,
            ),
            SyncState.error => (
              'Cloud problem',
              'Could not save to the cloud. Your changes are kept on this device. ${repo.lastError ?? ''}',
              AppColors.danger,
            ),
            SyncState.idle when pending > 0 => (
              'Waiting to upload',
              '$pending change(s) will upload in a moment.',
              AppColors.amber,
            ),
            SyncState.idle => (
              'All saved',
              'Everything is saved in the cloud and visible on every device.',
              AppColors.full,
            ),
          };
          final last = repo.lastSynced;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: c,
                  ),
                ),
                const SizedBox(height: 6),
                Text(body, style: const TextStyle(fontSize: 16)),
                if (last != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last synced: ${TimeOfDay.fromDateTime(last).format(ctx)}',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('syncNow'),
                    onPressed: repo.state == SyncState.syncing
                        ? null
                        : repo.sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
