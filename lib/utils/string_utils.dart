class StringUtils {
  /// Normalizes a string for matching purposes.
  ///
  /// - Lowercases the string.
  /// - Trims leading/trailing whitespace.
  /// - Collapses consecutive whitespace characters into a single space.
  /// - Removes common diacritic characters (á → a, é → e, …).
  /// - Normalizes basic punctuation by removing characters that are not
  ///   alphanumeric, whitespace, or '&'.
  ///   This keeps words like "live", "remix", "acoustic", "instrumental",
  ///   "cover" intact.
  static String normalize(String input) {
    // Lowercase and trim.
    String result = input.toLowerCase().trim();

    // Replace common diacritics with their base characters.
    const diacriticMap = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
      'ß': 'ss',
    };
    result = result.split('').map((c) => diacriticMap[c] ?? c).join();

    // Collapse repeated whitespace.
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    // Remove punctuation except '&'. Keep alphanumerics and spaces.
    result = result.replaceAll(RegExp(r"[^a-z0-9 &]"), '');

    // Collapse any new multiple spaces produced by punctuation removal.
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    return result;
  }
}
