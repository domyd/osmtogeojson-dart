/// Utility functions used during OSM-to-GeoJSON conversion.
library;

/// Type alias for the relation membership map:
///   `{memberType: {memberRef: [relationInfos]}}`
typedef RelationMembershipMap =
    Map<String, Map<String, List<Map<String, dynamic>>>>;

/// Removes the _fullGeom prefix from an ID and converts to a number if possible.
String cleanId(String id) {
  var cleaned = id.replaceFirst('_fullGeom', '');
  // Try to parse as int to normalize "123" vs 123
  final parsed = int.tryParse(cleaned);
  if (parsed != null) cleaned = parsed.toString();
  return cleaned;
}

/// Parses a tags map from JSON data, converting all values to strings.
Map<String, String> parseTags(dynamic tagsData) {
  if (tagsData is Map<String, dynamic>) {
    return tagsData.map((k, v) => MapEntry(k, v.toString()));
  }
  return {};
}

/// Recursively merges [source] into [target].
///
/// Deep-merges nested Maps; other values (including Lists) are overwritten.
/// Ported from lodash's `_.merge`.
Map<String, dynamic> deepMerge(
  Map<String, dynamic> target,
  Map<String, dynamic> source,
) {
  final result = Map<String, dynamic>.from(target);
  for (final entry in source.entries) {
    if (result[entry.key] is Map<String, dynamic> &&
        entry.value is Map<String, dynamic>) {
      result[entry.key] = deepMerge(
        result[entry.key] as Map<String, dynamic>,
        entry.value as Map<String, dynamic>,
      );
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

/// Default deduplication handler.
///
/// If object versions differ, use the highest available version.
/// Otherwise, merge properties via [deepMerge].
Map<String, dynamic> defaultDeduplicator(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) {
  final versionA = a['version'];
  final versionB = b['version'];
  if ((versionA != null || versionB != null) && (versionA != versionB)) {
    return ((versionA ?? 0) > (versionB ?? 0)) ? a : b;
  }
  return deepMerge(a, b);
}

/// Checks if [tags] contains any "interesting" keys that are not in
/// [uninterestingTags] or [ignoreTags].
///
/// In [ignoreTags], a value of `true` means all values for that key are
/// ignored. A string value means only that specific value is ignored.
bool hasInterestingTags(
  Map<String, String>? tags,
  Map<String, dynamic> uninterestingTags,
  Map<String, dynamic>? ignoreTags,
) {
  if (tags == null || tags.isEmpty) return false;
  ignoreTags ??= {};
  for (final key in tags.keys) {
    if (uninterestingTags[key] == true ||
        ignoreTags[key] == true ||
        ignoreTags[key] == tags[key]) {
      continue;
    }
    return true;
  }
  return false;
}

/// Builds meta information from an OSM element.
Map<String, dynamic> buildMetaInformation({
  int? version,
  String? timestamp,
  int? changeset,
  String? user,
  int? uid,
}) {
  return {
    'timestamp': ?timestamp,
    'version': ?version,
    'changeset': ?changeset,
    'user': ?user,
    'uid': ?uid,
  };
}
