import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/string_utils.dart';

void main() {
  group('StringUtils.normalize', () {
    test('lowercases and trims', () {
      expect(StringUtils.normalize('  HeLLo WorLD  '), equals('hello world'));
    });
    test('collapses whitespace', () {
      expect(StringUtils.normalize('a   b \t c'), equals('a b c'));
    });
    test('removes diacritics', () {
      expect(StringUtils.normalize('Café'), equals('cafe'));
    });
    test('preserves & and important words', () {
      expect(StringUtils.normalize('Live Remix & Acoustic'), equals('live remix & acoustic'));
    });
    test('removes punctuation except &', () {
      expect(StringUtils.normalize('Hello! (World)'), equals('hello world'));
    });
  });
}
