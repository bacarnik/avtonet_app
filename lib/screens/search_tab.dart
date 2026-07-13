import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../data/filter_options.dart';
import '../widgets/body_type_grid.dart';

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _kmMinCtrl;
  late final TextEditingController _kmMaxCtrl;
  late final TextEditingController _letnikMinCtrl;
  late final TextEditingController _letnikMaxCtrl;
  late final TextEditingController _cenaMinCtrl;
  late final TextEditingController _cenaMaxCtrl;
  late final TextEditingController _mocMinCtrl;
  late final TextEditingController _mocMaxCtrl;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: c.draftSearchName);
    _kmMinCtrl = TextEditingController(text: c.kmMinText);
    _kmMaxCtrl = TextEditingController(text: c.kmMaxText);
    _letnikMinCtrl = TextEditingController(text: c.letnikMinText);
    _letnikMaxCtrl = TextEditingController(text: c.letnikMaxText);
    _cenaMinCtrl = TextEditingController(text: c.cenaMinText);
    _cenaMaxCtrl = TextEditingController(text: c.cenaMaxText);
    _mocMinCtrl = TextEditingController(text: c.mocMinText);
    _mocMaxCtrl = TextEditingController(text: c.mocMaxText);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kmMinCtrl.dispose();
    _kmMaxCtrl.dispose();
    _letnikMinCtrl.dispose();
    _letnikMaxCtrl.dispose();
    _cenaMinCtrl.dispose();
    _cenaMaxCtrl.dispose();
    _mocMinCtrl.dispose();
    _mocMaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ListenableBuilder(
                listenable: c,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        c.editingId == null ? 'Nova konfiguracija' : 'Uredi iskanje',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      
                      _fieldLabel('Ime iskanja'),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(hintText: 'npr. BMW serija 3'),
                        onChanged: c.setDraftSearchName,
                      ),
                      const SizedBox(height: 20),
                      
                      _fieldLabel('Znamka in model'),
                      _makeDropdown(),
                      const SizedBox(height: 12),
                      _modelDropdown(),
                      const SizedBox(height: 20),

                      _fieldLabel('Oblika vozila (več možnosti)'),
                      BodyTypeGrid(
                        selectedCodes: c.selectedBodyTypes,
                        onSelected: c.toggleBodyType,
                      ),
                      const SizedBox(height: 24),

                      _fieldLabel('Cena (€)'),
                      _pair(_cenaMinCtrl, 'Min', c.setCenaMin, _cenaMaxCtrl, 'Max', c.setCenaMax),
                      const SizedBox(height: 16),

                      _fieldLabel('Letnik'),
                      _pair(_letnikMinCtrl, 'Od', c.setLetnikMin, _letnikMaxCtrl, 'Do', c.setLetnikMax),
                      const SizedBox(height: 16),

                      _fieldLabel('Kilometri'),
                      _pair(_kmMinCtrl, 'Min', c.setKmMin, _kmMaxCtrl, 'Max', c.setKmMax),
                      const SizedBox(height: 24),

                      // NEW: Power Unit Toggle (kW / KM)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _fieldLabel('Moč motorja'),
                          ToggleButtons(
                            borderRadius: BorderRadius.circular(8),
                            constraints: const BoxConstraints(minHeight: 28, minWidth: 48),
                            isSelected: [c.powerUnit == 'kW', c.powerUnit == 'KM'],
                            onPressed: (index) {
                              c.setPowerUnit(index == 0 ? 'kW' : 'KM');
                            },
                            children: const [
                              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('kW', style: TextStyle(fontSize: 11))),
                              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('KM', style: TextStyle(fontSize: 11))),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _pair(_mocMinCtrl, 'Min (${c.powerUnit})', c.setMocMin, _mocMaxCtrl, 'Max (${c.powerUnit})', c.setMocMax),
                      const SizedBox(height: 24),

                      _fieldLabel('Gorivo in menjalnik'),
                      _fuelDropdown(),
                      const SizedBox(height: 12),
                      _transmissionDropdown(),
                      
                      const SizedBox(height: 40),

                      ElevatedButton(
                        onPressed: () async {
                          final success = await c.saveCurrentSearch();
                          if (success && mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        child: Text(
                          c.editingId == null ? 'SHRANI ISKANJE' : 'POSODOBI ISKANJE',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(t, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
  );

  /// Fixed Row Overflows with Expanded/Flexible.
  Widget _pair(
    TextEditingController a,
    String aLabel,
    void Function(String) onA,
    TextEditingController b,
    String bLabel,
    void Function(String) onB,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: a,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: aLabel),
            onChanged: onA,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: b,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: bLabel),
            onChanged: onB,
          ),
        ),
      ],
    );
  }

  Widget _makeDropdown() {
    return DropdownButtonFormField<String>(
      value: c.selectedMake,
      isExpanded: true,
      items: [
        const DropdownMenuItem(value: '', child: Text('Vse znamke')),
        ...c.allBrands.map((b) => DropdownMenuItem(
              value: b.value,
              child: Text(b.displayName, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: c.onMakeChanged,
    );
  }

  Widget _modelDropdown() {
    return DropdownButtonFormField<String>(
      value: c.selectedModel,
      isExpanded: true,
      items: ['', ...c.models]
          .map((m) => DropdownMenuItem(value: m, child: Text(m.isEmpty ? 'Vsi modeli' : m, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: c.isModelDropdownEnabled ? c.onModelChanged : null,
    );
  }

  Widget _fuelDropdown() {
    return DropdownButtonFormField<int>(
      value: c.selectedFuel,
      isExpanded: true,
      items: kFuelOptions
          .map((f) => DropdownMenuItem(value: f.code, child: Text(f.label, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (v) => c.onFuelChanged(v),
    );
  }

  Widget _transmissionDropdown() {
    return DropdownButtonFormField<String>(
      value: c.selectedTransmission,
      isExpanded: true,
      items: kTransmissionOptions
          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.label, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: c.onTransmissionChanged,
    );
  }
}
