import 'dart:convert';

import 'package:osmtogeojson/osmtogeojson.dart';

void main() {
  // JSON as output by Overpass API (using `[out:json];`)
  final overpassJson = {
    'elements': [
      {
        'type': 'node',
        'id': 1,
        'lat': 48.2082,
        'lon': 16.3738,
        'tags': {'name': 'Vienna', 'place': 'city'},
      },
    ],
  };

  // Convert to GeoJSON and pretty-print it
  final geoJson = osmToGeoJson(overpassJson);
  print(const JsonEncoder.withIndent('  ').convert(geoJson));
}
