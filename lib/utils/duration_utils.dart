class DurationUtils {
  /// Returns true if [a] and [b] are within [tolerance] of each other.
  /// Default tolerance is 5 seconds.
  static bool isClose(Duration a, Duration b, {Duration tolerance = const Duration(seconds: 5)}) {
    return (a - b).abs() <= tolerance;
  }
}
