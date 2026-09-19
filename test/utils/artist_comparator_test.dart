import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/artist_comparator.dart';

void main() {
  group('ArtistComparator.sameName', () {
    test('case-insensitive match', () {
      expect(ArtistComparator.sameName('Daft Punk', 'daft punk'), isTrue);
    });
    test('ampersand handling', () {
      expect(ArtistComparator.sameName('Simon & Garfunkel', 'Simon and Garfunkel'), isTrue);
    });
    test('featuring removal', () {
      expect(ArtistComparator.sameName('Coldplay feat. Beyonce', 'Coldplay'), isTrue);
    });
    test('different artists', () {
      expect(ArtistComparator.sameName('Radiohead', 'The Beatles'), isFalse);
    });
  });
}
