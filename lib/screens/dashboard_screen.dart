import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/app_controller.dart';
import '../models/search_config.dart';
import '../models/car_listing.dart';
import '../theme/app_theme.dart';
import 'logs_tab.dart';
import 'search_tab.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('AvtoNet Skener Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.bug_report_outlined, size: 20),
                onPressed: () => _showDebugConsole(context),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader(context, 'Aktivni Filtri', 
                  trailing: TextButton.icon(
                    onPressed: () => _showAddSearchDialog(context, controller),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nov filter'),
                  )
                ),
                if (controller.savedSearches.isEmpty)
                  _buildEmptyState('Ni shranjenih filtrov.', Icons.filter_list_off)
                else
                  ...controller.savedSearches.map((s) => _SearchCard(config: s, controller: controller)),
                
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: controller.isScanning ? null : () => controller.runSequentialScan(forceAll: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('SKENIRAJ ZDAJ'),
                ),

                const SizedBox(height: 32),
                _buildSectionHeader(context, 'Zgodovina oglasov (${controller.savedListings.length})'),
                if (controller.savedListings.isEmpty)
                  _buildEmptyState('Ni zaznanih novih oglasov.', Icons.car_repair)
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: controller.savedListings.length,
                    itemBuilder: (context, i) => _HistoryItem(
                      listing: controller.savedListings[i],
                      onDelete: () => controller.removeListing(controller.savedListings[i].id),
                    ),
                  ),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildEmptyState(String msg, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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

  void _showAddSearchDialog(BuildContext context, AppController c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SearchTab(controller: c),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.config, required this.controller});
  final SearchConfig config;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(config.name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('Zadnji sken: ${config.lastChecked?.hour.toString().padLeft(2, '0')}:${config.lastChecked?.minute.toString().padLeft(2, '0') ?? "---"}', 
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                Switch(
                  value: config.isEnabled,
                  activeThumbColor: AppTheme.brandPurple,
                  onChanged: (val) => controller.toggleSearch(config.id, val),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(config.lastStatus.isEmpty ? 'Čaka na sken' : config.lastStatus, 
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: config.lastStatus.contains('Napaka') ? Colors.red : AppTheme.brandPurple)),
                Row(
                  children: [
                    IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () {}),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), 
                      onPressed: () => controller.deleteSearch(config.id)),
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.listing, required this.onDelete});
  final CarListing listing;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String bodyLabel = _bodyTypeToLabel(listing.bodyType);
    final String powerLabel = listing.powerKw > 0 ? ' • ${listing.powerKw} kW (${listing.powerHp} KM)' : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(listing.link), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80, height: 60,
                decoration: BoxDecoration(color: Colors.black.withAlpha(5), borderRadius: BorderRadius.circular(8)),
                child: listing.imageUrl.isEmpty 
                  ? const Icon(Icons.directions_car, color: Colors.grey)
                  : Image.network(listing.imageUrl, fit: BoxFit.cover, 
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.directions_car, color: Colors.grey)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${listing.year.isEmpty ? "/" : listing.year} • ${listing.fuel.isEmpty ? "/" : listing.fuel} • ${listing.mileage.isEmpty ? "/" : listing.mileage}', 
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('$bodyLabel$powerLabel', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(listing.price, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                        IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _bodyTypeToLabel(int code) {
    switch (code) {
      case 11: return 'Limuzina';
      case 12: return 'Hatchback';
      case 13: return 'Karavan';
      case 14: return 'Enoprostorec';
      case 15: return 'SUV';
      case 16: return 'Coupe';
      case 17: return 'Cabrio';
      case 18: return 'Pick-up';
      default: return 'Neznano';
    }
  }
}
