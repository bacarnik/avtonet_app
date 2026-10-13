import 'package:flutter_test/flutter_test.dart';
import 'package:avtonet_app/models/car_listing.dart';
import 'package:avtonet_app/models/history_filter.dart';
import 'package:avtonet_app/screens/history_tab.dart';

void main() {
  group('History Filter Tests', () {
    final listings = [
      const CarListing(
        id: '1',
        title: 'BMW serija 3: 320d Touring',
        price: '15.000 €',
        link: 'https://www.avto.net/1',
      ),
      const CarListing(
        id: '2',
        title: 'BMW serija 3 Coupé 330i xDrive',
        price: '18.000 €',
        link: 'https://www.avto.net/2',
      ),
      const CarListing(
        id: '3',
        title: 'BMW serija 3 Cabrio 325i',
        price: '16.000 €',
        link: 'https://www.avto.net/3',
      ),
      const CarListing(
        id: '4',
        title: 'BMW serija 3 Gran Turismo 320d',
        price: '17.000 €',
        link: 'https://www.avto.net/4',
      ),
      const CarListing(
        id: '5',
        title: 'BMW 320d xDrive Aut.',
        price: '14.000 €',
        link: 'https://www.avto.net/5',
      ),
      const CarListing(
        id: '6',
        title: 'BMW serija 5: 520d Touring',
        price: '22.000 €',
        link: 'https://www.avto.net/6',
      ),
      const CarListing(
        id: '7',
        title: 'Volkswagen Golf VII 1.6 TDI Comfortline',
        price: '10.000 €',
        link: 'https://www.avto.net/7',
      ),
      const CarListing(
        id: '8',
        title: 'Volkswagen Golf Variant 2.0 TDI Highline',
        price: '12.000 €',
        link: 'https://www.avto.net/8',
      ),
      const CarListing(
        id: '9',
        title: 'Volkswagen Golf Sportsvan 1.4 TSI Allstar',
        price: '11.000 €',
        link: 'https://www.avto.net/9',
      ),
      const CarListing(
        id: '10',
        title: 'Volkswagen Passat Variant 2.0 TDI',
        price: '15.000 €',
        link: 'https://www.avto.net/10',
      ),
      const CarListing(
        id: '11',
        title: 'Škoda Octavia Combi 2.0 TSI RS 245 DSG',
        price: '25.000 €',
        link: 'https://www.avto.net/11',
      ),
    ];

    test('BMW serija 3 (vsi) vključuje vse podmodele serije 3 in izključuje serijo 5', () {
      const hf = HistoryFilter(make: 'BMW', model: 'Serija 3 (vsi)');
      final matched = listings.where((l) {
        return matchesHistoryBrand(l.title, hf.make) &&
            matchesHistoryModel(l, hf.model, hf.make);
      }).toList();

      final ids = matched.map((l) => l.id).toList();
      expect(ids, containsAll(['1', '2', '3', '4', '5']));
      expect(ids, isNot(contains('6'))); // BMW serija 5 mora biti izključena
    });

    test('BMW serija 3 Coupé vrne samo Coupé in ne drugih podmodelov', () {
      const hf = HistoryFilter(make: 'BMW', model: 'serija 3 Coupé:');
      final matched = listings.where((l) {
        return matchesHistoryBrand(l.title, hf.make) &&
            matchesHistoryModel(l, hf.model, hf.make);
      }).toList();

      final ids = matched.map((l) => l.id).toList();
      expect(ids, equals(['2']));
    });

    test('Golf (vsi) vključuje vse ustreznice Golfa in izključuje Passata', () {
      const hf = HistoryFilter(make: 'Volkswagen', model: 'Golf (vsi)');
      final matched = listings.where((l) {
        return matchesHistoryBrand(l.title, hf.make) &&
            matchesHistoryModel(l, hf.model, hf.make);
      }).toList();

      final ids = matched.map((l) => l.id).toList();
      expect(ids, containsAll(['7', '8', '9']));
      expect(ids, isNot(contains('10'))); // Passat mora biti izključen
    });

    test('Znamka Škoda s šumnikom vključuje Škoda Octavio', () {
      const hf = HistoryFilter(make: 'Škoda', model: 'Octavia');
      final matched = listings.where((l) {
        return matchesHistoryBrand(l.title, hf.make) &&
            matchesHistoryModel(l, hf.model, hf.make);
      }).toList();

      final ids = matched.map((l) => l.id).toList();
      expect(ids, equals(['11']));
    });

    test('Oglasi, ki ne ustrezajo znamki, se izključijo', () {
      const hf = HistoryFilter(make: 'BMW', model: 'Octavia');
      final matched = listings.where((l) {
        return matchesHistoryBrand(l.title, hf.make) &&
            matchesHistoryModel(l, hf.model, hf.make);
      }).toList();

      expect(matched, isEmpty);
    });
  });
}
