/// Utility for normalizing Slovenian characters and strings for reliable matching.
abstract final class StringUtils {
  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('č', 'c')
        .replaceAll('š', 's')
        .replaceAll('ž', 'z')
        .replaceAll('ć', 'c')
        .replaceAll('đ', 'd')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool contains(String source, String query) {
    if (query.isEmpty) return true;
    return normalize(source).contains(normalize(query));
  }

  static bool equals(String a, String b) {
    return normalize(a) == normalize(b);
  }
}
