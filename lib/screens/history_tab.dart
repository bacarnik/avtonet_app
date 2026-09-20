import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_controller.dart';
import '../models/car_listing.dart';
import '../models/history_filter.dart';
import '../data/body_types.dart';
import '../data/filter_options.dart';
import '../models/search_config.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key, required this.controller});
  final AppController controller;

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  bool showFilters = false;
  
  late TextEditingController _priceMinCtrl;
  late TextEditingController _priceMaxCtrl;
  late TextEditingController _yearMinCtrl;
  late TextEditingController _yearMaxCtrl;

  @override
  void initState() {
    super.initState();
    final hf = widget.controller.historyFilter;
    _priceMinCtrl = TextEditingController(text: hf.priceMin?.toString() ?? '');
    _priceMaxCtrl = TextEditingController(text: hf.priceMax?.toString() ?? '');
    _yearMinCtrl = TextEditingController(text: hf.yearMin?.toString() ?? '');
    _yearMaxCtrl = TextEditingController(text: hf.yearMax?.toString() ?? '');
  }

  @override
  void dispose() {
    _priceMinCtrl.dispose();
    _priceMaxCtrl.dispose();
    _yearMinCtrl.dispose();
    _yearMaxCtrl.dispose();
    super.dispose();
  }

  void _updateFilter(HistoryFilter nf) {
    widget.controller.updateHistoryFilter(nf);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final allListings = widget.controller.savedListings;
        final hf = widget.controller.historyFilter;
        final filteredListings = _applyFiltersAndSort(allListings, hf);

        // Sync controllers if reset happened
        if (hf.priceMin == null && _priceMinCtrl.text.isNotEmpty) _priceMinCtrl.clear();
        if (hf.priceMax == null && _priceMaxCtrl.text.isNotEmpty) _priceMaxCtrl.clear();
        if (hf.yearMin == null && _yearMinCtrl.text.isNotEmpty) _yearMinCtrl.clear();
        if (hf.yearMax == null && _yearMaxCtrl.text.isNotEmpty) _yearMaxCtrl.clear();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Zgodovina oglasov'),
            actions: [
              IconButton(
                icon: Icon(showFilters ? Icons.filter_alt_off : Icons.filter_alt_outlined),
                onPressed: () => setState(() => showFilters = !showFilters),
              ),
              if (allListings.isNotEmpty)
                IconButton(
                  tooltip: 'Počisti zgodovino',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                  onPressed: () => _confirmClearHistory(context),
                ),
            ],
          ),
          body: Column(
            children: [
              if (showFilters) _buildFilterPanel(hf),
              _buildSortBar(hf, allListings.length, filteredListings.length),
              Expanded(
                child: filteredListings.isEmpty
                    ? _buildEmptyState(allListings.isEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: filteredListings.length,
                        itemBuilder: (context, i) => _HistoryCard(
                          listing: filteredListings[i],
                          onDelete: () => widget.controller.removeListing(filteredListings[i].id),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterPanel(HistoryFilter hf) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // FIX: Expanded to prevent overflow
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: hf.make.isEmpty ? '' : hf.make,
                  decoration: const InputDecoration(labelText: 'Znamka', isDense: true),
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('Vse')),
                    ...widget.controller.makes.map((m) => DropdownMenuItem<String>(
                      value: m, 
                      child: Text(m, overflow: TextOverflow.ellipsis)
                    )),
                  ],
                  onChanged: (v) => _updateFilter(hf.copyWith(make: v ?? '', model: '')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: hf.model.isEmpty ? null : hf.model,
                  decoration: const InputDecoration(labelText: 'Model', isDense: true),
                  items: ['', ...widget.controller.modelsForMake(hf.make)].map((m) => DropdownMenuItem<String>(
                    value: m, 
                    child: Text(m.isEmpty ? 'Vsi' : m, overflow: TextOverflow.ellipsis)
                  )).toList(),
                  onChanged: (v) => _updateFilter(hf.copyWith(model: v ?? '')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: hf.bodyCode == 0 ? null : hf.bodyCode,
                  decoration: const InputDecoration(labelText: 'Oblika', isDense: true),
                  items: kBodyTypes.map((b) => DropdownMenuItem<int>(
                    value: b.code, 
                    child: Text(b.label, overflow: TextOverflow.ellipsis)
                  )).toList(),
                  onChanged: (v) => _updateFilter(hf.copyWith(bodyCode: v ?? 0)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: hf.fuelCode == 0 ? null : hf.fuelCode,
                  decoration: const InputDecoration(labelText: 'Gorivo', isDense: true),
                  items: kFuelOptions.map((f) => DropdownMenuItem<int>(
                    value: f.code, 
                    child: Text(f.label, overflow: TextOverflow.ellipsis)
                  )).toList(),
                  onChanged: (v) => _updateFilter(hf.copyWith(fuelCode: v ?? 0)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _priceMinCtrl,
                  decoration: const InputDecoration(labelText: 'Cena Min', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _updateFilter(hf.copyWith(priceMin: int.tryParse(v))),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _priceMaxCtrl,
                  decoration: const InputDecoration(labelText: 'Cena Max', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _updateFilter(hf.copyWith(priceMax: int.tryParse(v))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              widget.controller.resetHistoryFilter();
              _priceMinCtrl.clear();
              _priceMaxCtrl.clear();
              _yearMinCtrl.clear();
              _yearMaxCtrl.clear();
            },
            child: const Text('PONASTAVI FILTRE'),
          ),
        ],
      ),
    );
  }

  Widget _buildSortBar(HistoryFilter hf, int total, int filtered) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Row(
        children: [
          Text('$filtered/$total oglasov', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const Spacer(),
          const Text('Sortiraj:', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: hf.sortType,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
            dropdownColor: theme.colorScheme.surface,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'date', child: Text('Datum')),
              DropdownMenuItem(value: 'price', child: Text('Cena')),
              DropdownMenuItem(value: 'year', child: Text('Letnik')),
              DropdownMenuItem(value: 'km', child: Text('Kilometri')),
            ],
            onChanged: (v) {
              if (v != null) {
                _updateFilter(hf.copyWith(sortType: v));
              }
            },
          ),
          IconButton(
            icon: Icon(hf.sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16),
            onPressed: () => _updateFilter(hf.copyWith(sortAscending: !hf.sortAscending)),
          ),
        ],
      ),
    );
  }

  List<CarListing> _applyFiltersAndSort(List<CarListing> source, HistoryFilter hf) {
    final filtered = source.where((l) {
      if (hf.make.isNotEmpty) {
        final titleLower = l.title.toLowerCase();
        final makeLower = hf.make.toLowerCase();
        bool makeMatch = titleLower.contains(RegExp('\\b${RegExp.escape(makeLower)}\\b'));
        if (!makeMatch && makeLower == 'volkswagen') {
          makeMatch = titleLower.contains(RegExp(r'\bvw\b'));
        }
        if (!makeMatch) return false;
      }
      
      if (hf.model.isNotEmpty && !l.title.toLowerCase().contains(hf.model.toLowerCase())) return false;
      
      final price = int.tryParse(l.price.replaceAll(RegExp(r'\D'), ''));
      if (price != null) {
        if (hf.priceMin != null && price < hf.priceMin!) return false;
        if (hf.priceMax != null && price > hf.priceMax!) return false;
      }

      final year = int.tryParse(l.year);
      if (year != null) {
        if (hf.yearMin != null && year < hf.yearMin!) return false;
        if (hf.yearMax != null && year > hf.yearMax!) return false;
      }

      if (hf.bodyCode != 0) {
        // Strict match if body type was successfully parsed
        if (l.bodyType != 0 && l.bodyType != hf.bodyCode) return false;
        
        // If body type is unknown (0), we check if the search that found this ad 
        // actually requested this body type.
        if (l.bodyType == 0) {
          final config = widget.controller.savedSearches.firstWhere(
            (s) => s.id == l.searchConfigId,
            orElse: () => SearchConfig(id: '', name: '', znamka: ''),          );
          if (config.id.isNotEmpty) {
            final configBodyCodes = config.oblika.split(',').map((e) => int.tryParse(e)).whereType<int>();
            if (!configBodyCodes.contains(hf.bodyCode)) return false;
          } else {
            // No config info, and bodyType is 0, hide it from specific body filter
            return false;
          }
        }
      }

      if (hf.fuelCode != 0) {
          final fuelText = l.fuel.toLowerCase();
          if (hf.fuelCode == 201 && !fuelText.contains('bencin')) return false;
          if (hf.fuelCode == 202 && !(fuelText.contains('diesel') || fuelText.contains('dizel'))) return false;
          if (hf.fuelCode == 203 && !fuelText.contains('lpg')) return false;
          if (hf.fuelCode == 204 && !fuelText.contains('hibrid')) return false;
          if (hf.fuelCode == 205 && !(fuelText.contains('elektro') || fuelText.contains('električni'))) return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      int cmp = 0;
      switch (hf.sortType) {
        case 'price':
          final pa = int.tryParse(a.price.replaceAll(RegExp(r'\D'), '')) ?? 0;
          final pb = int.tryParse(b.price.replaceAll(RegExp(r'\D'), '')) ?? 0;
          cmp = pa.compareTo(pb);
          break;
        case 'year':
          final ya = int.tryParse(a.year) ?? 0;
          final yb = int.tryParse(b.year) ?? 0;
          cmp = ya.compareTo(yb);
          break;
        case 'km':
          final ka = int.tryParse(a.mileage.replaceAll(RegExp(r'\D'), '')) ?? 0;
          final kb = int.tryParse(b.mileage.replaceAll(RegExp(r'\D'), '')) ?? 0;
          cmp = ka.compareTo(kb);
          break;
        case 'date':
        default:
          final da = a.foundAt ?? DateTime(1970);
          final db = b.foundAt ?? DateTime(1970);
          cmp = da.compareTo(db);
          break;
      }
      return hf.sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  Widget _buildEmptyState(bool noData) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(noData ? Icons.history_toggle_off : Icons.filter_list_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(noData ? 'Ni zaznanih novih oglasov.' : 'Noben oglas ne ustreza filtrom.', 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory(BuildContext context) async {
    if (await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Clear History?'), content: const Text('This will delete all captured vehicle records.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CLEAR ALL'))])) == true) await widget.controller.clearListings();
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.listing, required this.onDelete});
  final CarListing listing;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String displayMileage = (listing.mileage.isEmpty || listing.mileage == '0 km') ? '/' : listing.mileage;
    final String displayYear = listing.year.isEmpty ? '/' : listing.year;
    final String displayFuel = listing.fuel.isEmpty ? '/' : listing.fuel;
    final String displayTime = listing.foundAt != null ? '${listing.foundAt!.day}.${listing.foundAt!.month}. ob ${listing.foundAt!.hour}:${listing.foundAt!.minute.toString().padLeft(2, "0")}' : '';
    
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
                width: 90, 
                height: 70, 
                decoration: BoxDecoration(color: Colors.black.withAlpha(10), borderRadius: BorderRadius.circular(8)), 
                child: listing.imageUrl.isEmpty 
                  ? const Icon(Icons.directions_car, color: Colors.grey) 
                  : Image.network(
                      listing.imageUrl, 
                      fit: BoxFit.cover, 
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.directions_car, color: Colors.grey)
                    )
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(listing.title, style: theme.textTheme.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('$displayYear • $displayFuel • $displayMileage', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text('$bodyLabel$powerLabel', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 10)),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(listing.price, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 17)), if (displayTime.isNotEmpty) Text(displayTime, style: const TextStyle(fontSize: 9, color: Colors.grey))]),
                  IconButton(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey)),
                ]),
              ])),
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
