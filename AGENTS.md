# AGENTS.md

## Overview

Pure Dart port of the [`osmtogeojson`](https://github.com/tyrasd/osmtogeojson) npm library. Converts OSM data (XML or Overpass JSON) to GeoJSON FeatureCollections.

## Building & testing

```bash
dart pub get
dart analyze
dart test
```

## Editing guidelines
* Do not change the public API unless instructed to do so.
* Always format the code with `dart format .` when you're done.

## Architecture

```
lib/
  osmtogeojson.dart          # Public API: osmToGeoJson(), osmToGeoJsonFeatures()
  src/
    models.dart              # OsmNode, OsmWay, OsmRelation, OsmMember, OsmToGeoJsonOptions
    osm_parser.dart          # parseOsmJson(), parseOsmXml() — input format detection + parsing
    converter.dart           # convert2geoJSON() — main pipeline: indexing, dedup, POI detection,
                             #   relation resolution (route → MultiLineString, multipolygon →
                             #   Polygon/MultiPolygon), way typing (LineString vs Polygon),
                             #   flatProperties, feature assembly
    multipolygon_helper.dart # join(), pointInPolygon(), constructMultipolygon() — way segment
                             #   assembly, ring sorting, inner/outer assignment
    polygon_features.dart    # Polygon-feature tag detection rules (inlined from osm-polygon-features)
    geojson_rewind.dart      # rewind() — polygon winding correction (shoelace formula)
    utils.dart               # deepMerge(), hasInterestingTags(), buildMetaInformation()
```

## Public API

```dart
import 'package:osmtogeojson/osmtogeojson.dart';

// Returns a full GeoJSON FeatureCollection Map
Map<String, dynamic> osmToGeoJson(dynamic data, {OsmToGeoJsonOptions? options});

// Returns an iterable of individual Feature Maps (no envelope)
Iterable<Map<String, dynamic>> osmToGeoJsonFeatures(dynamic data, {OsmToGeoJsonOptions? options});
```

`data` is either a `String` (OSM XML) or `Map<String, dynamic>` (Overpass JSON with an `"elements"` list).

## Conversion pipeline

1. **Parse** — `parseOsmXml()` or `parseOsmJson()` produces flat lists of `OsmNode`, `OsmWay`, `OsmRelation`. Geometry mode helpers handle Overpass `center`, `bounds`, and `full` (inline geometry) modes.
2. **Index + deduplicate** — elements indexed by ID. Duplicates (same ID) are resolved via the `deduplicator` option (default: higher version wins, otherwise merge).
3. **POI detection** — nodes with "interesting" tags (not in `uninterestingTags`) or relation membership become Point features.
4. **Way resolution** — node refs resolved against the node index.
5. **Relation mapping** — `relsMap` tracks each element's relation memberships.
6. **Feature emission** — POIs → Points. Relations: `type=route|waterway` → LineString/MultiLineString (via way segment joining); `type=multipolygon|boundary` → Polygon/MultiPolygon (simple if 1 outer + no interesting relation tags, complex otherwise). Standalone ways → LineString (default) or Polygon (if closed + tags match polygon-feature rules or `isBoundsPlaceholder`).
7. **Assembly** — polygons, then lines, then points. `flatProperties` merges meta + tags + id if enabled.

## Key design choices

- **IDs are strings internally.** The original interleaves numeric IDs and `_fullGeom`/`_anonymous@lat/lon` prefixed strings. Storing as `String` avoids type confusion. Output IDs are normalized back to `int` when numeric.
- **Zero runtime dependencies beyond `xml`.** lodash functions replaced with native Dart; geojson-rewind and osm-polygon-features data inlined.
- **Simple vs complex multipolygon.** Simple = exactly 1 outer way + relation has no interesting tags beyond `type=multipolygon`. The outer way is promoted to a Polygon with holes; the relation is invisible. Complex = the relation itself becomes the feature with the relation's tags.
- **Tainting.** Features missing any referenced geometry get `tainted: true` in properties rather than being silently dropped.
- **Polygon detection.** Checks `area=no` first (never polygon), then matches tags against the `polygonFeatures` rules. `isBoundsPlaceholder` is always a polygon.
