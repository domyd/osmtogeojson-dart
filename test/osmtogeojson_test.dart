import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:osmtogeojson/osmtogeojson.dart';
import 'package:test/scaffolding.dart';

void main() {
  group('osm (xml)', () {
    test('blank osm', () {
      const xml = '<osm></osm>';
      final result = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      check(result).deepEquals({'type': 'FeatureCollection', 'features': []});
    });

    test('node', () {
      const xml = "<osm><node id='1' lat='1.234' lon='4.321' /></osm>";
      final result = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      check(result).deepEquals({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'id': 'node/1',
            'properties': {
              'type': 'node',
              'id': 1,
              'tags': {},
              'relations': [],
              'meta': {},
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [4.321, 1.234],
            },
          },
        ],
      });
    });

    test('way', () {
      const xml =
          "<osm><way id='1'><nd ref='2' /><nd ref='3' /><nd ref='4' /></way>"
          "<node id='2' lat='0.0' lon='1.0' /><node id='3' lat='0.0' lon='1.1' />"
          "<node id='4' lat='0.1' lon='1.2' /></osm>";
      final result = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      check(result).deepEquals({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'id': 'way/1',
            'properties': {
              'type': 'way',
              'id': 1,
              'tags': {},
              'relations': [],
              'meta': {},
            },
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                [1.0, 0.0],
                [1.1, 0.0],
                [1.2, 0.1],
              ],
            },
          },
        ],
      });
    });

    test('relation', () {
      const xml =
          "<osm>"
          "<relation id='1'><tag k='type' v='multipolygon' />"
          "<member type='way' ref='2' role='outer' />"
          "<member type='way' ref='3' role='inner' /></relation>"
          "<way id='2'><tag k='area' v='yes' />"
          "<nd ref='4' /><nd ref='5' /><nd ref='6' /><nd ref='7' /><nd ref='4' /></way>"
          "<way id='3'><nd ref='8' /><nd ref='9' /><nd ref='10' /><nd ref='8' /></way>"
          "<node id='4' lat='-1.0' lon='-1.0' /><node id='5' lat='-1.0' lon='1.0' />"
          "<node id='6' lat='1.0' lon='1.0' /><node id='7' lat='1.0' lon='-1.0' />"
          "<node id='8' lat='-0.5' lon='0.0' /><node id='9' lat='0.5' lon='0.0' />"
          "<node id='10' lat='0.0' lon='0.5' /></osm>";
      final geojson = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['id']).equals('way/2');
      check(f['properties']['type']).equals('way');
      check(f['properties']['id']).equals(2);
      check(f['properties']['tags'] as Map).deepEquals({'area': 'yes'});
      check(f['properties']['meta'] as Map).deepEquals({});
      // Relations
      final rels = f['properties']['relations'] as List<dynamic>;
      check(rels).length.equals(1);
      check((rels[0] as Map)['rel']).equals(1);
      check((rels[0] as Map)['role']).equals('outer');
      check(
        (rels[0] as Map)['reltags'] as Map,
      ).deepEquals({'type': 'multipolygon'});
      // Geometry
      check(f['geometry']['type']).equals('Polygon');
      final coords = f['geometry']['coordinates'] as List<dynamic>;
      check(coords).length.equals(2);
      final outer = coords[0] as List<dynamic>;
      final inner = coords[1] as List<dynamic>;
      check(outer).length.equals(5);
      check(inner).length.equals(4);
      // Outer ring: SW, SE, NE, NW, SW (clockwise; rewind keeps it)
      check((outer[0] as List<num>)).deepEquals([-1.0, -1.0]);
      check((outer[2] as List<num>)).deepEquals([1.0, 1.0]);
      check((outer[4] as List<num>)).deepEquals([-1.0, -1.0]);
      // Inner ring
      check((inner[0] as List<num>)).deepEquals([0.0, -0.5]);
      check((inner[2] as List<num>)).deepEquals([0.5, 0.0]);
    });
  });

  group('osm (json)', () {
    test('node', () {
      final json = {
        'elements': [
          {'type': 'node', 'id': 1, 'lat': 1.234, 'lon': 4.321},
        ],
      };
      final result = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      check(result).deepEquals({
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'id': 'node/1',
            'properties': {
              'type': 'node',
              'id': 1,
              'tags': {},
              'relations': [],
              'meta': {},
            },
            'geometry': {
              'type': 'Point',
              'coordinates': [4.321, 1.234],
            },
          },
        ],
      });
    });

    test('way', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3, 4],
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 1.1},
          {'type': 'node', 'id': 4, 'lat': 0.1, 'lon': 1.2},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('LineString');
    });

    test('polygon', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3, 4, 5, 2],
            'tags': {'area': 'yes'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 4, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('Polygon');
    });

    test('simple multipolygon', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
            'tags': {'area': 'yes'},
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [8, 9, 10, 8],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 2.0},
          {'type': 'node', 'id': 6, 'lat': 2.0, 'lon': 2.0},
          {'type': 'node', 'id': 7, 'lat': 2.0, 'lon': 0.0},
          {'type': 'node', 'id': 8, 'lat': 0.5, 'lon': 0.5},
          {'type': 'node', 'id': 9, 'lat': 0.5, 'lon': 1.5},
          {'type': 'node', 'id': 10, 'lat': 1.5, 'lon': 1.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['id']).equals('way/2');
      check(f['geometry']['type']).equals('Polygon');
    });

    test('complex multipolygon', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon', 'landuse': 'forest'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 4],
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [7, 8, 9, 7],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 7, 'lat': 2.0, 'lon': 2.0},
          {'type': 'node', 'id': 8, 'lat': 2.0, 'lon': 3.0},
          {'type': 'node', 'id': 9, 'lat': 3.0, 'lon': 3.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['id']).equals('relation/1');
      check(f['geometry']['type']).equals('MultiPolygon');
    });

    test('multipolygon', () {
      // valid multipolygon with 2 outers + 2 inners
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon', 'building': 'yes'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
              {'type': 'way', 'ref': 4, 'role': 'inner'},
              {'type': 'way', 'ref': 5, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
            'tags': {'building': 'yes'},
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [8, 9, 10, 8],
            'tags': {'area': 'yes'},
          },
          {
            'type': 'way',
            'id': 4,
            'nodes': [11, 12, 13, 11],
            'tags': {'barrier': 'fence'},
          },
          {
            'type': 'way',
            'id': 5,
            'nodes': [14, 15, 16, 14],
            'tags': {'building': 'yes', 'area': 'yes'},
          },
          {'type': 'node', 'id': 4, 'lat': -1.0, 'lon': -1.0},
          {'type': 'node', 'id': 5, 'lat': -1.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 7, 'lat': 1.0, 'lon': -1.0},
          {'type': 'node', 'id': 8, 'lat': -0.5, 'lon': 0.0},
          {'type': 'node', 'id': 9, 'lat': 0.5, 'lon': 0.0},
          {'type': 'node', 'id': 10, 'lat': 0.0, 'lon': 0.5},
          {'type': 'node', 'id': 11, 'lat': 0.1, 'lon': -0.1},
          {'type': 'node', 'id': 12, 'lat': -0.1, 'lon': -0.1},
          {'type': 'node', 'id': 13, 'lat': 0.0, 'lon': -0.2},
          {'type': 'node', 'id': 14, 'lat': 0.1, 'lon': -1.1},
          {'type': 'node', 'id': 15, 'lat': -0.1, 'lon': -1.1},
          {'type': 'node', 'id': 16, 'lat': 0.0, 'lon': -1.2},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(4);

      // Feature 0: relation/1 → MultiPolygon
      final f0 = features[0] as Map<String, dynamic>;
      check(f0['id']).equals('relation/1');
      check(f0['properties']['type']).equals('relation');
      check(f0['properties']['id']).equals(1);
      check(
        f0['properties']['tags'] as Map,
      ).deepEquals({'type': 'multipolygon', 'building': 'yes'});
      check(f0['geometry']['type']).equals('MultiPolygon');

      // Feature 1: way/3 → Polygon (inner way with area=yes)
      final f1 = features[1] as Map<String, dynamic>;
      check(f1['id']).equals('way/3');
      check(f1['properties']['type']).equals('way');
      check(f1['properties']['tags'] as Map).deepEquals({'area': 'yes'});
      check(f1['geometry']['type']).equals('Polygon');
      final f1Rels = f1['properties']['relations'] as List<dynamic>;
      check(f1Rels).length.equals(1);
      check((f1Rels[0] as Map)['rel']).equals(1);
      check((f1Rels[0] as Map)['role']).equals('inner');

      // Feature 2: way/5 → Polygon (outer way with building=yes, area=yes)
      final f2 = features[2] as Map<String, dynamic>;
      check(f2['id']).equals('way/5');
      check(
        f2['properties']['tags'] as Map,
      ).deepEquals({'building': 'yes', 'area': 'yes'});
      check(f2['geometry']['type']).equals('Polygon');
      final f2Rels = f2['properties']['relations'] as List<dynamic>;
      check(f2Rels).length.equals(1);
      check((f2Rels[0] as Map)['rel']).equals(1);
      check((f2Rels[0] as Map)['role']).equals('outer');

      // Feature 3: way/4 → LineString (barrier=fence is not a polygon feature)
      final f3 = features[3] as Map<String, dynamic>;
      check(f3['id']).equals('way/4');
      check(f3['properties']['tags'] as Map).deepEquals({'barrier': 'fence'});
      check(f3['geometry']['type']).equals('LineString');
      final f3Rels = f3['properties']['relations'] as List<dynamic>;
      check(f3Rels).length.equals(1);
      check((f3Rels[0] as Map)['rel']).equals(1);
      check((f3Rels[0] as Map)['role']).equals('inner');

      // handle role-less members as outer ways
      final elements = json['elements'] as List<dynamic>;
      final relMembers =
          (elements[0] as Map<String, dynamic>)['members'] as List<dynamic>;
      (relMembers[3] as Map<String, dynamic>)['role'] = '';
      final geo2 = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f2b =
          (geo2['features'] as List<dynamic>)[2] as Map<String, dynamic>;
      final f2bRels = f2b['properties']['relations'] as List<dynamic>;
      if (f2bRels.isNotEmpty) {
        check((f2bRels[0] as Map)['role']).equals('');
      }
    });

    test('route relation', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'route', 'route': 'hiking'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'forward'},
              {'type': 'way', 'ref': 3, 'role': 'forward'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5],
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [5, 6],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 0.0, 'lon': 2.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['id']).equals('relation/1');
      check(f['properties']['type']).equals('relation');
      check(f['properties']['id']).equals(1);
      check(
        f['properties']['tags'] as Map,
      ).deepEquals({'type': 'route', 'route': 'hiking'});
      // Two connected forward ways join into one LineString
      check(f['geometry']['type']).equals('LineString');
      check(f['geometry']['coordinates'] as List).deepEquals([
        [0.0, 0.0],
        [1.0, 0.0],
        [2.0, 0.0],
      ]);
    });

    test('tags: nodes with interesting tags appear as POIs', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'tags': {'amenity': 'cafe'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 1.0},
          {
            'type': 'way',
            'id': 3,
            'nodes': [1, 2],
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(2);
    });

    test('tags: ways and nodes / pois', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3, 4],
            'tags': {'foo': 'bar'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 1.0},
          {
            'type': 'node',
            'id': 3,
            'lat': 0.0,
            'lon': 1.1,
            'tags': {'asd': 'fasd'},
          },
          {
            'type': 'node',
            'id': 4,
            'lat': 0.1,
            'lon': 1.2,
            'tags': {'created_by': 'me'},
          },
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 0.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(3);
      check((features[0] as Map)['id']).equals('way/1');
      check((features[1] as Map)['id']).equals('node/3');
      check((features[2] as Map)['id']).equals('node/5');
    });

    test('meta data is preserved', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'timestamp': '2020-01-01T00:00:00Z',
            'version': 3,
            'changeset': 12345,
            'user': 'testuser',
            'uid': 999,
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f =
          (geojson['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      final meta = f['properties']['meta'] as Map<String, dynamic>;
      check(meta['timestamp']).equals('2020-01-01T00:00:00Z');
      check(meta['version']).equals(3);
    });

    test('meta data is preserved on ways and relations', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 1.234,
            'lon': 4.321,
            'tags': {'amenity': 'yes'},
            'user': 'johndoe',
          },
          {
            'type': 'way',
            'id': 1,
            'tags': {'highway': 'road'},
            'user': 'johndoe',
            'nodes': [1, 1, 1, 1],
          },
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'user': 'johndoe',
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'outer'},
              {'type': 'way', 'ref': 1, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'tags': {'highway': 'road'},
            'user': 'johndoe',
            'nodes': [1, 1, 1, 1],
          },
          {
            'type': 'relation',
            'id': 2,
            'tags': {'type': 'multipolygon'},
            'user': 'johndoe',
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(4);
      for (final f in features) {
        final meta = (f as Map<String, dynamic>)['properties']['meta'] as Map;
        check(meta).containsKey('user');
        check(meta['user']).equals('johndoe');
      }
    });
  });

  group('defaults', () {
    test('interesting objects: tagged node appears, created_by excluded', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'tags': {'name': 'Test'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 1.0},
          {
            'type': 'node',
            'id': 3,
            'lat': 0.0,
            'lon': 2.0,
            'tags': {'created_by': 'JOSM'},
          },
          {
            'type': 'way',
            'id': 4,
            'nodes': [1, 2, 3],
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(2);
    });

    test('interesting objects', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2],
          },
          {
            'type': 'node',
            'id': 1,
            'tags': {'created_by': 'foo'},
            'lat': 1.0,
            'lon': 0.0,
          },
          {
            'type': 'node',
            'id': 2,
            'tags': {'interesting': 'yes'},
            'lat': 2.0,
            'lon': 0.0,
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(2);
      check((features[0] as Map)['geometry']['type']).equals('LineString');
      check((features[1] as Map)['geometry']['type']).equals('Point');
      check((features[1] as Map)['properties']['id']).equals(2);
    });

    test('interesting objects: relation members', () {
      const xml =
          '<osm version="0.6">'
          '<relation id="4294968148">'
          '<member type="way" ref="4295032195" role="line"/>'
          '<member type="node" ref="4295668179" role="point"/>'
          '<member type="node" ref="4295668178" role=""/>'
          '<member type="way" ref="4295032194" role=""/>'
          '<member type="way" ref="4295032193" role=""/>'
          '<member type="node" ref="4295668174" role="foo"/>'
          '<member type="node" ref="4295668175" role="bar"/>'
          '<tag k="type" v="fancy"/>'
          '</relation>'
          '<way id="4295032195">'
          '<nd ref="4295668174"/><nd ref="4295668172"/>'
          '<nd ref="4295668171"/><nd ref="4295668170"/>'
          '<nd ref="4295668173"/><nd ref="4295668175"/>'
          '<tag k="highway" v="residential"/>'
          '</way>'
          '<way id="4295032194">'
          '<nd ref="4295668177"/><nd ref="4295668178"/>'
          '<nd ref="4295668180"/>'
          '<tag k="highway" v="service"/>'
          '</way>'
          '<way id="4295032193">'
          '<nd ref="4295668181"/><nd ref="4295668178"/>'
          '<nd ref="4295668176"/>'
          '<tag k="highway" v="service"/>'
          '</way>'
          '<node id="4295668172" lat="46.4910906" lon="11.2735763">'
          '<tag k="highway" v="crossing"/>'
          '</node>'
          '<node id="4295668173" lat="46.4911004" lon="11.2759498">'
          '<tag k="created_by" v="foo"/>'
          '</node>'
          '<node id="4295668170" lat="46.4909732" lon="11.2753813"/>'
          '<node id="4295668171" lat="46.4909781" lon="11.2743295"/>'
          '<node id="4295668174" lat="46.4914820" lon="11.2731001"/>'
          '<node id="4295668175" lat="46.4915603" lon="11.2765254"/>'
          '<node id="4295668176" lat="46.4919468" lon="11.2756726"/>'
          '<node id="4295668177" lat="46.4919664" lon="11.2753031"/>'
          '<node id="4295668178" lat="46.4921083" lon="11.2755021"/>'
          '<node id="4295668179" lat="46.4921327" lon="11.2742229"/>'
          '<node id="4295668180" lat="46.4922893" lon="11.2757152"/>'
          '<node id="4295668181" lat="46.4923235" lon="11.2752747"/>'
          '</osm>';
      final geojson = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(8);
    });

    test('polygon detection: area=yes vs area=no', () {
      final polygonJson = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [3, 4, 5, 6, 3],
            'tags': {'area': 'yes'},
          },
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final pResult = osmToGeoJson(polygonJson);
      final pF =
          (pResult['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(pF['geometry']['type']).equals('Polygon');

      final lineJson = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [3, 4, 5, 6, 3],
            'tags': {'area': 'no'},
          },
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final lResult = osmToGeoJson(lineJson);
      final lF =
          (lResult['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(lF['geometry']['type']).equals('LineString');
    });
  });

  group('options', () {
    test('flatProperties: false keeps nested structure', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'tags': {'name': 'Test'},
            'timestamp': '2020-01-01T00:00:00Z',
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final p =
          (geojson['features'] as List<dynamic>)[0]['properties']
              as Map<String, dynamic>;
      check(p).containsKey('type');
      check(p).containsKey('tags');
      check(p).containsKey('meta');
    });

    test('flatProperties: true (default) merges properties', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'tags': {'name': 'Test'},
          },
        ],
      };
      final geojson = osmToGeoJson(json);
      final p =
          (geojson['features'] as List<dynamic>)[0]['properties']
              as Map<String, dynamic>;
      check(p['name']).equals('Test');
      check(p['id']).equals('node/1');
    });
  });

  group('tainted data', () {
    test('tainted way with some valid nodes', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3, 4],
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 0.0},
          // Node 3 is missing
          {'type': 'node', 'id': 4, 'lat': 2.0, 'lon': 2.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['properties']['tainted']).equals(true);
    });

    test('tainted geometries', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 10,
            'nodes': [2, 3, 5],
          },
          {
            'type': 'way',
            'id': 11,
            'nodes': [2, 3, 4, 5, 2],
            'tags': {'area': 'yes'},
          },
          {
            'type': 'way',
            'id': 12,
            'nodes': [2, 3, 4, 2],
          },
          {
            'type': 'relation',
            'id': 100,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 12, 'role': 'outer'},
              {'type': 'way', 'ref': 13, 'role': 'inner'},
            ],
          },
          {'type': 'node', 'id': 2, 'lat': 1.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 4, 'lat': 1.0, 'lon': 1.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(3);
      // Feature 0: way/12 — simple multipolygon, tainted (missing inner way)
      final f0 = features[0] as Map<String, dynamic>;
      check(f0['id']).equals('way/12');
      check(f0['geometry']['type']).equals('Polygon');
      check(f0['properties']['tainted']).equals(true);
      // Feature 1: way/11 — closed polygon, tainted (node 4 missing)
      final f1 = features[1] as Map<String, dynamic>;
      check(f1['id']).equals('way/11');
      check(f1['properties']['tags'] as Map).deepEquals({'area': 'yes'});
      check(f1['properties']['tainted']).equals(true);
      // Feature 2: way/10 — LineString, tainted (node 5 missing)
      final f2 = features[2] as Map<String, dynamic>;
      check(f2['id']).equals('way/10');
      check(f2['geometry']['type']).equals('LineString');
      check(f2['properties']['tainted']).equals(true);
    });

    test('ids_only elements produce no features', () {
      final json = {
        'elements': [
          {'type': 'node', 'id': 1},
          {'type': 'way', 'id': 2},
          {'type': 'relation', 'id': 3},
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });
  });

  group('other', () {
    test('input is not mutated', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 1.0,
            'lon': 2.0,
            'tags': {'name': 'Test'},
          },
        ],
      };
      final original = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 1.0,
            'lon': 2.0,
            'tags': {'name': 'Test'},
          },
        ],
      };
      osmToGeoJson(json);
      check(json).deepEquals(original);
    });
  });

  group('overpass geometry types', () {
    test('center geometry (json)', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'center': {'lat': 1.0, 'lon': 2.0},
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('Point');
      check(f['geometry']['coordinates'] as List).deepEquals([2.0, 1.0]);
      check(f['properties']['geometry']).equals('center');
    });

    test('bounds geometry (json)', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'bounds': {
              'minlat': 0.0,
              'minlon': 0.0,
              'maxlat': 1.0,
              'maxlon': 1.0,
            },
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('Polygon');
      check(f['properties']['geometry']).equals('bounds');
    });

    test('full geometry way (json)', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'geometry': [
              {'lat': 0.0, 'lon': 0.0},
              {'lat': 0.0, 'lon': 1.0},
              {'lat': 1.0, 'lon': 1.0},
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('LineString');
      check((f['geometry']['coordinates'] as List).length).equals(3);
    });

    test('full geometry (json)', () {
      // Way with both bounds AND full geometry (geometry wins)
      final json1 = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'bounds': {'minlat': 0, 'minlon': 0, 'maxlat': 1, 'maxlon': 1},
            'nodes': [1, 2, 3, 1],
            'geometry': [
              {'lat': 0, 'lon': 0},
              {'lat': 0, 'lon': 1},
              {'lat': 1, 'lon': 1},
              {'lat': 0, 'lon': 0},
            ],
            'tags': {'area': 'yes'},
          },
        ],
      };
      final geo1 = osmToGeoJson(
        json1,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f1 = (geo1['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f1['id']).equals('way/1');
      check(f1['geometry']['type']).equals('Polygon');
      check(
        (f1['geometry']['coordinates'] as List)[0] as List,
      ).length.equals(4);

      // Way with ref-less geometry (no nodes array)
      final json2 = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'bounds': {'minlat': 0, 'minlon': 0, 'maxlat': 1, 'maxlon': 1},
            'geometry': [
              {'lat': 0, 'lon': 0},
              {'lat': 0, 'lon': 1},
              {'lat': 1, 'lon': 1},
              {'lat': 0, 'lon': 0},
            ],
            'tags': {'area': 'yes'},
          },
        ],
      };
      final geo2 = osmToGeoJson(
        json2,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f2 = (geo2['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f2['id']).equals('way/1');
      check(f2['geometry']['type']).equals('Polygon');
      check(
        (f2['geometry']['coordinates'] as List)[0] as List,
      ).length.equals(4);

      // Relation with 2 outer members in full geometry + node member
      final json3 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'boundary'},
            'bounds': {'minlat': 0, 'minlon': 0, 'maxlat': 1, 'maxlon': 1},
            'members': [
              {
                'type': 'way',
                'ref': 1,
                'role': 'outer',
                'geometry': [
                  {'lat': 0, 'lon': 0},
                  {'lat': 0, 'lon': 1},
                  {'lat': 1, 'lon': 1},
                  {'lat': 1, 'lon': 0},
                  {'lat': 0, 'lon': 0},
                ],
              },
              {
                'type': 'way',
                'ref': 2,
                'role': 'outer',
                'geometry': [
                  {'lat': 1.1, 'lon': 1.1},
                  {'lat': 1.1, 'lon': 1.2},
                  {'lat': 1.2, 'lon': 1.2},
                  {'lat': 1.1, 'lon': 1.1},
                ],
              },
              {
                'type': 'node',
                'ref': 1,
                'role': 'admin_centre',
                'lat': 0.5,
                'lon': 0.5,
              },
            ],
          },
        ],
      };
      final geo3 = osmToGeoJson(
        json3,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features3 = geo3['features'] as List<dynamic>;
      check(features3).length.equals(2);
      check((features3[0] as Map)['id']).equals('relation/1');
      check((features3[0] as Map)['geometry']['type']).equals('MultiPolygon');
      check((features3[1] as Map)['id']).equals('node/1');
    });
  });

  group('duplicate elements', () {
    test('duplicate nodes are merged', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'tags': {'name': 'A'},
          },
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'tags': {'name': 'B'},
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
    });

    test('duplicate nodes: higher version wins', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'version': 1,
            'tags': {'name': 'Old'},
          },
          {
            'type': 'node',
            'id': 1,
            'lat': 1.0,
            'lon': 1.0,
            'version': 2,
            'tags': {'name': 'New'},
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['coordinates'] as List).deepEquals([1.0, 1.0]);
      check(f['properties']['tags'] as Map).deepEquals({'name': 'New'});
      check(f['properties']['meta']['version']).equals(2);
    });
  });

  group('osmToGeoJsonFeatures', () {
    test('returns iterable of features', () {
      final json = {
        'elements': [
          {'type': 'node', 'id': 1, 'lat': 0.0, 'lon': 0.0},
        ],
      };
      final features = osmToGeoJsonFeatures(json).toList();
      check(features).length.equals(1);
      check(features[0]['id']).equals('node/1');
      check(features[0]['geometry']['type']).equals('Point');
    });

    test('includes polygon features from relations', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
            'tags': {'area': 'yes'},
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [8, 9, 10, 8],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 2.0},
          {'type': 'node', 'id': 6, 'lat': 2.0, 'lon': 2.0},
          {'type': 'node', 'id': 7, 'lat': 2.0, 'lon': 0.0},
          {'type': 'node', 'id': 8, 'lat': 0.5, 'lon': 0.5},
          {'type': 'node', 'id': 9, 'lat': 0.5, 'lon': 1.5},
          {'type': 'node', 'id': 10, 'lat': 1.5, 'lon': 1.0},
        ],
      };
      final features = osmToGeoJsonFeatures(json).toList();
      check(features).length.equals(1);
      check(features[0]['id']).equals('way/2');
      check(features[0]['geometry']['type']).equals('Polygon');
    });

    test('includes LineString features', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3],
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 1.0, 'lon': 1.0},
        ],
      };
      final features = osmToGeoJsonFeatures(json).toList();
      check(features).length.equals(1);
      check(features[0]['geometry']['type']).equals('LineString');
    });

    test('matches osmToGeoJson feature content', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 1.0,
            'lon': 2.0,
            'tags': {'name': 'Test'},
          },
        ],
      };
      final collection = osmToGeoJson(json);
      final iterable = osmToGeoJsonFeatures(json).toList();
      check(iterable).deepEquals(collection['features'] as List);
    });
  });

  group('osm (json) - edge cases', () {
    test('one-node-ways produce no features', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2],
            'tags': {'foo': 'bar'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 0.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      check(geojson['features'] as List).isEmpty();
    });

    test('invalid multipolygon: empty', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
          },
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });

    test('invalid multipolygon: missing members', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'outer'},
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });

    test('invalid multipolygon: empty members', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'outer'},
            ],
          },
          {'type': 'way', 'id': 1},
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });

    test('invalid route: empty', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'route'},
          },
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });

    test('invalid route: missing members', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'route'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'forward'},
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });

    test('invalid route: empty members', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'route'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'forward'},
            ],
          },
          {'type': 'way', 'id': 1},
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });

    test('relations and id-spaces', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2, 3],
            'tags': {'foo': 'bar'},
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [3, 1],
          },
          {'type': 'node', 'id': 1, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 2, 'lat': 2.0, 'lon': 2.0},
          {'type': 'node', 'id': 3, 'lat': 1.0, 'lon': 2.0},
          {
            'type': 'relation',
            'id': 1,
            'tags': {'foo': 'bar'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'asd'},
              {'type': 'node', 'ref': 1, 'role': 'fasd'},
              {'type': 'relation', 'ref': 2, 'role': ''},
            ],
          },
          {
            'type': 'relation',
            'id': 2,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 1, 'role': 'outer'},
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(3);

      // Feature 0: relation/2 → Polygon (complex multipolygon, relation is
      // the tag source). Its relations list shows it is a member of relation 1.
      final f0 = features[0] as Map<String, dynamic>;
      check(f0['id']).equals('relation/2');
      check(f0['properties']['type']).equals('relation');
      check(f0['properties']['id']).equals(2);
      check(
        f0['properties']['tags'] as Map,
      ).deepEquals({'type': 'multipolygon'});
      check(f0['geometry']['type']).equals('Polygon');
      final f0Rels = f0['properties']['relations'] as List<dynamic>;
      check(f0Rels).length.equals(1);
      check((f0Rels[0] as Map)['rel']).equals(1);
      check((f0Rels[0] as Map)['role']).equals('');
      check((f0Rels[0] as Map)['reltags'] as Map).deepEquals({'foo': 'bar'});

      // Feature 1: way/1 → LineString (not closed, so not a polygon).
      // Its relations list shows it is a member of both relation 1 and 2.
      final f1 = features[1] as Map<String, dynamic>;
      check(f1['id']).equals('way/1');
      check(f1['properties']['type']).equals('way');
      check(f1['properties']['tags'] as Map).deepEquals({'foo': 'bar'});
      check(f1['geometry']['type']).equals('LineString');
      final f1Rels = f1['properties']['relations'] as List<dynamic>;
      check(f1Rels).length.equals(2);
      // Both relations should be tracked
      final f1Roles = f1Rels.map((r) => (r as Map)['role'] as String).toSet();
      check(f1Roles).deepEquals({'asd', 'outer'});

      // Feature 2: node/1 → Point. It is a member of relation 1.
      final f2 = features[2] as Map<String, dynamic>;
      check(f2['id']).equals('node/1');
      check(f2['properties']['type']).equals('node');
      check(f2['geometry']['type']).equals('Point');
      check(f2['geometry']['coordinates'] as List).deepEquals([1.0, 1.0]);
      final f2Rels = f2['properties']['relations'] as List<dynamic>;
      check(f2Rels).length.equals(1);
      check((f2Rels[0] as Map)['rel']).equals(1);
      check((f2Rels[0] as Map)['role']).equals('fasd');
    });

    test('overpass area elements are ignored', () {
      final json = {
        'elements': [
          {'type': 'area', 'id': 1},
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });
  });

  group('multipolygon edge cases', () {
    test('outer way tagging: both relation and outer way get features', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon', 'amenity': 'xxx'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
            'tags': {'amenity': 'yyy'},
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [8, 9, 10, 8],
          },
          {'type': 'node', 'id': 4, 'lat': -1.0, 'lon': -1.0},
          {'type': 'node', 'id': 5, 'lat': -1.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 7, 'lat': 1.0, 'lon': -1.0},
          {'type': 'node', 'id': 8, 'lat': -0.5, 'lon': 0.0},
          {'type': 'node', 'id': 9, 'lat': 0.5, 'lon': 0.0},
          {'type': 'node', 'id': 10, 'lat': 0.0, 'lon': 0.5},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(2);
      check((features[0] as Map)['id']).equals('relation/1');
      check((features[1] as Map)['id']).equals('way/2');
    });

    test('non-matching inner and outer rings: inner ring dropped', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [8, 9, 10, 8],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 0.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 7, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 8, 'lat': 3.0, 'lon': 3.0},
          {'type': 'node', 'id': 9, 'lat': 4.0, 'lon': 3.0},
          {'type': 'node', 'id': 10, 'lat': 3.0, 'lon': 4.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('Polygon');
      check((f['geometry']['coordinates'] as List).length).equals(1);
    });

    test('non-matching inner and outer rings: complex multipolygon', () {
      // Complex multipolygon (relation is tag source) with a non-existent
      // outer way and a non-matching inner ring. The inner ring is dropped.
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': -1, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 0.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 7, 'lat': 0.0, 'lon': 1.0},
          {
            'type': 'way',
            'id': 3,
            'nodes': [8, 9, 10, 8],
          },
          {'type': 'node', 'id': 8, 'lat': 3.0, 'lon': 3.0},
          {'type': 'node', 'id': 9, 'lat': 4.0, 'lon': 3.0},
          {'type': 'node', 'id': 10, 'lat': 3.0, 'lon': 4.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['id']).equals('relation/1');
      check(f['properties']['type']).equals('relation');
      check(f['geometry']['type']).equals('Polygon');
      check((f['geometry']['coordinates'] as List).length).equals(1);
    });

    test('multipolygon: non-trivial ring building', () {
      // Way order: 3 outer ways listed out of sequence still form a closed ring
      final json1 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'outer'},
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [2, 3],
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [3, 1],
          },
          {'type': 'node', 'id': 1, 'lat': 1.0, 'lon': 0.0},
          {'type': 'node', 'id': 2, 'lat': 2.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 3.0, 'lon': 0.0},
        ],
      };
      final geo1 = osmToGeoJson(
        json1,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f1 = (geo1['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f1['id']).equals('relation/1');
      check(f1['geometry']['type']).equals('Polygon');
      final ring1 = (f1['geometry']['coordinates'] as List)[0] as List;
      check(ring1).length.equals(4);

      // Way direction: 6 outers facing different directions still join
      final json2 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'outer'},
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'outer'},
              {'type': 'way', 'ref': 4, 'role': 'outer'},
              {'type': 'way', 'ref': 5, 'role': 'outer'},
              {'type': 'way', 'ref': 6, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [2, 3],
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [4, 3],
          },
          {
            'type': 'way',
            'id': 4,
            'nodes': [5, 4],
          },
          {
            'type': 'way',
            'id': 5,
            'nodes': [5, 6],
          },
          {
            'type': 'way',
            'id': 6,
            'nodes': [1, 6],
          },
          {'type': 'node', 'id': 1, 'lat': 1.0, 'lon': 0.0},
          {'type': 'node', 'id': 2, 'lat': 2.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 3.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 4.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 5.0, 'lon': 0.0},
          {'type': 'node', 'id': 6, 'lat': 6.0, 'lon': 0.0},
        ],
      };
      final geo2 = osmToGeoJson(
        json2,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f2 = (geo2['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f2['id']).equals('relation/1');
      check(f2['geometry']['type']).equals('Polygon');
      final ring2 = (f2['geometry']['coordinates'] as List)[0] as List;
      check(ring2).length.equals(7);
    });

    test('unclosed ring is automatically closed', () {
      // Single way with 4 nodes, not closed (first != last node)
      final json1 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [3, 4, 5, 6],
          },
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final geojson1 = osmToGeoJson(
        json1,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f1 =
          (geojson1['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f1['geometry']['type']).equals('Polygon');
      final coords1 = (f1['geometry']['coordinates'] as List)[0] as List;
      // The ring is auto-closed: 4 unique nodes + repeated first = 5 positions
      check(coords1).length.equals(5);
      // Per GeoJSON spec, first and last positions must be identical
      check((coords1.first as List<num>)).deepEquals([0.0, 0.0]);
      check((coords1.last as List<num>)).deepEquals([0.0, 0.0]);
      check(f1['properties']['tainted']).isNull();

      // Two ways that join but form an unclosed ring.
      // Way 1: [1,2], Way 2: [2,3,4] → join to [1,2,3,4] → auto-closed
      final json2 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'outer'},
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [2, 3, 4],
          },
          {'type': 'node', 'id': 1, 'lat': 1.0, 'lon': 0.0},
          {'type': 'node', 'id': 2, 'lat': 2.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 3.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 4.0, 'lon': 0.0},
        ],
      };
      final geojson2 = osmToGeoJson(
        json2,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features2 = geojson2['features'] as List<dynamic>;
      check(features2).length.equals(1);
      final f2 = features2[0] as Map<String, dynamic>;
      check(f2['id']).equals('relation/1');
      check(f2['geometry']['type']).equals('Polygon');
      final coords2 = (f2['geometry']['coordinates'] as List)[0] as List;
      // The ring is auto-closed: 4 joined nodes + repeated first = 5 positions
      check(coords2).length.equals(5);
      // Per GeoJSON spec, first and last positions must be identical
      check((coords2.first as List<num>)).deepEquals([0.0, 1.0]);
      check((coords2.last as List<num>)).deepEquals([0.0, 1.0]);
      // An auto-closed ring is not tainted
      check(f2['properties']['tainted']).isNull();
    });
  });

  group('options - extended', () {
    test('uninteresting tags', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'tags': {'source': 'survey', 'name': 'Test'},
          },
        ],
      };
      final r1 = osmToGeoJson(json);
      check(r1['features'] as List).length.equals(1);
      final r2 = osmToGeoJson(
        json,
        options: OsmToGeoJsonOptions(
          uninterestingTags: {'source': true, 'name': true},
        ),
      );
      check(r2['features'] as List).length.equals(1);
    });

    test('polygon detection: custom rules', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3, 4, 5, 2],
            'tags': {'highway': 'pedestrian', 'area': 'yes'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 4, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final r1 = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(
          polygonFeatures: {'highway': true, 'area': true},
        ),
      );
      final f1 = (r1['features'] as List)[0] as Map<String, dynamic>;
      check(f1['geometry']['type']).equals('Polygon');
    });
  });

  group('tainted data - extended', () {
    test('empty multipolygon produces no features', () {
      final geojson = osmToGeoJson({
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
        ],
      });
      check(geojson['features'] as List).isEmpty();
    });

    test('tainted simple multipolygon: missing outer way', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [8, 9, 10, 8],
          },
          {'type': 'node', 'id': 8, 'lat': 0.5, 'lon': 0.5},
          {'type': 'node', 'id': 9, 'lat': 0.5, 'lon': 1.5},
          {'type': 'node', 'id': 10, 'lat': 1.5, 'lon': 1.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      check(geojson['features'] as List).isEmpty();
    });

    test('tainted simple multipolygon: missing nodes', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 2.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      if (features.isNotEmpty) {
        final f = features[0] as Map<String, dynamic>;
        check(f['properties']['tainted']).equals(true);
      }
    });

    test('tainted simple multipolygon', () {
      // Missing inner way: still produces outer polygon but tainted
      final json1 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 4],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final geo1 = osmToGeoJson(
        json1,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f1 = (geo1['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f1['id']).equals('way/2');
      check(f1['properties']['tainted']).equals(true);

      // All nodes missing: produces no features
      final json2 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [3, 4, 5, 3],
          },
        ],
      };
      final geo2 = osmToGeoJson(
        json2,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      check(geo2['features'] as List).isEmpty();

      // One node missing: produces tainted polygon
      final json3 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [3, 4, 5, 6, 3],
          },
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final geo3 = osmToGeoJson(
        json3,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f3 = (geo3['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f3['id']).equals('way/2');
      check(f3['properties']['tainted']).equals(true);
    });

    test('tainted multipolygon', () {
      // Missing way in complex multipolygon
      final json1 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 4],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final geo1 = osmToGeoJson(
        json1,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f1 = (geo1['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f1['id']).equals('relation/1');
      check(f1['properties']['tainted']).equals(true);

      // Missing node in complex multipolygon
      final json2 = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
              {'type': 'way', 'ref': 3, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [4, 5, 6, 7, 4],
          },
          {
            'type': 'way',
            'id': 3,
            'nodes': [4, 5, 6, 4],
          },
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 5, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final geo2 = osmToGeoJson(
        json2,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f2 = (geo2['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f2['id']).equals('relation/1');
      check(f2['properties']['tainted']).equals(true);
    });

    test('degenerate multipolygon: no outer ring', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'inner'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [3, 4, 5, 3],
          },
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 1.0},
        ],
      };
      final geojson = osmToGeoJson(json);
      check(geojson['features'] as List).isEmpty();
    });
  });

  group('overpass geometry types - xml', () {
    test('center geometry (xml)', () {
      const xml = "<osm><way id='1'><center lat='1.0' lon='2.0' /></way></osm>";
      final geojson = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('Point');
      check(f['geometry']['coordinates'] as List).deepEquals([2.0, 1.0]);
      check(f['properties']['geometry']).equals('center');
    });

    test('bounds geometry (xml)', () {
      const xml =
          "<osm><way id='1'>"
          "<bounds minlat='0.0' minlon='0.0' maxlat='1.0' maxlon='1.0' />"
          "</way></osm>";
      final geojson = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['geometry']['type']).equals('Polygon');
      check(f['properties']['geometry']).equals('bounds');
    });

    test('full geometry (xml)', () {
      // Way with both bounds AND full geometry (geometry wins)
      const xml1 =
          "<osm><way id='1'>"
          "<bounds minlat='0' minlon='0' maxlat='1' maxlon='1'/>"
          "<nd ref='1' lat='0' lon='0' />"
          "<nd ref='2' lat='0' lon='1' />"
          "<nd ref='3' lat='1' lon='1' />"
          "<nd ref='1' lat='0' lon='0' />"
          "<tag k='area' v='yes' />"
          "</way></osm>";
      final geo1 = osmToGeoJson(
        xml1,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f1 = (geo1['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f1['id']).equals('way/1');
      check(f1['geometry']['type']).equals('Polygon');
      check(
        (f1['geometry']['coordinates'] as List)[0] as List,
      ).length.equals(4);

      // Way with ref-less nodes (anonymous IDs)
      const xml2 =
          "<osm><way id='1'>"
          "<bounds minlat='0' minlon='0' maxlat='1' maxlon='1'/>"
          "<nd lat='0' lon='0' />"
          "<nd lat='0' lon='1' />"
          "<nd lat='1' lon='1' />"
          "<nd lat='0' lon='0' />"
          "<tag k='area' v='yes' />"
          "</way></osm>";
      final geo2 = osmToGeoJson(
        xml2,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f2 = (geo2['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f2['id']).equals('way/1');
      check(f2['geometry']['type']).equals('Polygon');
      check(
        (f2['geometry']['coordinates'] as List)[0] as List,
      ).length.equals(4);

      // Relation with 2 outer members in full geometry + node member
      const xml3 =
          "<osm><relation id='1'>"
          "<bounds minlat='0' minlon='0' maxlat='1' maxlon='1'/>"
          "<member type='way' ref='1' role='outer'>"
          "<nd lat='0' lon='0' /><nd lat='0' lon='1' />"
          "<nd lat='1' lon='1' /><nd lat='1' lon='0' />"
          "<nd lat='0' lon='0' />"
          "</member>"
          "<member type='way' ref='2' role='outer'>"
          "<nd lat='1.1' lon='1.1' /><nd lat='1.1' lon='1.2' />"
          "<nd lat='1.2' lon='1.2' /><nd lat='1.1' lon='1.1' />"
          "</member>"
          "<member type='node' ref='1' role='admin_centre' lat='0.5' lon='0.5'/>"
          "<tag k='type' v='boundary' />"
          "</relation></osm>";
      final geo3 = osmToGeoJson(
        xml3,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features3 = geo3['features'] as List<dynamic>;
      check(features3).length.equals(2);
      check((features3[0] as Map)['id']).equals('relation/1');
      check((features3[0] as Map)['geometry']['type']).equals('MultiPolygon');
      check((features3[1] as Map)['id']).equals('node/1');

      // Two more complex relations sharing geometry data
      const xml4 =
          "<osm>"
          "<relation id='1'>"
          "<member type='way' ref='1' role='outer'>"
          "<nd lat='0' lon='0' /><nd lat='0' lon='1' />"
          "</member>"
          "<member type='way' ref='2' role='outer'>"
          "<nd lat='0' lon='1' /><nd lat='1' lon='1' />"
          "</member>"
          "<member type='way' ref='3' role='outer'>"
          "<nd lat='1' lon='1' /><nd lat='0' lon='0' />"
          "</member>"
          "<tag k='type' v='multipolygon' />"
          "</relation>"
          "<relation id='2'>"
          "<member type='way' ref='4' role='outer'>"
          "<nd lat='0' lon='0' /><nd lat='1' lon='0' />"
          "</member>"
          "<member type='way' ref='5' role='outer'>"
          "<nd lat='1' lon='0' /><nd lat='1' lon='1' />"
          "</member>"
          "<member type='way' ref='3' role='outer'>"
          "<nd lat='1' lon='1' /><nd lat='0' lon='0' />"
          "</member>"
          "<tag k='type' v='multipolygon' />"
          "</relation>"
          "</osm>";
      final geo4 = osmToGeoJson(
        xml4,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features4 = geo4['features'] as List<dynamic>;
      check(features4).length.equals(2);
      check((features4[0] as Map)['geometry']['type']).equals('Polygon');
      check(
        ((features4[0] as Map)['geometry']['coordinates'] as List)[0] as List,
      ).length.equals(4);
      check((features4[1] as Map)['geometry']['type']).equals('Polygon');
      check(
        ((features4[1] as Map)['geometry']['coordinates'] as List)[0] as List,
      ).length.equals(4);
    });
  });

  group('duplicate elements - extended', () {
    test('duplicate ways are merged', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3],
          },
          {
            'type': 'way',
            'id': 1,
            'nodes': [3, 4],
            'tags': {'highway': 'residential'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 2.0},
        ],
      };
      final geojson = osmToGeoJson(json);
      final features = geojson['features'] as List<dynamic>;
      check(features).length.isGreaterOrEqual(1);
      final wayFeatures = features.where((f) => (f as Map)['id'] == 'way/1');
      check(wayFeatures).length.equals(1);
    });

    test('duplicate ways: higher version wins', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3],
            'version': 1,
            'tags': {'highway': 'old'},
          },
          {
            'type': 'way',
            'id': 1,
            'nodes': [3, 4],
            'version': 2,
            'tags': {'highway': 'new'},
          },
          {'type': 'node', 'id': 2, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 2.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['properties']['meta']['version']).equals(2);
    });

    test('duplicate relations are merged', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon', 'name': 'Test'},
            'members': [
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [3, 4, 5, 6, 3],
          },
          {'type': 'node', 'id': 3, 'lat': 0.0, 'lon': 0.0},
          {'type': 'node', 'id': 4, 'lat': 0.0, 'lon': 1.0},
          {'type': 'node', 'id': 5, 'lat': 1.0, 'lon': 1.0},
          {'type': 'node', 'id': 6, 'lat': 1.0, 'lon': 0.0},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
    });

    test('custom deduplicator', () {
      final json = {
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 0.0,
            'lon': 0.0,
            'version': 2,
            'tags': {'name': 'Higher'},
          },
          {
            'type': 'node',
            'id': 1,
            'lat': 1.0,
            'lon': 1.0,
            'version': 1,
            'tags': {'name': 'Lower'},
          },
        ],
      };
      // Custom deduplicator that always takes the lower version
      final geojson = osmToGeoJson(
        json,
        options: OsmToGeoJsonOptions(
          flatProperties: false,
          deduplicator: (a, b) {
            final va = a['version'] as int? ?? 0;
            final vb = b['version'] as int? ?? 0;
            return va < vb ? a : b;
          },
        ),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['properties']['meta']['version']).equals(1);
    });

    test('relation, additional skeleton ways', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'version': 2,
            'members': [
              {'type': 'way', 'ref': 1, 'role': 'outer'},
              {'type': 'way', 'ref': 2, 'role': 'outer'},
            ],
            'tags': {'type': 'multipolygon', 'foo': 'bar'},
          },
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2, 3],
            'tags': {'asd': 'fasd'},
          },
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2, 3],
          },
          {
            'type': 'way',
            'id': 2,
            'nodes': [3, 1],
          },
          {'type': 'node', 'id': 1, 'lat': 1, 'lon': 1},
          {'type': 'node', 'id': 2, 'lat': 2, 'lon': 2},
          {'type': 'node', 'id': 3, 'lat': 2, 'lon': 1},
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(2);
      check((features[0] as Map)['id']).equals('relation/1');
      check((features[1] as Map)['id']).equals('way/1');
      check(
        (features[0] as Map)['geometry']['coordinates'] as List,
      ).length.equals(1);
    });
  });

  group('overpass geometry - full, tainted, nested', () {
    test('full geometry relation (json)', () {
      final json = {
        'elements': [
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon'},
            'members': [
              {
                'type': 'way',
                'ref': 1,
                'role': 'outer',
                'geometry': [
                  {'lat': 0.0, 'lon': 0.0},
                  {'lat': 0.0, 'lon': 1.0},
                  {'lat': 1.0, 'lon': 1.0},
                  {'lat': 1.0, 'lon': 0.0},
                  {'lat': 0.0, 'lon': 0.0},
                ],
              },
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      check((features[0] as Map)['geometry']['type']).equals('Polygon');
    });

    test('full geometry with tainted members (json)', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'geometry': [
              {'lat': 0.0, 'lon': 0.0},
              null,
              {'lat': 1.0, 'lon': 1.0},
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
    });

    test('tainted full geometry (xml)', () {
      const xml =
          "<osm><way id='1'>"
          "<nd lat='0.0' lon='0.0' />"
          "<nd />"
          "<nd lat='1.0' lon='1.0' />"
          "</way></osm>";
      final geojson = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
      final f = features[0] as Map<String, dynamic>;
      check(f['properties']['tainted']).equals(true);
    });

    test('full geometry mixed content (json)', () {
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [2, 3],
            'geometry': [
              {'lat': 0.0, 'lon': 0.0},
              {'lat': 1.0, 'lon': 1.0},
            ],
          },
        ],
      };
      final geojson = osmToGeoJson(json);
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(1);
    });

    test('full, mixed content (xml)', () {
      // Full geometry nodes should not shadow real nodes in output
      const xml =
          "<osm><way id='1'>"
          "<nd ref='1' lat='0' lon='0' />"
          "<nd ref='2' lat='1' lon='1' />"
          "<nd ref='3' lat='2' lon='2' />"
          "</way>"
          "<node id='2' lat='1' lon='1'>"
          "<tag k='foo' v='bar' />"
          "</node></osm>";
      final geojson = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(2);
      check((features[0] as Map)['id']).equals('way/1');
      check((features[1] as Map)['id']).equals('node/2');
      check(
        (features[1] as Map)['properties']['tags'] as Map,
      ).deepEquals({'foo': 'bar'});
    });

    test('full, mixed content (json)', () {
      // Full geometry nodes should not shadow real nodes in output
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 1,
            'nodes': [1, 2, 3],
            'geometry': [
              {'lat': 0, 'lon': 0},
              {'lat': 1, 'lon': 1},
              {'lat': 2, 'lon': 2},
            ],
          },
          {
            'type': 'node',
            'id': 2,
            'lat': 1,
            'lon': 1,
            'tags': {'foo': 'bar'},
          },
        ],
      };
      final geojson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final features = geojson['features'] as List<dynamic>;
      check(features).length.equals(2);
      check((features[0] as Map)['id']).equals('way/1');
      check((features[1] as Map)['id']).equals('node/2');
      check(
        (features[1] as Map)['properties']['tags'] as Map,
      ).deepEquals({'foo': 'bar'});
    });

    test('nested / mixed content', () {
      // JSON: relation references a way both via inline geometry AND as
      // a standalone element. The two geometries merge into one ring.
      final json = {
        'elements': [
          {
            'type': 'way',
            'id': 2,
            'tags': {'building': 'yes'},
            'nodes': [1, 2, 3],
            'geometry': [
              {'lat': 2, 'lon': 2},
              {'lat': 1, 'lon': 0},
              {'lat': 0, 'lon': 0},
            ],
          },
          {
            'type': 'relation',
            'id': 1,
            'tags': {'type': 'multipolygon', 'building': 'yes'},
            'members': [
              {
                'type': 'way',
                'ref': 1,
                'role': 'outer',
                'geometry': [
                  {'lat': 0, 'lon': 0},
                  {'lat': 0, 'lon': 1},
                  {'lat': 1, 'lon': 1},
                  {'lat': 2, 'lon': 2},
                ],
              },
              {
                'type': 'way',
                'ref': 2,
                'role': 'outer',
                'geometry': [
                  {'lat': 2, 'lon': 2},
                  {'lat': 1, 'lon': 0},
                  {'lat': 0, 'lon': 0},
                ],
              },
            ],
          },
        ],
      };
      final geoJson = osmToGeoJson(
        json,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final f =
          (geoJson['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(f['id']).equals('relation/1');
      check(f['geometry']['type']).equals('Polygon');
      final coords = (f['geometry']['coordinates'] as List)[0] as List;
      check(coords).length.equals(6);

      // XML: same scenario
      const xml =
          "<osm>"
          "<relation id='1'>"
          "<member type='way' ref='1' role='outer'>"
          "<nd lat='0' lon='0' /><nd lat='0' lon='1' />"
          "<nd lat='1' lon='1' /><nd lat='2' lon='2' />"
          "</member>"
          "<member type='way' ref='2' role='outer'>"
          "<nd lat='2' lon='2' /><nd lat='1' lon='0' />"
          "<nd lat='0' lon='0' />"
          "</member>"
          "<tag k='type' v='multipolygon' />"
          "<tag k='building' v='yes' />"
          "</relation>"
          "<way id='2'>"
          "<nd ref='1' lat='2' lon='2' />"
          "<nd ref='2' lat='1' lon='0' />"
          "<nd ref='3' lat='0' lon='0' />"
          "<tag k='building' v='yes' />"
          "</way>"
          "</osm>";
      final geoXml = osmToGeoJson(
        xml,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );
      final fXml =
          (geoXml['features'] as List<dynamic>)[0] as Map<String, dynamic>;
      check(fXml['id']).equals('relation/1');
      check(fXml['geometry']['type']).equals('Polygon');
      final coordsXml = (fXml['geometry']['coordinates'] as List)[0] as List;
      check(coordsXml).length.equals(6);
    });
  });

  group('regression', () {
    test('real-world village boundary relation (Timelkam)', () {
      // Load input from root (Overpass API JSON with full geometry)
      final inputJson =
          jsonDecode(File('test/data/input.json').readAsStringSync())
              as Map<String, dynamic>;

      // Load expected output
      final expectedGeoJson =
          jsonDecode(File('test/data/expected.geojson').readAsStringSync())
              as Map<String, dynamic>;

      // Convert with the same options the expected data was produced with
      final actual = osmToGeoJson(
        inputJson,
        options: const OsmToGeoJsonOptions(flatProperties: false),
      );

      final expectedFeatures = expectedGeoJson['features'] as List<dynamic>;
      final actualFeatures = actual['features'] as List<dynamic>;

      final expectedPolygon = expectedFeatures.first as Map<String, dynamic>;
      final actualPolygon =
          actualFeatures.firstWhere(
                (f) => (f as Map)['id'] == expectedPolygon['id'],
              )
              as Map<String, dynamic>;

      // Geometry types should match
      final eg = expectedPolygon['geometry'] as Map<String, dynamic>;
      final ag = actualPolygon['geometry'] as Map<String, dynamic>;
      check(ag['type']).equals(eg['type']);

      final ec = eg['coordinates'] as List<dynamic>;
      final ac = ag['coordinates'] as List<dynamic>;

      // Coordinates must match exactly (same ring traversal order)
      check(ac).deepEquals(ec);
    });
  });
}
