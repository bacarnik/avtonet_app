import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/search_config.dart';
import '../theme/app_theme.dart';

class DashboardTab extends StatelessWidget {
  const DashboardTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final searches = controller.savedSearches;

        return Column(
          children: [
            if (controller.isScanning) _progressIndicator(),
            if (searches.isNotEmpty) _topActions(context),
            Expanded(
              child: searches.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: searches.length,
                      itemBuilder: (context, index) => _SearchConfigCard(
                        config: searches[index],
                        onDelete: () => controller.deleteSearch(searches[index].id),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _topActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () => _confirmReset(context),
            icon: const Icon(Icons.history, size: 16),
            label: const Text('RESET SEEN IDs', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ponastavi bazo videnih?'),
        content: const Text('Aplikacija bo naslednjič vse najdene oglase obravnavala kot nove. Shranjeni filtri ostanejo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('PREKLIČI')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('PONASTAVI')),
        ],
      ),
    );
    if (ok == true) await controller.resetSeenDatabase();
  }

  Widget _progressIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.brandPurple.withAlpha(20),
        border: const Border(bottom: BorderSide(color: AppTheme.brandPurple, width: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Skeniranje: ${controller.scanIndex}/${controller.scanTotal}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: controller.cancelScan,
                child: const Text('PREKLIČI'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: controller.scanTotal > 0 ? controller.scanIndex / controller.scanTotal : 0,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text(
            controller.scanLabel,
            style: const TextStyle(fontSize: 11, color: AppTheme.brandPurple),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 64, color: AppTheme.darkTextMuted),
          SizedBox(height: 16),
          Text(
            'Ni aktivnih iskanj',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            'Dodajte novo iskanje v prvem zavihku.',
            style: TextStyle(color: AppTheme.darkTextMuted),
          ),
        ],
      ),
    );
  }
}

class _SearchConfigCard extends StatelessWidget {
  const _SearchConfigCard({required this.config, required this.onDelete});

  final SearchConfig config;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final lastCheckStr = config.lastChecked != null
        ? '${config.lastChecked!.hour.toString().padLeft(2, '0')}:${config.lastChecked!.minute.toString().padLeft(2, '0')}:${config.lastChecked!.second.toString().padLeft(2, '0')}'
        : 'Nikoli';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    config.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  'Zadnje: $lastCheckStr',
                  style: const TextStyle(fontSize: 10, color: AppTheme.darkTextMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              config.lastStatus,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: config.lastStatus.contains('Napaka') ? Colors.red : AppTheme.brandPurple,
              ),
            ),
            
            // --- DEBUG SECTION ---
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black.withAlpha(10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DEBUG INFO:', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _debugItem('Parsed', config.lastParsedCount),
                      _debugItem('Matched', config.lastMatchedCount),
                      _debugItem('Duplicates', config.lastDuplicateCount),
                      _debugItem('New', config.lastMatchedCount - config.lastDuplicateCount),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('IDs: ${config.lastFoundIds.isEmpty ? "None" : config.lastFoundIds}', 
                    style: const TextStyle(fontSize: 9, fontFamily: 'monospace', color: Colors.blueGrey)),
                  if (config.lastRejectionReason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Rejected: ${config.lastRejectionReason}', 
                      style: const TextStyle(fontSize: 9, color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _debugItem(String label, int val) {
    return Column(
      children: [
        Text(val.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.grey)),
      ],
    );
  }
}
