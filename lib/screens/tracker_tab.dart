import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/search_config.dart';
import '../theme/app_theme.dart';
import '../widgets/scan_schedule_dialog.dart';
import 'logs_tab.dart';
import 'search_tab.dart';

class TrackerTab extends StatelessWidget {
  const TrackerTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final searches = controller.savedSearches;

        return Scaffold(
          appBar: AppBar(
            title: const Text('avtonetFinder'),
            actions: [
              // Global Schedule Status Button
              IconButton(
                tooltip: 'Scan Schedule Status',
                icon: const Icon(Icons.schedule, size: 22),
                onPressed: () => _showScheduleStatus(context),
              ),
              // Hidden Debug Console Button
              IconButton(
                icon: const Icon(Icons.bug_report_outlined, size: 20),
                onPressed: () => _showDebugConsole(context),
              ),
              IconButton(
                tooltip: 'Clear Database',
                icon: const Icon(Icons.delete_forever, size: 22, color: Colors.red),
                onPressed: () => _confirmFullClear(context),
              ),
            ],
          ),
          body: Column(
            children: [
              if (controller.isScanning) _linearProgress(),
              Expanded(
                child: searches.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: searches.length,
                        itemBuilder: (context, i) => _TrackerCard(
                          config: searches[i],
                          controller: controller,
                        ),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              controller.prepareNewSearch();
              _showSearchDialog(context);
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _linearProgress() {
    return LinearProgressIndicator(
      backgroundColor: AppTheme.brandPurple.withAlpha(20),
      valueColor: const AlwaysStoppedAnimation(AppTheme.brandPurple),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sensors_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('No active trackers', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Tap + to create a new vehicle filter', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  void _showDebugConsole(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: LogsTab(logService: controller.log),
      ),
    );
  }

  void _showScheduleStatus(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ScanScheduleDialog(controller: controller),
    );
  }

  void _showSearchDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SearchTab(controller: controller),
    );
  }

  Future<void> _confirmFullClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all data?'),
        content: const Text('This will delete all history, processed IDs and logs. Active filters will remain.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CLEAR ALL', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.fullClearDatabase();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database cleared successfully')),
        );
      }
    }
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.config, required this.controller});
  final SearchConfig config;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastTime = config.lastChecked != null
        ? '${config.lastChecked!.hour.toString().padLeft(2, '0')}:${config.lastChecked!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(config.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        'Last scan: $lastTime',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: config.isEnabled,
                  activeThumbColor: theme.colorScheme.primary,
                  onChanged: (val) => controller.toggleSearch(config.id, val),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${config.znamka} ${config.model} • ${controller.bodyTypeLabel(config.oblika)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    config.lastStatus.isEmpty ? 'Waiting for scan...' : config.lastStatus,
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: config.lastStatus.contains('Error') || config.lastStatus.contains('Napaka') 
                        ? Colors.red 
                        : AppTheme.brandPurple,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Scan now',
                      onPressed: controller.isScanning ? null : () => controller.runSequentialScan(singleId: config.id),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () {
                        controller.loadSearchForEditing(config);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => SearchTab(controller: controller),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                      onPressed: () => controller.deleteSearch(config.id),
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
