/// Rewinds GeoJSON polygons to ensure proper winding order.
///
/// Per the GeoJSON specification (RFC 7946), outer rings must be
/// counter-clockwise and inner rings must be clockwise.
///
/// Ported from @mapbox/geojson-rewind.
///
/// Rewinds the polygons in [geojson] to follow the right-hand rule, mutating
/// the input in place.
void rewind(Map<String, dynamic> geojson) {
  final features = geojson['features'] as List<dynamic>?;
  if (features == null) return;

  for (final f in features) {
    final feature = f as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;

    final type = geometry['type'] as String?;
    if (type == 'Polygon') {
      _rewindPolygon(geometry['coordinates'] as List<dynamic>?);
    } else if (type == 'MultiPolygon') {
      final coords = geometry['coordinates'] as List<dynamic>?;
      if (coords != null) {
        for (final polygon in coords) {
          _rewindPolygon(polygon as List<dynamic>?);
        }
      }
    }
  }
}

/// Rewind a single polygon's rings. Outer ring CCW, inner rings CW.
void _rewindPolygon(List<dynamic>? rings) {
  if (rings == null || rings.isEmpty) return;

  final outer = rings[0] as List<dynamic>;
  if (_clockwise(outer)) {
    rings[0] = outer.reversed.toList();
  }

  for (var i = 1; i < rings.length; i++) {
    final inner = rings[i] as List<dynamic>;
    if (!_clockwise(inner)) {
      rings[i] = inner.reversed.toList();
    }
  }
}

/// Returns `true` if the ring is clockwise (has positive signed area).
///
/// Uses the shoelace formula. For [lon, lat] coordinate pairs,
/// a positive area indicates clockwise winding.
bool _clockwise(List<dynamic> ring) {
  var sum = 0.0;

  if (ring.length < 2) return false;

  for (var i = 0; i < ring.length - 1; i++) {
    final p1 = ring[i] as List<dynamic>;
    final p2 = ring[i + 1] as List<dynamic>;
    final x1 = (p1[0] as num).toDouble();
    final y1 = (p1[1] as num).toDouble();
    final x2 = (p2[0] as num).toDouble();
    final y2 = (p2[1] as num).toDouble();
    sum += (x2 - x1) * (y2 + y1);
  }

  return sum > 0;
}
