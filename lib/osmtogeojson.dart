/// Converts OpenStreetMap data to GeoJSON.
///
/// Converts OpenStreetMap data (OSM XML or [Overpass API][overpass] JSON) to
/// [GeoJSON FeatureCollections][geojson]. A pure Dart port of the
/// [`osmtogeojson`][npm] npm library.
///
/// ## Usage
///
/// ```dart
/// import 'package:osmtogeojson/osmtogeojson.dart';
///
/// // From Overpass API JSON:
/// final json = {
///   'elements': [
///     {'type': 'node', 'id': 1, 'lat': 48.2, 'lon': 16.3,
///      'tags': {'name': 'Vienna'}},
///   ],
/// };
/// final collection = osmToGeoJson(json);
///
/// // From OSM XML:
/// const xml = "<osm><node id='1' lat='48.2' lon='16.3' /></osm>";
/// final collection = osmToGeoJson(xml);
///
/// // Stream individual features without the FeatureCollection envelope:
/// for (final feature in osmToGeoJsonFeatures(json)) {
///   print(feature['id']); // "node/1"
/// }
/// ```
///
/// ## Options
///
/// [osmToGeoJson] and [osmToGeoJsonFeatures] accept an optional
/// [OsmToGeoJsonOptions] object with the following fields:
///
/// - **`flatProperties`** (default `true`) — if `true`, each feature's
///   `properties` will be a simple key-value list instead of a structured
///   object with separate `tags` and `meta`.
/// - **`uninterestingTags`** (default `{source, source_ref, …}`) — tag keys
///   to ignore when deciding whether a node should be a standalone POI.
/// - **`polygonFeatures`** — tag patterns that cause a closed way to be
///   treated as a Polygon rather than LineString. Defaults to a built-in set
///   based on OSM conventions.
/// - **`deduplicator`** — custom function `(a, b) => merged` for resolving
///   duplicate OSM elements. Defaults to preferring the higher version.
/// - **`verbose`** (default `false`) — when `true`, prints warnings for
///   ignored or tainted features.
///
/// ## Supported features
///
/// - **Input:** OSM XML, Overpass API JSON (including `out center`,
///   `out bounds`, and `out geom`).
/// - **Geometry:** Point, LineString, Polygon, MultiPolygon, MultiLineString.
/// - **Relations:** multipolygon (simple and complex), boundary, route,
///   waterway. Generic relations are tracked in each member's `relations`
///   property.
/// - **Deduplication:** duplicate elements are merged by default (higher
///   version wins, properties are combined).
/// - **Tainting:** features with missing geometry data are emitted with
///   `tainted: true` rather than being dropped.
///
/// [npm]: https://github.com/tyrasd/osmtogeojson
/// [overpass]: https://wiki.openstreetmap.org/wiki/Overpass_API
/// [geojson]: https://geojson.org/
library;

import 'src/converter.dart';
import 'src/geojson_rewind.dart';
import 'src/models.dart';
import 'src/options.dart';
import 'src/osm_parser.dart';

export 'src/options.dart' show OsmToGeoJsonOptions;

/// Converts OSM data to a GeoJSON FeatureCollection.
///
/// [data] may be:
/// - A [String] of OSM XML (e.g. from the Overpass API's XML output).
/// - A [Map] of Overpass JSON (with an `"elements"` list).
///
/// Returns a GeoJSON FeatureCollection `Map<String, dynamic>` with polygon
/// winding corrected to the right-hand rule.
///
/// ```dart
/// final geojson = osmToGeoJson(json, options: OsmToGeoJsonOptions(flatProperties: false));
/// print(geojson['type']); // "FeatureCollection"
/// ```
Map<String, dynamic> osmToGeoJson(
  dynamic data, {
  OsmToGeoJsonOptions? options,
}) {
  final features = _parseAndConvert(data, options);
  final geojson = <String, dynamic>{
    'type': 'FeatureCollection',
    'features': features,
  };
  rewind(geojson);
  return geojson;
}

/// Converts OSM data to an iterable of GeoJSON Feature maps.
///
/// Like [osmToGeoJson] but produces individual features without a
/// FeatureCollection envelope. Useful for streaming or per-feature
/// processing.
///
/// [data] may be:
/// - A [String] of OSM XML.
/// - A [Map] of Overpass JSON.
///
/// ```dart
/// for (final feature in osmToGeoJsonFeatures(json)) {
///   print('${feature['id']}: ${feature['geometry']['type']}');
/// }
/// ```
Iterable<Map<String, dynamic>> osmToGeoJsonFeatures(
  dynamic data, {
  OsmToGeoJsonOptions? options,
}) {
  return _parseAndConvert(data, options);
}

/// Shared pipeline: parse input, run converter, return feature list.
List<Map<String, dynamic>> _parseAndConvert(
  dynamic data,
  OsmToGeoJsonOptions? options,
) {
  options ??= const OsmToGeoJsonOptions();

  List<OsmNode> nodes;
  List<OsmWay> ways;
  List<OsmRelation> rels;

  if (data is String) {
    final result = parseOsmXml(data, options.verbose);
    nodes = result.nodes;
    ways = result.ways;
    rels = result.rels;
  } else if (data is Map<String, dynamic>) {
    final result = parseOsmJson(data, options.verbose);
    nodes = result.nodes;
    ways = result.ways;
    rels = result.rels;
  } else {
    throw ArgumentError(
      'Unsupported input format. Expected a String (OSM XML) or Map '
      '(Overpass JSON).',
    );
  }

  return convert2geoJSON(nodes, ways, rels, options);
}
