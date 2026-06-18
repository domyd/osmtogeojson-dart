/// Options for the osmtogeojson conversion.
class OsmToGeoJsonOptions {
  /// If `true`, each feature's `properties` will be a simple key-value list
  /// instead of a structured object with separate `tags` and `meta`.
  final bool flatProperties;

  /// Tag keys to ignore when deciding whether a node should be a standalone
  /// POI. Defaults to a built-in set (`source`, `source_ref`, `created_by`,
  /// etc.).
  final Map<String, dynamic>? uninterestingTags;

  /// Tag patterns that cause a closed way to be treated as a Polygon rather
  /// than LineString. Defaults to a built-in set based on OSM conventions
  /// (e.g. `building`, `landuse`, `amenity`).
  final Map<String, dynamic>? polygonFeatures;

  /// Custom function `(a, b) => merged` for resolving duplicate OSM elements.
  /// Defaults to preferring the higher version and merging properties.
  final Map<String, dynamic> Function(
    Map<String, dynamic>,
    Map<String, dynamic>,
  )?
  deduplicator;

  /// When `true`, prints warnings for ignored or tainted features.
  final bool verbose;

  /// Constructs a new options object.
  const OsmToGeoJsonOptions({
    this.flatProperties = true,
    this.uninterestingTags,
    this.polygonFeatures,
    this.deduplicator,
    this.verbose = false,
  });
}
