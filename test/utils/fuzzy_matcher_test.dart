import 'package:flutter_test/flutter_test.dart';
import 'package:spotube/utils/fuzzy_matcher.dart';

void main() {
  group('FuzzyMatcher.score', () {
    test('exact match returns 100', () {
      expect(FuzzyMatcher.score('hello world', 'hello world'), equals(100));
    });
    test('case-insensitive match returns 100', () {
      expect(FuzzyMatcher.score('Hello', 'heLLo'), equals(100));
    });
    test('different strings lower score', () {
      final score = FuzzyMatcher.score('hello world', 'goodbye moon');
      expect(score, lessThan(100));
      expect(score, greaterThan(0));
    });
  });
}
