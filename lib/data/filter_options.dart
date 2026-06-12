/// Gorivo – vrednosti parametra `bencin` na Avto.net.
class FuelOption {
  const FuelOption({required this.code, required this.label});
  final int code;
  final String label;
}

const List<FuelOption> kFuelOptions = [
  FuelOption(code: 0, label: 'Vsa'),
  FuelOption(code: 201, label: 'Bencin'),
  FuelOption(code: 202, label: 'Dizel'),
  FuelOption(code: 204, label: 'Hibrid'),
  FuelOption(code: 205, label: 'Elektrika'),
  FuelOption(code: 203, label: 'Plin'),
];

/// Menjalnik – shranjeno za prikaz; filtriranje prek EQ parametrov.
class TransmissionOption {
  const TransmissionOption({required this.id, required this.label, this.eq7});
  final String id;
  final String label;
  final String? eq7;
}

const List<TransmissionOption> kTransmissionOptions = [
  TransmissionOption(id: '', label: 'Vsi'),
  TransmissionOption(id: 'rocni', label: 'Ročni', eq7: '1110100120'),
  TransmissionOption(
    id: 'avtomatski',
    label: 'Avtomatski',
    eq7: '1110101120',
  ),
];
