import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_controller.dart';
import '../models/car_listing.dart';
import '../theme/app_theme.dart';

class MatchesTab extends StatelessWidget {
  const MatchesTab({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final listings = controller.savedListings;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'NOVI ZADETKI (${listings.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0, fontSize: 13),
                    ),
                  ),
                  if (listings.isNotEmpty)
                    TextButton(
                      onPressed: () => _confirmClear(context),
                      child: const Text('POČISTI VSE'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: listings.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: listings.length,
                      itemBuilder: (context, i) => _MatchCard(
                        listing: listings[i],
                        onDelete: () => controller.removeListing(listings[i].id),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 64, color: AppTheme.darkTextMuted),
          SizedBox(height: 16),
          Text(
            'Brez novih obvestil',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tukaj se bodo pojavili novi oglasi, ko jih sistem zazna.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.darkTextMuted),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Izbris vseh oglasov?'),
        content: const Text('Tega dejanja ni mogoče razveljaviti.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('PREKLIČI')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('IZBRIŠI')),
        ],
      ),
    );
    if (ok == true) await controller.clearListings();
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.listing, required this.onDelete});

  final CarListing listing;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(listing.link), mode: LaunchMode.externalApplication),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 100,
                height: 75,
                decoration: BoxDecoration(
                  color: AppTheme.brandPurple.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: listing.imageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          listing.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.image, color: AppTheme.darkTextMuted),
                        ),
                      )
                    : const Icon(Icons.image, color: AppTheme.darkTextMuted, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${listing.year} • ${listing.mileage}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          listing.price,
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.darkTextMuted),
                          onPressed: onDelete,
                        ),
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
}
