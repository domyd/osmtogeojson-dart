/// Helper functions for constructing multipolygons and multilinestrings
/// from OSM relations.
library;

import 'models.dart';
import 'utils.dart';

/// Joins adjacent OSM way segments into continuous linestrings or linear rings.
///
/// Ported from iD editor's relation.js.
List<List<OsmNode>> join(List<ProcessedWayMember> ways) {
  final joined = <List<OsmNode>>[];
  final remaining = ways.map((w) => List<OsmNode>.from(w.nodes)).toList();

  while (remaining.isNotEmpty) {
    final current = remaining.removeAt(0);
    joined.add(current);

    while (remaining.isNotEmpty && !_nodesMatch(current.first, current.last)) {
      final first = current.first;
      final last = current.last;
      List<OsmNode>? segment;
      void Function(OsmNode)? insertFn;
      int foundIndex = -1;

      for (var i = 0; i < remaining.length; i++) {
        final candidate = remaining[i];
        if (_nodesMatch(last, candidate.first)) {
          insertFn = (node) => current.add(node);
          segment = candidate.sublist(1);
          foundIndex = i;
          break;
        } else if (_nodesMatch(last, candidate.last)) {
          insertFn = (node) => current.add(node);
          segment = candidate
              .sublist(0, candidate.length - 1)
              .reversed
              .toList();
          foundIndex = i;
          break;
        } else if (_nodesMatch(first, candidate.last)) {
          insertFn = (node) => current.insert(0, node);
          segment = candidate.sublist(0, candidate.length - 1);
          foundIndex = i;
          break;
        } else if (_nodesMatch(first, candidate.first)) {
          insertFn = (node) => current.insert(0, node);
          segment = candidate.sublist(1).reversed.toList();
          foundIndex = i;
          break;
        }
      }

      if (segment == null || insertFn == null) {
        break; // Invalid geometry (dangling way, unclosed ring)
      }

      remaining.removeAt(foundIndex);
      for (final node in segment) {
        insertFn(node);
      }
    }
  }

  return joined;
}

/// Checks if two nodes match by ID. Returns false if either is null.
bool _nodesMatch(OsmNode? a, OsmNode? b) {
  return a != null && b != null && a.id == b.id;
}

/// Ray-casting point-in-polygon test.
///
/// Based on https://github.com/substack/point-in-polygon
/// and http://www.ecse.rpi.edu/Homepages/wrf/Research/Short_Notes/pnpoly.html
bool pointInPolygon(List<double> point, List<List<double>> polygon) {
  final x = point[0], y = point[1];
  var inside = false;

  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i][0], yi = polygon[i][1];
    final xj = polygon[j][0], yj = polygon[j][1];

    final intersect =
        ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }

  return inside;
}

/// Checks if a polygon (outer ring) intersects with another polygon (inner ring).
bool _polygonIntersectsPolygon(
  List<List<double>> outer,
  List<List<double>> inner,
) {
  for (final point in inner) {
    if (pointInPolygon(point, outer)) return true;
  }
  return false;
}

/// Converts a list of OsmNode objects to [lon, lat] coordinate pairs.
List<List<double>> _mapCoordinates(List<OsmNode> nodes) {
  return nodes.map((n) => [n.lon!, n.lat!]).toList();
}

/// Finds which outer ring contains the given inner ring.
///
/// Returns the index of the containing outer ring, or null if none found.
int? findOuter(List<OsmNode> inner, List<List<OsmNode>> outers) {
  final innerCoords = _mapCoordinates(inner);
  for (var o = 0; o < outers.length; o++) {
    final outerCoords = _mapCoordinates(outers[o]);
    if (_polygonIntersectsPolygon(outerCoords, innerCoords)) {
      return o;
    }
  }
  return null;
}

/// Builds multipolygon coordinates from a relation's outer and inner way members.
///
/// Returns null if the multipolygon cannot be constructed.
Map<String, dynamic>? constructMultipolygon(
  OsmElement tagObject,
  OsmRelation rel,
  Map<String, OsmWay> wayMap,
  Map<String, OsmNode> nodeMap,
  bool isSimple,
  bool verbose,
) {
  var isTainted = false;
  final mpGeometry = isSimple ? 'way' : 'relation';
  final mpId = cleanId(tagObject.id);

  // Filter to way members
  final members =
      rel.members
          ?.where((m) => m.type == 'way')
          .map((m) {
            final way = wayMap[m.ref];
            if (way == null || way.nodes.isEmpty) {
              if (verbose) {
                print(
                  'Warning: Multipolygon $mpGeometry/$mpId tainted by a missing or incomplete way ${m.type}/${m.ref}',
                );
              }
              isTainted = true;
              return null;
            }
            final validNodes = <OsmNode>[];
            for (final nodeRef in way.nodes) {
              final node = nodeMap[nodeRef];
              if (node != null) {
                validNodes.add(node);
              } else {
                isTainted = true;
                if (verbose) {
                  print(
                    'Warning: Multipolygon $mpGeometry/$mpId tainted by a way ${m.type}/${m.ref} with an unresolved node',
                  );
                }
              }
            }
            return ProcessedWayMember(
              id: m.ref,
              role: m.role ?? 'outer',
              way: way,
              nodes: validNodes,
            );
          })
          .where((m) => m != null)
          .cast<ProcessedWayMember>()
          .toList() ??
      [];

  if (members.isEmpty) {
    if (verbose) {
      print('Warning: Multipolygon $mpGeometry/$mpId has no usable members');
    }
    return null;
  }

  // Separate outer and inner rings
  final outerMembers = members.where((m) => m.role == 'outer').toList();
  final innerMembers = members.where((m) => m.role == 'inner').toList();

  // Build rings
  final outers = join(outerMembers);
  final inners = join(innerMembers);

  // Assign inner rings to outer rings
  final mp = outers.map((o) => [o]).toList();
  for (final inner in inners) {
    final outerIdx = findOuter(inner, outers);
    if (outerIdx != null) {
      mp[outerIdx].add(inner);
    } else {
      if (verbose) {
        print(
          'Warning: Multipolygon $mpGeometry/$mpId contains an inner ring with no containing outer',
        );
      }
    }
  }

  // Convert to coordinate arrays, filter degenerate rings
  final mpCoords = <List<List<List<double>>>>[];
  for (final cluster in mp) {
    final ringCoords = <List<List<double>>>[];
    for (final ring in cluster) {
      if (ring.length < 4) {
        if (verbose) {
          print(
            'Warning: Multipolygon $mpGeometry/$mpId contains a ring with less than four nodes',
          );
        }
        continue;
      }
      final coords = <List<double>>[];
      for (final node in ring) {
        if (node.lon != null && node.lat != null) {
          coords.add([node.lon!, node.lat!]);
        }
      }
      if (coords.isNotEmpty) {
        ringCoords.add(coords);
      }
    }
    if (ringCoords.isEmpty) {
      if (verbose) {
        print(
          'Warning: Multipolygon $mpGeometry/$mpId contains an empty ring cluster',
        );
      }
      continue;
    }
    mpCoords.add(ringCoords);
  }

  if (mpCoords.isEmpty) {
    if (verbose) {
      print('Warning: Multipolygon $mpGeometry/$mpId contains no coordinates');
    }
    return null;
  }

  final geometryType = mpCoords.length == 1 ? 'Polygon' : 'MultiPolygon';
  final coordinates = mpCoords.length == 1 ? mpCoords[0] : mpCoords;

  return {
    'type': geometryType,
    'coordinates': coordinates,
    'tainted': isTainted,
  };
}
