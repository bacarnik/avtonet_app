import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avtonet_app/parsers/avtonet_html_parser.dart';
import 'package:avtonet_app/widgets/body_type_grid.dart';

void main() {
  group('Image URL Parsing Tests', () {
    test('Zavrne placeholder src in vzame pravi data-src z // protocol-relative URL', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=12345">BMW 420d Coupé</a>
          </div>
          <div class="GO-Results-Photo">
            <img src="/images/blank.gif" data-src="//photo.avto.net/12345/1.jpg" />
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.imageUrl, equals('https://photo.avto.net/12345/1.jpg'));
    });

    test('Vzame data-original, če je na voljo', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=12346">BMW 120i Cabrio</a>
          </div>
          <div class="GO-Results-Photo">
            <img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" data-original="https://photo.avto.net/12346/1.jpg" />
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.imageUrl, equals('https://photo.avto.net/12346/1.jpg'));
    });

    test('Pravilno razreši navaden relativni URL s poševnico', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=12347">VW Golf VII</a>
          </div>
          <div class="GO-Results-Photo">
            <img src="/photo/12347/1.jpg" />
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.imageUrl, equals('https://www.avto.net/photo/12347/1.jpg'));
    });

    test('Zavrne samostojen placeholder brez prave fotografije', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=12348">Vozilo brez slike</a>
          </div>
          <div class="GO-Results-Photo">
            <img src="/images/blank.gif" />
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.imageUrl, equals(''));
    });
  });

  group('Body Type Detection Tests', () {
    test('Ekspliciten Coupé v naslovu dobi kodo 16 ne glede na scope z 3 vrat', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=22848430">BMW serija 4 Coupé 420d</a>
          </div>
          <div class="GO-Results-Row-Data-Data">
            letnik 2017 • 185.000 km • 3 vrat • diesel
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.bodyType, equals(16)); // Coupe
    });

    test('Ekspliciten Cabrio v naslovu dobi kodo 17', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=22818949">BMW serija 1 120i Cabrio</a>
          </div>
          <div class="GO-Results-Row-Data-Data">
            letnik 2010 • 140.000 km • 2 vrat • bencin
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.bodyType, equals(17)); // Cabrio
    });

    test('Compact v naslovu dobi kodo 12 (Hatchback)', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=22818950">BMW serija 1 118d Compact</a>
          </div>
          <div class="GO-Results-Row-Data-Data">
            letnik 2004 • 200.000 km • diesel
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.bodyType, equals(12)); // Hatchback
    });

    test('Avant/Karavan v naslovu dobi kodo 13 (Karavan)', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=22818951">Audi A4 Avant 2.0 TDI</a>
          </div>
          <div class="GO-Results-Row-Data-Data">
            letnik 2018 • 150.000 km • 5 vrat
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.bodyType, equals(13)); // Karavan
    });

    test('SUV v naslovu ali scope dobi kodo 15 (SUV)', () {
      const htmlSnippet = '''
        <div class="GO-Results-Row">
          <div class="GO-Results-Naziv">
            <a class="stretched-link" href="details.asp?id=22818952">BMW X5 xDrive30d SUV</a>
          </div>
          <div class="GO-Results-Row-Data-Data">
            letnik 2020 • 80.000 km • terensko
          </div>
        </div>
      ''';

      final listings = AvtonetHtmlParser.parseListings(htmlSnippet);
      expect(listings, hasLength(1));
      expect(listings.first.bodyType, equals(15)); // SUV
    });
  });

  group('UI BodyTypeGrid Widget Tests', () {
    testWidgets('Ikone karoserij niso prisotne, tekstovne oznake pa so vidne in delujoče', (WidgetTester tester) async {
      int selectedCode = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BodyTypeGrid(
              selectedCodes: const [],
              onSelected: (code) {
                selectedCode = code;
              },
            ),
          ),
        ),
      );

      // Verify NO icons are present in BodyTypeGrid
      expect(find.byType(Icon), findsNothing);

      // Verify text labels ARE present
      expect(find.text('Katerikoli'), findsOneWidget);
      expect(find.text('Limuzina'), findsOneWidget);
      expect(find.text('Coupe'), findsOneWidget);
      expect(find.text('Cabrio'), findsOneWidget);

      // Tap on 'Coupe' label (code 16)
      await tester.tap(find.text('Coupe'));
      await tester.pump();

      // Verify onSelected callback fired with code 16
      expect(selectedCode, equals(16));
    });
  });
}
