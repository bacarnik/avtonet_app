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

  late final FocusNode _nameFocus;
  late final FocusNode _kmMinFocus;
  late final FocusNode _kmMaxFocus;
  late final FocusNode _letnikMinFocus;
  late final FocusNode _letnikMaxFocus;
  late final FocusNode _cenaMinFocus;
  late final FocusNode _cenaMaxFocus;
  late final FocusNode _mocMinFocus;
  late final FocusNode _mocMaxFocus;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onControllerChanged);
    _nameFocus = FocusNode();
    _kmMinFocus = FocusNode();
    _kmMaxFocus = FocusNode();
    _letnikMinFocus = FocusNode();
    _letnikMaxFocus = FocusNode();
    _cenaMinFocus = FocusNode();
    _cenaMaxFocus = FocusNode();
    _mocMinFocus = FocusNode();
    _mocMaxFocus = FocusNode();

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
    c.removeListener(_onControllerChanged);
    _nameFocus.dispose();
    _kmMinFocus.dispose();
    _kmMaxFocus.dispose();
    _letnikMinFocus.dispose();
    _letnikMaxFocus.dispose();
    _cenaMinFocus.dispose();
    _cenaMaxFocus.dispose();
    _mocMinFocus.dispose();
    _mocMaxFocus.dispose();

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

  void _onControllerChanged() {
    _syncController(_nameCtrl, _nameFocus, c.draftSearchName);
    _syncController(_kmMinCtrl, _kmMinFocus, c.kmMinText ?? '');
    _syncController(_kmMaxCtrl, _kmMaxFocus, c.kmMaxText ?? '');
    _syncController(_letnikMinCtrl, _letnikMinFocus, c.letnikMinText ?? '');
    _syncController(_letnikMaxCtrl, _letnikMaxFocus, c.letnikMaxText ?? '');
    _syncController(_cenaMinCtrl, _cenaMinFocus, c.cenaMinText ?? '');
    _syncController(_cenaMaxCtrl, _cenaMaxFocus, c.cenaMaxText ?? '');
    _syncController(_mocMinCtrl, _mocMinFocus, c.mocMinText ?? '');
    _syncController(_mocMaxCtrl, _mocMaxFocus, c.mocMaxText ?? '');
  }

  void _syncController(TextEditingController ctrl, FocusNode fn, String expected) {
    if (!fn.hasFocus && ctrl.text != expected) {
      ctrl.text = expected;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Text(
                      c.editingId == null ? 'Nova konfiguracija' : 'Uredi iskanje',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: 24),

                  _fieldLabel('Ime iskanja'),
                  TextField(
                    controller: _nameCtrl,
                    focusNode: _nameFocus,
                    decoration: const InputDecoration(hintText: 'npr. BMW serija 3'),
                    onChanged: c.setDraftSearchName,
                  ),
                  const SizedBox(height: 20),

                  _fieldLabel('Znamka in model'),
                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                      children: [
                        _makeDropdown(),
                        const SizedBox(height: 12),
                        _modelDropdown(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  _fieldLabel('Oblika vozila (več možnosti)'),
                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => BodyTypeGrid(
                      selectedCodes: c.selectedBodyTypes,
                      onSelected: c.toggleBodyType,
                    ),
                  ),
                  const SizedBox(height: 24),

                  _fieldLabel('Cena (€)'),
                  _pair(_cenaMinCtrl, _cenaMinFocus, 'Min', c.setCenaMin, _cenaMaxCtrl, _cenaMaxFocus, 'Max', c.setCenaMax),
                  const SizedBox(height: 16),

                  _fieldLabel('Letnik'),
                  _pair(_letnikMinCtrl, _letnikMinFocus, 'Od', c.setLetnikMin, _letnikMaxCtrl, _letnikMaxFocus, 'Do', c.setLetnikMax),
                  const SizedBox(height: 16),

                  _fieldLabel('Kilometri'),
                  _pair(_kmMinCtrl, _kmMinFocus, 'Min', c.setKmMin, _kmMaxCtrl, _kmMaxFocus, 'Max', c.setKmMax),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _fieldLabel('Moč motorja'),
                      ListenableBuilder(
                        listenable: c,
                        builder: (context, _) => ToggleButtons(
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => _pair(
                      _mocMinCtrl,
                      _mocMinFocus,
                      'Min (${c.powerUnit})',
                      c.setMocMin,
                      _mocMaxCtrl,
                      _mocMaxFocus,
                      'Max (${c.powerUnit})',
                      c.setMocMax,
                    ),
                  ),
                  const SizedBox(height: 24),

                  _fieldLabel('Gorivo in menjalnik'),
                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => Column(
                      children: [
                        _fuelDropdown(),
                        const SizedBox(height: 12),
                        _transmissionDropdown(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  ListenableBuilder(
                    listenable: c,
                    builder: (context, _) => ElevatedButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        final success = await c.saveCurrentSearch();
                        if (success && mounted) {
                          nav.pop();
                        }
                      },
                      child: Text(
                        c.editingId == null ? 'SHRANI ISKANJE' : 'POSODOBI ISKANJE',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
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

  Widget _pair(
    TextEditingController a,
    FocusNode aFocus,
    String aLabel,
    void Function(String) onA,
    TextEditingController b,
    FocusNode bFocus,
    String bLabel,
    void Function(String) onB,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: a,
            focusNode: aFocus,
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
            focusNode: bFocus,
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
    final brands = c.allBrands;

    final topNames = [
      'Audi',
      'BMW',
      'Mercedes-Benz',
      'Renault',
      'Škoda',
      'Volkswagen'
    ];

    final topBrands = [];
    final topValues = <String>{};

    for (var name in topNames) {
      try {
        final b = brands.firstWhere((b) => b.displayName == name);
        topBrands.add(b);
        topValues.add(b.value);
      } catch (_) {}
    }

    final remainingBrands = brands.where((b) => !topValues.contains(b.value)).toList();
    remainingBrands.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
    );

    final items = <DropdownMenuItem<String>>[];

    items.add(const DropdownMenuItem(value: '', child: Text('Izberi znamko')));

    items.add(const DropdownMenuItem(
      value: '---sep-fav---',
      enabled: false,
      child: Center(
        child: Text(
          '──────── PRILJUBLJENE ────────',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    ));

    for (var b in topBrands) {
      items.add(DropdownMenuItem(
        value: b.value,
        child: Text(b.displayName, overflow: TextOverflow.ellipsis),
      ));
    }

    items.add(const DropdownMenuItem(
      value: '---sep-all---',
      enabled: false,
      child: Center(
        child: Text(
          '──────── VSE ZNAMKE ────────',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    ));

    for (var b in remainingBrands) {
      items.add(DropdownMenuItem(
        value: b.value,
        child: Text(b.displayName, overflow: TextOverflow.ellipsis),
      ));
    }

    return DropdownButtonFormField<String>(
      value: c.selectedMake,
      isExpanded: true,
      items: items,
      onChanged: (val) {
        if (val != null && !val.startsWith('---sep-')) {
          c.onMakeChanged(val);
        }
      },
    );
  }

  Widget _modelDropdown() {
    final availableModels = c.availableModels;
    final items = <DropdownMenuItem<String>>[];

    items.add(const DropdownMenuItem(
      value: '',
      child: Text('Vsi modeli', overflow: TextOverflow.ellipsis),
    ));

    bool inGroup = false;

    for (final m in availableModels) {
      final isGroup = (m.subModelGroup != null && m.subModelGroup!.isNotEmpty) ||
          m.displayName.toLowerCase().contains('(vsi)');

      if (isGroup) {
        inGroup = true;
      } else if (m.modelId != null && m.modelId!.isNotEmpty) {
        inGroup = false;
      }

      String displayText = m.displayName;
      if (displayText.endsWith(':')) {
        displayText = displayText.substring(0, displayText.length - 1);
      }

      if (inGroup && !isGroup) {
        displayText = '    $displayText';
      }

      items.add(DropdownMenuItem<String>(
        value: m.displayName,
        child: Text(
          displayText,
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }

    return DropdownButtonFormField<String>(
      value: c.selectedModel,
      isExpanded: true,
      items: items,
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
