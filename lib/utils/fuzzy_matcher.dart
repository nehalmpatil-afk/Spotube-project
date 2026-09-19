import 'package:fuzzywuzzy/fuzzywuzzy.dart';

/// Utility class for fuzzy string matching.
/// Uses the `fuzzywuzzy` Dart package.
///
/// The `score` method returns an integer similarity score in the range 0‑100,
/// where 100 means the strings are exactly the same after case‑insensitive
/// comparison. The algorithm employed is the standard Levenshtein‑based ratio
/// used by the original Python fuzzywuzzy library.
class FuzzyMatcher {
  /// Returns the fuzzy similarity ratio between two input strings.
  ///
  /// The comparison is case‑insensitive and works on the raw strings. The
  /// caller may pre‑process the inputs (e.g., with `StringUtils.normalize`) if
  /// needed.
  static int score(String a, String b) {
    // The `ratio` function from the fuzzywuzzy package returns an int 0‑100.
    return ratio(a.toLowerCase(), b.toLowerCase());
  }
}
