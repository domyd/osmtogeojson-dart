/// Core conversion pipeline: turns parsed OSM elements into GeoJSON features.
library;

import 'models.dart';
import 'multipolygon_helper.dart';
import 'options.dart';
import 'polygon_features.dart';
import 'utils.dart';

/// Main conversion function — takes parsed OSM elements and produces a list of
/// GeoJSON Feature maps (polygons first, then lines, then points).
///
/// Features have structured properties; [flatProperties] is applied per-feature
/// if [options.flatProperties] is true.
List<Map<String, dynamic>> convert2geoJSON(
  List<OsmNode> nodes,
  List<OsmWay> ways,
  List<OsmRelation> rels,
  OsmToGeoJsonOptions options,
) {
  final features = <Map<String, dynamic>>[];
  final verbose = options.verbose;
  final defaultUninterestingTags =
      options.uninterestingTags ??
      {
        'source': true,
        'source_ref': true,
        'source:ref': true,
        'history': true,
        'attribution': true,
        'created_by': true,
        'tiger:county': true,
        'tiger:tlid': true,
        'tiger:upload_uuid': true,
      };
  final polyFeatures = options.polygonFeatures ?? polygonFeatures;
  final deduplicator = options.deduplicator;

  // ---- Node indexing and deduplication ----
  final nodeMap = <String, OsmNode>{};
  final poiIds = <String, bool>{};
  for (final node in nodes) {
    final effective = nodeMap.containsKey(node.id)
        ? _deduplicateNode(node, nodeMap[node.id]!, deduplicator)
        : node;
    nodeMap[effective.id] = effective;
    if (effective.tags.isNotEmpty &&
        hasInterestingTags(effective.tags, defaultUninterestingTags, null)) {
      poiIds[effective.id] = true;
    }
  }

  // Mark relation member nodes as POIs
  for (final rel in rels) {
    final members = rel.members;
    if (members == null) continue;
    for (final member in members) {
      if (member.type == 'node') {
        poiIds[member.ref] = true;
      }
    }
  }

  // ---- Way indexing, deduplication, and node resolution ----
  final wayMap = <String, OsmWay>{};
  final wayNodeIds = <String, bool>{};
  for (final way in ways) {
    final effective = wayMap.containsKey(way.id)
        ? _deduplicateWay(way, wayMap[way.id]!, deduplicator)
        : way;
    wayMap[effective.id] = effective;
    for (final nodeRef in effective.nodes) {
      wayNodeIds[nodeRef] = true;
    }
  }

  // ---- Build POI list ----
  final pois = <OsmNode>[];
  for (final id in nodeMap.keys) {
    final node = nodeMap[id]!;
    if (!wayNodeIds.containsKey(id) || poiIds.containsKey(id)) {
      pois.add(node);
    }
  }

  // ---- Relation deduplication ----
  final relMap = <String, OsmRelation>{};
  for (final rel in rels) {
    final effective = relMap.containsKey(rel.id)
        ? _deduplicateRelation(rel, relMap[rel.id]!, deduplicator)
        : rel;
    relMap[effective.id] = effective;
  }

  // ---- Build relation membership map ----
  final relationsByType = <String, Map<String, List<Map<String, dynamic>>>>{
    'node': {},
    'way': {},
    'relation': {},
  };
  for (final id in relMap.keys) {
    final rel = relMap[id]!;
    final members = rel.members;
    if (members == null || members.isEmpty) {
      if (verbose) {
        print(
          'Warning: Relation ${rel.type}/${rel.id} ignored because it has no members',
        );
      }
      continue;
    }
    for (final member in members) {
      var mRef = member.ref;
      // De-namespace full geometry content
      mRef = mRef.replaceFirst('_fullGeom', '');
      final mType = member.type;
      final typeMap = relationsByType[mType];
      if (typeMap == null) {
        if (verbose) {
          print(
            'Warning: Relation ${rel.type}/${rel.id} member $mType/$mRef ignored because it has an invalid type',
          );
        }
        continue;
      }
      typeMap.putIfAbsent(mRef, () => []);
      typeMap[mRef]!.add({
        'role': member.role,
        'rel': _normalizeId(rel.id),
        'reltags': rel.tags.isNotEmpty ? rel.tags : null,
      });
    }
  }

  // ---- Collect features ----
  final geojsonPolygons = <Map<String, dynamic>>[];
  final geojsonLines = <Map<String, dynamic>>[];
  final geojsonNodes = <Map<String, dynamic>>[];

  // Emit POI features
  for (final poi in pois) {
    if (poi.lon == null || poi.lat == null) {
      if (verbose) {
        print(
          'Warning: POI ${poi.type}/${poi.id} ignored because it lacks coordinates',
        );
      }
      continue;
    }
    final feature = _buildFeature(
      type: poi.type,
      id: poi.id,
      tags: poi.tags,
      relations: _getRelations(relationsByType, poi.type, poi.id),
      meta: buildMetaInformation(
        version: poi.version,
        timestamp: poi.timestamp,
        changeset: poi.changeset,
        user: poi.user,
        uid: poi.uid,
      ),
      geometryType: 'Point',
      coordinates: [poi.lon, poi.lat],
      bbox: null,
    );
    if (poi.isCenterPlaceholder) {
      feature['properties']['geometry'] = 'center';
    }
    geojsonNodes.add(feature);
  }

  // Process relations
  for (final rel in rels) {
    // Skip deduplication artifacts
    if (relMap[rel.id] != rel) continue;

    final tags = rel.tags;
    if (tags.isEmpty) continue;

    final members = rel.members;

    // ---- Route relations ----
    if (tags['type'] == 'route' || tags['type'] == 'waterway') {
      if (members == null || members.isEmpty) {
        if (verbose) {
          print(
            'Warning: Route ${rel.type}/${rel.id} ignored because it has no members',
          );
        }
        continue;
      }

      // Mark uninteresting way members as skippable
      for (final m in members) {
        final way = wayMap[m.ref];
        if (way != null &&
            !hasInterestingTags(way.tags, defaultUninterestingTags, null)) {
          way.isSkippableRelationMember = true;
        }
      }

      final coords = _buildMultilinestringCoords(rel, wayMap, nodeMap, verbose);
      if (coords == null || coords.isEmpty) {
        if (verbose) {
          print(
            'Warning: Route relation ${rel.type}/${rel.id} ignored because it has invalid geometry',
          );
        }
        continue;
      }

      final isTainted = _checkMultilinestringTainted(rel, wayMap, nodeMap);
      final geomType = coords.length == 1 ? 'LineString' : 'MultiLineString';
      final feature = _buildFeature(
        type: rel.type,
        id: rel.id,
        tags: rel.tags,
        relations: _getRelations(relationsByType, rel.type, rel.id),
        meta: buildMetaInformation(
          version: rel.version,
          timestamp: rel.timestamp,
          changeset: rel.changeset,
          user: rel.user,
          uid: rel.uid,
        ),
        geometryType: geomType,
        coordinates: coords.length == 1 ? coords[0] : coords,
        bbox: rel.bounds,
      );
      if (isTainted) {
        if (verbose) {
          print('Warning: Route ${rel.type}/${rel.id} is tainted');
        }
        feature['properties']['tainted'] = true;
      }
      geojsonPolygons.add(feature);
      continue;
    }

    // ---- Multipolygon relations ----
    if (tags['type'] == 'multipolygon' || tags['type'] == 'boundary') {
      if (members == null || members.isEmpty) {
        if (verbose) {
          print(
            'Warning: Multipolygon ${rel.type}/${rel.id} ignored because it has no members',
          );
        }
        continue;
      }

      var outerCount = 0;
      for (final m in members) {
        if (m.role == 'outer') {
          outerCount++;
        } else if (verbose && m.role != 'inner') {
          print(
            'Warning: Multipolygon ${rel.type}/${rel.id} member ${m.type}/${m.ref} ignored because it has an invalid role: "${m.role}"',
          );
        }
      }

      // Mark members as skippable
      for (final m in members) {
        final way = wayMap[m.ref];
        if (way != null) {
          if (m.role == 'outer' &&
              !hasInterestingTags(
                way.tags,
                defaultUninterestingTags,
                rel.tags,
              )) {
            way.isSkippableRelationMember = true;
          }
          if (m.role == 'inner' &&
              !hasInterestingTags(way.tags, defaultUninterestingTags, null)) {
            way.isSkippableRelationMember = true;
          }
        }
      }

      if (outerCount == 0) {
        if (verbose) {
          print(
            'Warning: Multipolygon relation ${rel.type}/${rel.id} ignored because it has no outer ways',
          );
        }
        continue;
      }

      final isSimple =
          outerCount == 1 &&
          !hasInterestingTags(rel.tags, defaultUninterestingTags, {
            'type': true,
          });

      Map<String, dynamic>? mpFeature;
      if (!isSimple) {
        // Complex multipolygon - relation is the tag source
        final result = constructMultipolygon(
          rel,
          rel,
          wayMap,
          nodeMap,
          false,
          verbose,
        );
        if (result == null) {
          if (verbose) {
            print(
              'Warning: Multipolygon relation ${rel.type}/${rel.id} ignored because it has invalid geometry',
            );
          }
          continue;
        }
        final geomType = result['type'] as String;
        final coordinates = result['coordinates'];
        final tainted = result['tainted'] as bool? ?? false;

        final relCleanId = cleanId(rel.id);
        mpFeature = _buildFeature(
          type: rel.type,
          id: relCleanId,
          tags: rel.tags,
          relations: _getRelations(relationsByType, rel.type, rel.id),
          meta: buildMetaInformation(
            version: rel.version,
            timestamp: rel.timestamp,
            changeset: rel.changeset,
            user: rel.user,
            uid: rel.uid,
          ),
          geometryType: geomType,
          coordinates: coordinates,
          bbox: rel.bounds,
        );
        if (tainted) {
          if (verbose) {
            print('Warning: Multipolygon ${rel.type}/${rel.id} is tainted');
          }
          mpFeature['properties']['tainted'] = true;
        }
      } else {
        // Simple multipolygon - outer way is the tag source
        final outerMember = members.where((m) => m.role == 'outer').first;
        final outerWay = wayMap[outerMember.ref];
        if (outerWay == null) {
          if (verbose) {
            print(
              'Warning: Multipolygon relation ${rel.type}/${rel.id} ignored because outer way ${outerMember.type}/${outerMember.ref} is missing',
            );
          }
          continue;
        }
        outerWay.isSkippableRelationMember = true;

        final result = constructMultipolygon(
          outerWay,
          rel,
          wayMap,
          nodeMap,
          true,
          verbose,
        );
        if (result == null) {
          if (verbose) {
            print(
              'Warning: Multipolygon relation ${rel.type}/${rel.id} ignored because it has invalid geometry',
            );
          }
          continue;
        }
        final geomType = result['type'] as String;
        final coordinates = result['coordinates'];
        final tainted = result['tainted'] as bool? ?? false;

        final outerCleanId = cleanId(outerWay.id);
        mpFeature = _buildFeature(
          type: outerWay.type,
          id: outerCleanId,
          tags: outerWay.tags,
          relations: _getRelations(relationsByType, outerWay.type, outerWay.id),
          meta: buildMetaInformation(
            version: outerWay.version,
            timestamp: outerWay.timestamp,
            changeset: outerWay.changeset,
            user: outerWay.user,
            uid: outerWay.uid,
          ),
          geometryType: geomType,
          coordinates: coordinates,
          bbox: outerWay.bounds ?? rel.bounds,
        );
        if (tainted) {
          if (verbose) {
            print(
              'Warning: Multipolygon ${outerWay.type}/${outerWay.id} is tainted',
            );
          }
          mpFeature['properties']['tainted'] = true;
        }
      }

      geojsonPolygons.add(mpFeature);
    }
  }

  // Process standalone ways
  for (final way in ways) {
    // Skip deduplication artifacts
    if (wayMap[way.id] != way) continue;

    if (way.nodes.isEmpty) {
      if (verbose) {
        print(
          'Warning: Way ${way.type}/${way.id} ignored because it has no nodes',
        );
      }
      continue;
    }
    if (way.isSkippableRelationMember) continue;

    // Clean full geometry namespace from ID
    var wayId = way.id;
    final parsedId = int.tryParse(wayId);
    if (parsedId == null) {
      wayId = wayId.replaceFirst('_fullGeom', '');
    }

    way.tainted = false;
    way.hidden = false;

    final coords = <List<double>>[];
    var resolvedNodeCount = 0;
    for (final nodeRef in way.nodes) {
      final node = nodeMap[nodeRef];
      if (node != null && node.lon != null && node.lat != null) {
        coords.add([node.lon!, node.lat!]);
        resolvedNodeCount++;
      } else {
        if (verbose) {
          print(
            'Warning: Way ${way.type}/$wayId is tainted by an invalid node',
          );
        }
        way.tainted = true;
      }
    }
    if (way.hasMissingNodeRefs) {
      way.tainted = true;
    }

    if (coords.length <= 1) {
      if (verbose) {
        print(
          'Warning: Way ${way.type}/$wayId ignored because it contains too few nodes',
        );
      }
      continue;
    }

    var wayType = 'LineString'; // default
    final firstNodeRef = way.nodes.first;
    final lastNodeRef = way.nodes.last;

    if (resolvedNodeCount >= 2) {
      final firstNode = nodeMap[firstNodeRef];
      final lastNode = nodeMap[lastNodeRef];

      if (firstNode != null &&
          lastNode != null &&
          firstNode.id == lastNode.id &&
          (way.tags.isNotEmpty && _isPolygonFeature(way.tags, polyFeatures) ||
              way.isBoundsPlaceholder)) {
        wayType = 'Polygon';
      }
    }

    final geomCoords = wayType == 'Polygon' ? [coords] : coords;

    final feature = _buildFeature(
      type: way.type,
      id: wayId,
      tags: way.tags,
      relations: _getRelations(relationsByType, way.type, wayId),
      meta: buildMetaInformation(
        version: way.version,
        timestamp: way.timestamp,
        changeset: way.changeset,
        user: way.user,
        uid: way.uid,
      ),
      geometryType: wayType,
      coordinates: geomCoords,
      bbox: way.bounds,
    );

    if (way.tainted) {
      if (verbose) {
        print('Warning: Way ${way.type}/$wayId is tainted');
      }
      feature['properties']['tainted'] = true;
    }
    if (way.isBoundsPlaceholder) {
      feature['properties']['geometry'] = 'bounds';
    }

    if (wayType == 'LineString') {
      geojsonLines.add(feature);
    } else {
      geojsonPolygons.add(feature);
    }
  }

  // ---- Assemble features in order: polygons, lines, nodes ----
  features.addAll(geojsonPolygons);
  features.addAll(geojsonLines);
  features.addAll(geojsonNodes);

  // Flatten properties if configured
  if (options.flatProperties) {
    for (final f in features) {
      final props = f['properties'] as Map<String, dynamic>;
      final meta = (props['meta'] ?? {}) as Map<String, dynamic>;
      final tags = (props['tags'] ?? {}) as Map<String, dynamic>;
      final idStr = '${props['type']}/${props['id']}';

      final flat = <String, dynamic>{};
      flat.addAll(meta);
      flat.addAll(tags);
      flat['id'] = idStr;
      f['properties'] = flat;
    }
  }

  return features;
}

// ---- Helper functions ----

/// Validates and sets the bbox field on a GeoJSON feature.
///
/// Only sets `'bbox'` if [bounds] is non-null, has 4 elements, all values
/// are finite, and coordinates are within valid geographic ranges per
/// RFC 7946: longitude in [-180, 180], latitude in [-90, 90].
List<double>? _validateBbox(List<double>? bounds) {
  if (bounds == null || bounds.length != 4) return null;
  for (var i = 0; i < 4; i++) {
    if (!bounds[i].isFinite) return null;
  }
  // Validate geographic bounds per GeoJSON spec
  if (bounds[0] < -180 ||
      bounds[0] > 180 ||
      bounds[2] < -180 ||
      bounds[2] > 180) {
    return null;
  }
  if (bounds[1] < -90 || bounds[1] > 90 || bounds[3] < -90 || bounds[3] > 90) {
    return null;
  }
  return bounds;
}

/// Builds a GeoJSON Feature map.
Map<String, dynamic> _buildFeature({
  required String type,
  required String id,
  required Map<String, String> tags,
  required List<Map<String, dynamic>> relations,
  required Map<String, dynamic> meta,
  required String geometryType,
  required dynamic coordinates,
  required List<double>? bbox,
}) {
  return {
    'type': 'Feature',
    'id': '$type/$id',
    'properties': {
      'type': type,
      'id': _normalizeId(id),
      'tags': tags,
      'relations': relations,
      'meta': meta,
    },
    'bbox': ?_validateBbox(bbox),
    'geometry': {'type': geometryType, 'coordinates': coordinates},
  };
}

/// Determines if a set of tags indicates the closed way should be a polygon.
bool _isPolygonFeature(
  Map<String, String> tags,
  Map<String, dynamic> polyFeatures,
) {
  // Explicitly tagged non-areas
  if (tags['area'] == 'no') return false;

  for (final key in tags.keys) {
    final val = tags[key]!;
    final pfk = polyFeatures[key];
    if (pfk == null) continue;
    // Explicitly un-set (e.g., building=no)
    if (val == 'no') continue;

    if (pfk == true) return true;
    if (pfk is Map) {
      final included = pfk['included_values'] as Map<String, dynamic>?;
      final excluded = pfk['excluded_values'] as Map<String, dynamic>?;
      if (included != null && included[val] == true) return true;
      if (excluded != null && excluded[val] != true) return true;
    }
  }
  return false;
}

/// Gets relation membership info for an element.
List<Map<String, dynamic>> _getRelations(
  Map<String, Map<String, List<Map<String, dynamic>>>> relsmap,
  String type,
  String id,
) {
  final typeMap = relsmap[type];
  if (typeMap == null) return [];
  return typeMap[id] ?? [];
}

/// Deduplicate a node.
OsmNode _deduplicateNode(
  OsmNode a,
  OsmNode b,
  Map<String, dynamic> Function(Map<String, dynamic>, Map<String, dynamic>)?
  customDedup,
) {
  if (customDedup != null) {
    final result = customDedup(_osmNodeToMap(a), _osmNodeToMap(b));
    return _mapToOsmNode(result);
  }
  // Default: higher version wins, else merge
  if ((a.version != null || b.version != null) && a.version != b.version) {
    return ((a.version ?? 0) > (b.version ?? 0)) ? a : b;
  }
  // Merge: b's values overwrite a's for non-null
  if (b.version != null) a.version = b.version;
  if (b.timestamp != null) a.timestamp = b.timestamp;
  if (b.changeset != null) a.changeset = b.changeset;
  if (b.user != null) a.user = b.user;
  if (b.uid != null) a.uid = b.uid;
  if (b.lat != null) a.lat = b.lat;
  if (b.lon != null) a.lon = b.lon;
  a.tags.addAll(b.tags);
  return a;
}

/// Deduplicate a way.
OsmWay _deduplicateWay(
  OsmWay a,
  OsmWay b,
  Map<String, dynamic> Function(Map<String, dynamic>, Map<String, dynamic>)?
  customDedup,
) {
  if (customDedup != null) {
    final result = customDedup(_osmWayToMap(a), _osmWayToMap(b));
    return _mapToOsmWay(result);
  }
  if ((a.version != null || b.version != null) && a.version != b.version) {
    return ((a.version ?? 0) > (b.version ?? 0)) ? a : b;
  }
  if (b.version != null) a.version = b.version;
  if (b.timestamp != null) a.timestamp = b.timestamp;
  if (b.changeset != null) a.changeset = b.changeset;
  if (b.user != null) a.user = b.user;
  if (b.uid != null) a.uid = b.uid;
  if (b.nodes.isNotEmpty) a.nodes = b.nodes;
  if (b.isBoundsPlaceholder) a.isBoundsPlaceholder = true;
  if (b.hasMissingNodeRefs) a.hasMissingNodeRefs = true;
  if (b.bounds != null) a.bounds = b.bounds;
  a.tags.addAll(b.tags);
  return a;
}

/// Deduplicate a relation.
OsmRelation _deduplicateRelation(
  OsmRelation a,
  OsmRelation b,
  Map<String, dynamic> Function(Map<String, dynamic>, Map<String, dynamic>)?
  customDedup,
) {
  if (customDedup != null) {
    final result = customDedup(_osmElementToMap(a), _osmElementToMap(b));
    return _mapToOsmRelation(result);
  }
  if ((a.version != null || b.version != null) && a.version != b.version) {
    return ((a.version ?? 0) > (b.version ?? 0)) ? a : b;
  }
  if (b.version != null) a.version = b.version;
  if (b.timestamp != null) a.timestamp = b.timestamp;
  if (b.changeset != null) a.changeset = b.changeset;
  if (b.user != null) a.user = b.user;
  if (b.uid != null) a.uid = b.uid;
  if (b.bounds != null) a.bounds = b.bounds;
  a.tags.addAll(b.tags);
  return a;
}

/// Convert OsmElement to a Map for custom deduplicator.
Map<String, dynamic> _osmElementToMap(OsmElement el) {
  final m = <String, dynamic>{'type': el.type, 'id': el.id, 'tags': el.tags};
  if (el.version != null) m['version'] = el.version;
  if (el.timestamp != null) m['timestamp'] = el.timestamp;
  if (el.changeset != null) m['changeset'] = el.changeset;
  if (el.user != null) m['user'] = el.user;
  if (el.uid != null) m['uid'] = el.uid;
  if (el is OsmRelation && el.bounds != null) m['bounds'] = el.bounds;
  return m;
}

/// Convert OsmNode to a Map for custom deduplicator.
Map<String, dynamic> _osmNodeToMap(OsmNode el) {
  final m = _osmElementToMap(el);
  if (el.lat != null) m['lat'] = el.lat;
  if (el.lon != null) m['lon'] = el.lon;
  return m;
}

/// Convert OsmWay to a Map for custom deduplicator.
Map<String, dynamic> _osmWayToMap(OsmWay el) {
  final m = _osmElementToMap(el);
  m['nodes'] = el.nodes;
  if (el.bounds != null) m['bounds'] = el.bounds;
  return m;
}

/// Convert a deduplication result Map back to OsmNode.
OsmNode _mapToOsmNode(Map<String, dynamic> m) {
  return OsmNode(
    id: m['id']?.toString() ?? '',
    lat: (m['lat'] as num?)?.toDouble(),
    lon: (m['lon'] as num?)?.toDouble(),
    tags: parseTags(m['tags']),
    version: (m['version'] as num?)?.toInt(),
    timestamp: m['timestamp'] as String?,
    changeset: (m['changeset'] as num?)?.toInt(),
    user: m['user'] as String?,
    uid: (m['uid'] as num?)?.toInt(),
  );
}

/// Convert a deduplication result Map back to OsmWay.
OsmWay _mapToOsmWay(Map<String, dynamic> m) {
  return OsmWay(
    id: m['id']?.toString() ?? '',
    nodes: (m['nodes'] as List<dynamic>?)
        ?.map((n) => n?.toString())
        .whereType<String>()
        .toList(),
    tags: parseTags(m['tags']),
    version: (m['version'] as num?)?.toInt(),
    timestamp: m['timestamp'] as String?,
    changeset: (m['changeset'] as num?)?.toInt(),
    user: m['user'] as String?,
    uid: (m['uid'] as num?)?.toInt(),
    bounds: (m['bounds'] as List<dynamic>?)
        ?.map((v) => (v as num).toDouble())
        .toList(),
  );
}

/// Convert a deduplication result Map back to OsmRelation.
OsmRelation _mapToOsmRelation(Map<String, dynamic> m) {
  return OsmRelation(
    id: m['id']?.toString() ?? '',
    tags: parseTags(m['tags']),
    version: (m['version'] as num?)?.toInt(),
    timestamp: m['timestamp'] as String?,
    changeset: (m['changeset'] as num?)?.toInt(),
    user: m['user'] as String?,
    uid: (m['uid'] as num?)?.toInt(),
    bounds: (m['bounds'] as List<dynamic>?)
        ?.map((v) => (v as num).toDouble())
        .toList(),
  );
}

/// Normalize an ID for output (convert string to int if numeric).
dynamic _normalizeId(String id) {
  final parsed = int.tryParse(id);
  return parsed ?? id;
}

/// Build multilinestring coordinates for a route relation.
List<List<List<double>>>? _buildMultilinestringCoords(
  OsmRelation rel,
  Map<String, OsmWay> wayMap,
  Map<String, OsmNode> nodeMap,
  bool verbose,
) {
  final wayMembers = <ProcessedWayMember>[];
  final members = rel.members;
  if (members != null) {
    for (final m in members) {
      if (m.type != 'way') continue;
      final way = wayMap[m.ref];
      if (way == null || way.nodes.isEmpty) {
        if (verbose) {
          print(
            'Warning: Route ${rel.type}/${rel.id} tainted by a missing or incomplete way ${m.type}/${m.ref}',
          );
        }
        continue;
      }
      final resolvedNodes = <OsmNode>[];
      for (final nodeRef in way.nodes) {
        final node = nodeMap[nodeRef];
        if (node != null) {
          resolvedNodes.add(node);
        }
      }
      wayMembers.add(
        ProcessedWayMember(
          id: m.ref,
          role: m.role ?? '',
          way: way,
          nodes: resolvedNodes,
        ),
      );
    }
  }

  if (wayMembers.isEmpty) return null;

  final linestrings = join(wayMembers);
  final coords = <List<List<double>>>[];
  for (final ls in linestrings) {
    final lineCoords = <List<double>>[];
    for (final node in ls) {
      if (node.lon != null && node.lat != null) {
        lineCoords.add([node.lon!, node.lat!]);
      }
    }
    if (lineCoords.isNotEmpty) {
      coords.add(lineCoords);
    }
  }

  return coords.isEmpty ? null : coords;
}

/// Check if a multilinestring route relation is tainted.
bool _checkMultilinestringTainted(
  OsmRelation rel,
  Map<String, OsmWay> wayMap,
  Map<String, OsmNode> nodeMap,
) {
  final members = rel.members;
  if (members == null) return true;
  for (final m in members) {
    if (m.type != 'way') continue;
    final way = wayMap[m.ref];
    if (way == null || way.nodes.isEmpty || way.hasMissingNodeRefs) return true;
    for (final nodeRef in way.nodes) {
      if (!nodeMap.containsKey(nodeRef)) return true;
    }
  }
  return false;
}
