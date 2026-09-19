class ArtistComparator {
  /// Returns true if two artist name strings refer to the same artist.
  ///
  /// Normalization steps:
  ///   * case‑insensitive comparison
  ///   * replace '&' with 'and'
  ///   * remove common featuring markers like "feat.", "featuring", "ft"
  ///   * collapse whitespace
  ///   * trim surrounding whitespace
  ///   * remove punctuation characters except alphanumerics and spaces
  static bool sameName(String a, String b) {
    String normalize(String input) {
      var s = input.toLowerCase().trim();
      s = s.replaceAll('&', 'and');
      s = s.replaceAll(RegExp(r"\b(feat|featuring|ft)\b.*"), '');
      s = s.replaceAll(RegExp(r"[^a-z0-9 ]"), '');
      s = s.replaceAll(RegExp(r"\s+"), ' ');
      return s.trim();
    }
    return normalize(a) == normalize(b);
  }
}
