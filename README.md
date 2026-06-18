# osmtogeojson

Converts OpenStreetMap data (OSM XML or [Overpass API][overpass] JSON) to
[GeoJSON][geojson] FeatureCollections. A pure Dart port of the
[`osmtogeojson`][npm] npm library.

## Installation

```bash
dart pub add osmtogeojson
```

## Usage

```dart
import 'package:osmtogeojson/osmtogeojson.dart';

// From an Overpass API JSON response:
final json = {
  'elements': [
    {'type': 'node', 'id': 1, 'lat': 48.2082, 'lon': 16.3738,
     'tags': {'name': 'Vienna'}},
  ],
};

// Full FeatureCollection:
final collection = osmToGeoJson(json);
print(collection['type']); // "FeatureCollection"

// Or iterate features individually:
for (final feature in osmToGeoJsonFeatures(json)) {
  print(feature['id']);         // "node/1"
  print(feature['geometry']);   // {type: Point, coordinates: [16.3738, 48.2082]}
  print(feature['properties']); // {id: "node/1", name: "Vienna"}
}
```

OSM XML input is auto-detected — pass a `String` instead of a `Map`:

```dart
const xml = '''
  <osm>
    <node id="1" lat="48.2082" lon="16.3738">
      <tag k="name" v="Vienna" />
    </node>
  </osm>
''';
final collection = osmToGeoJson(xml);
```

## Options

The optional `OsmToGeoJsonOptions` object supports:

- **`flatProperties`** (default `true`) — if `true`, each feature's
  `properties` will be a simple key-value list instead of a structured
  object with separate `tags` and `meta`.
- **`uninterestingTags`** (default `{source, source_ref, …}`) — tag keys
  to ignore when deciding whether a node should be a standalone POI.
- **`polygonFeatures`** — tag patterns that cause a closed way to be treated
  as a Polygon rather than LineString. Defaults to a built-in set based on
  OSM conventions.
- **`deduplicator`** — custom function `(a, b) => merged` for resolving
  duplicate OSM elements. Defaults to preferring the higher version.
- **`verbose`** (default `false`) — when `true`, prints warnings for ignored
  or tainted features.

## Supported features

- **All major OSM geometries** — Point, LineString, Polygon, MultiPolygon,
  MultiLineString.
- **Relations** — multipolygon (simple & complex), boundary, route, waterway.
- **Overpass output modes** — `out center`, `out bounds`, `out geom`.
- **Deduplication** — duplicate elements merged; custom deduplicator supported.
- **Tainting** — incomplete features emitted with `tainted: true` instead of
  being silently dropped.
- **Polygon winding** — corrected to GeoJSON right-hand rule.

## Related

- Original JS library: <https://github.com/tyrasd/osmtogeojson>
- Overpass API: <https://wiki.openstreetmap.org/wiki/Overpass_API>
- GeoJSON spec: <https://geojson.org/>

[npm]: https://github.com/tyrasd/osmtogeojson
[overpass]: https://wiki.openstreetmap.org/wiki/Overpass_API
[geojson]: https://geojson.org/
