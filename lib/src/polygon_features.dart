/// Polygon feature detection rules based on OSM wiki conventions.
///
/// Ported from the osm-polygon-features npm package (v0.9.1).
/// See https://wiki.openstreetmap.org/wiki/Overpass_turbo/Polygon_Features
library;

/// Transformed polygon features lookup map.
///
/// Format:
/// - `true` value means the key always indicates a polygon
/// - `{"included_values": {...}}` means only those values indicate a polygon
/// - `{"excluded_values": {...}}` means all values except those indicate a polygon
const Map<String, dynamic> polygonFeatures = {
  'building': true,
  'landuse': true,
  'amenity': true,
  'leisure': true,
  'area': true,
  'boundary': true,
  'place': true,
  'shop': true,
  'tourism': true,
  'historic': true,
  'public_transport': true,
  'office': true,
  'building:part': true,
  'military': true,
  'ruins': true,
  'area:highway': true,
  'craft': true,
  'golf': true,
  'highway': {
    'included_values': {
      'services': true,
      'rest_area': true,
      'escape': true,
      'elevator': true,
    },
  },
  'natural': {
    'excluded_values': {
      'coastline': true,
      'cliff': true,
      'ridge': true,
      'arete': true,
      'tree_row': true,
    },
  },
  'waterway': {
    'included_values': {
      'riverbank': true,
      'dock': true,
      'boatyard': true,
      'dam': true,
    },
  },
  'barrier': {
    'included_values': {
      'city_wall': true,
      'ditch': true,
      'hedge': true,
      'retaining_wall': true,
      'wall': true,
      'spikes': true,
    },
  },
  'railway': {
    'included_values': {
      'station': true,
      'turntable': true,
      'roundhouse': true,
      'platform': true,
    },
  },
  'man_made': {
    'excluded_values': {'cutline': true, 'embankment': true, 'pipeline': true},
  },
  'power': {
    'included_values': {
      'plant': true,
      'substation': true,
      'generator': true,
      'transformer': true,
    },
  },
  'aeroway': {
    'excluded_values': {'taxiway': true},
  },
};
