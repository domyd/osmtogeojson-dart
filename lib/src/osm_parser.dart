/// Parses OSM data from JSON (Overpass) or XML format into internal element
/// lists.
library;

import 'package:xml/xml.dart';

import 'models.dart';
import 'utils.dart';

/// Holds the result of parsing OSM input.
class OsmParsedData {
  final List<OsmNode> nodes;
  final List<OsmWay> ways;
  final List<OsmRelation> rels;

  OsmParsedData({required this.nodes, required this.ways, required this.rels});
}

/// Converts an OSM element ID or member ref from JSON (which may be [num] or
/// [String]) to its canonical [String] form.
String _parseId(dynamic id) => id?.toString() ?? '';

/// Parses Overpass JSON (or OSM JSON) format into element lists.
OsmParsedData parseOsmJson(Map<String, dynamic> json, bool verbose) {
  final nodes = <OsmNode>[];
  final ways = <OsmWay>[];
  final rels = <OsmRelation>[];

  // Helper: creates a pseudo-node at the given coordinates.
  OsmNode centerGeometry(String type, String id, double lat, double lon) {
    final pseudoNode = OsmNode(
      id: id,
      lat: lat,
      lon: lon,
      tags: {},
      isCenterPlaceholder: true,
    );
    nodes.add(pseudoNode);
    return pseudoNode;
  }

  /// Builds a stable anonymous node ID from coordinates.
  ///
  /// Uses [toStringAsFixed] so that e.g. `48` (int) and `48.0` (double)
  /// produce the same string, which is critical for [_nodesMatch] in the
  /// ring-assembly [join] function.
  String _anonId(num lat, num lon) =>
      '_anonymous@${lat.toDouble().toStringAsFixed(7)}/'
      '${lon.toDouble().toStringAsFixed(7)}';

  /// Create a pseudo-node from inline lat/lon.
  OsmNode addFullGeometryNode(String id, double lat, double lon) {
    final node = OsmNode(id: id, lat: lat, lon: lon, tags: {});
    nodes.add(node);
    return node;
  }

  // Process elements
  final elements = json['elements'] as List<dynamic>?;
  if (elements == null) {
    if (verbose) print('Warning: No "elements" field found in JSON input');
    return OsmParsedData(nodes: nodes, ways: ways, rels: rels);
  }

  for (final el in elements) {
    final element = el as Map<String, dynamic>;
    final type = element['type'] as String?;

    switch (type) {
      case 'node':
        final node = OsmNode(
          id: _parseId(element['id']),
          lat: (element['lat'] as num?)?.toDouble(),
          lon: (element['lon'] as num?)?.toDouble(),
          tags: parseTags(element['tags']),
          version: (element['version'] as num?)?.toInt(),
          timestamp: element['timestamp'] as String?,
          changeset: (element['changeset'] as num?)?.toInt(),
          user: element['user'] as String?,
          uid: (element['uid'] as num?)?.toInt(),
        );
        nodes.add(node);
        break;

      case 'way':
        final wayId = _parseId(element['id']);
        final wayTags = parseTags(element['tags']);

        // Parse node refs, filtering out nulls
        final rawNodeRefs = element['nodes'] as List<dynamic>?;
        final wayNodes = <String>[];
        var nodeRefsHadNulls = false;
        if (rawNodeRefs != null) {
          for (final n in rawNodeRefs) {
            final str = n?.toString();
            if (str != null) {
              wayNodes.add(str);
            } else {
              nodeRefsHadNulls = true;
            }
          }
        }

        final center = element['center'] as Map<String, dynamic>?;
        final bounds = element['bounds'] as Map<String, dynamic>?;
        final geometry = element['geometry'] as List<dynamic>?;

        // Handle full geometry (inline coordinates)
        if (geometry != null) {
          // If the way doesn't have a nodes array, create one from geometry
          if (rawNodeRefs == null) {
            final geomNodes = <String>[];
            for (final nd in geometry) {
              if (nd != null) {
                final ndMap = nd as Map<String, dynamic>;
                geomNodes.add(
                  _anonId(ndMap['lat'] as num, ndMap['lon'] as num),
                );
              } else {
                geomNodes.add('_anonymous@unknown_location');
              }
            }
            wayNodes
              ..clear()
              ..addAll(geomNodes);
          }
          // Create pseudo-nodes for each coordinate
          var idx = 0;
          for (final nd in geometry) {
            if (nd != null) {
              final ndMap = nd as Map<String, dynamic>;
              final nodeRef = idx < wayNodes.length ? wayNodes[idx] : null;
              addFullGeometryNode(
                nodeRef ?? '_anonymous@unknown_location',
                (ndMap['lat'] as num).toDouble(),
                (ndMap['lon'] as num).toDouble(),
              );
            }
            idx++;
          }
        }

        // Handle bounds geometry (pseudo-way rectangle)
        if (geometry == null && bounds != null) {
          final minlat = (bounds['minlat'] as num).toDouble();
          final minlon = (bounds['minlon'] as num).toDouble();
          final maxlat = (bounds['maxlat'] as num).toDouble();
          final maxlon = (bounds['maxlon'] as num).toDouble();

          final pseudoWay = OsmWay(
            id: wayId,
            nodes: [],
            tags: wayTags,
            isBoundsPlaceholder: true,
          );

          _addBoundsRing(
            '_way/$wayId',
            minlat,
            minlon,
            maxlat,
            maxlon,
            pseudoWay,
            nodes,
          );

          ways.add(pseudoWay);
        }

        // Handle center geometry (pseudo-node at center)
        if (center != null) {
          centerGeometry(
            'way',
            wayId,
            (center['lat'] as num).toDouble(),
            (center['lon'] as num).toDouble(),
          );
        } else if (geometry == null && bounds == null) {
          // Normal way
          final way = OsmWay(
            id: wayId,
            nodes: wayNodes,
            tags: wayTags,
            version: (element['version'] as num?)?.toInt(),
            timestamp: element['timestamp'] as String?,
            changeset: (element['changeset'] as num?)?.toInt(),
            user: element['user'] as String?,
            uid: (element['uid'] as num?)?.toInt(),
            hasMissingNodeRefs: nodeRefsHadNulls,
          );
          ways.add(way);
        } else if (geometry != null) {
          // Way with full geometry
          final way = OsmWay(
            id: wayId,
            nodes: wayNodes,
            tags: wayTags,
            version: (element['version'] as num?)?.toInt(),
            timestamp: element['timestamp'] as String?,
            changeset: (element['changeset'] as num?)?.toInt(),
            user: element['user'] as String?,
            uid: (element['uid'] as num?)?.toInt(),
            hasMissingNodeRefs: nodeRefsHadNulls,
          );
          ways.add(way);
        }
        break;

      case 'relation':
        final relId = _parseId(element['id']);
        final relTags = parseTags(element['tags']);
        final relMembersRaw = element['members'] as List<dynamic>? ?? [];
        final relMembers = relMembersRaw.map((m) {
          final mm = m as Map<String, dynamic>;
          return OsmMember(
            type: mm['type'] as String? ?? '',
            ref: _parseId(mm['ref']),
            role: mm['role'] as String?,
          );
        }).toList();

        final relCenter = element['center'] as Map<String, dynamic>?;
        final relBounds = element['bounds'] as Map<String, dynamic>?;

        // Check for full geometry in members
        var hasFullGeometry = false;
        for (var i = 0; i < relMembersRaw.length; i++) {
          final member = relMembersRaw[i] as Map<String, dynamic>;
          final mType = member['type'] as String?;
          if (mType == 'node' && member.containsKey('lat')) {
            hasFullGeometry = true;
            break;
          }
          if (mType == 'way') {
            final geom = member['geometry'] as List<dynamic>?;
            if (geom != null && geom.isNotEmpty) {
              hasFullGeometry = true;
              break;
            }
          }
        }

        if (hasFullGeometry) {
          // Process full geometry relation members
          for (var i = 0; i < relMembersRaw.length; i++) {
            final member = relMembersRaw[i] as Map<String, dynamic>;
            final mType = member['type'] as String?;

            if (mType == 'node') {
              if (member.containsKey('lat')) {
                addFullGeometryNode(
                  relMembers[i].ref,
                  (member['lat'] as num).toDouble(),
                  (member['lon'] as num).toDouble(),
                );
              }
            } else if (mType == 'way') {
              final geom = member['geometry'] as List<dynamic>?;
              if (geom != null) {
                // Prefix the ref with _fullGeom to namespace it (only if not
                // already prefixed — Overpass out:geom responses already have it).
                final rawRef = relMembers[i].ref;
                relMembers[i].ref = rawRef.startsWith('_fullGeom')
                    ? rawRef
                    : '_fullGeom$rawRef';
                final geomWayId = relMembers[i].ref;

                // Check if this way already exists
                final alreadyExists = ways.any(
                  (w) => w.type == 'way' && w.id == geomWayId,
                );
                if (!alreadyExists) {
                  final geomWay = OsmWay(id: geomWayId, nodes: []);
                  var hadNull = false;
                  for (final nd in geom) {
                    if (nd != null) {
                      final ndMap = nd as Map<String, dynamic>;
                      final pseudoNode = OsmNode(
                        id: _anonId(ndMap['lat'] as num, ndMap['lon'] as num),
                        lat: (ndMap['lat'] as num).toDouble(),
                        lon: (ndMap['lon'] as num).toDouble(),
                        tags: {},
                      );
                      geomWay.nodes.add(pseudoNode.id);
                      nodes.add(pseudoNode);
                    } else {
                      hadNull = true;
                    }
                  }
                  if (hadNull) geomWay.hasMissingNodeRefs = true;
                  ways.add(geomWay);
                }
              }
            }
          }
        }

        // Handle bounds geometry for relation
        if (!hasFullGeometry && relBounds != null) {
          final minlat = (relBounds['minlat'] as num).toDouble();
          final minlon = (relBounds['minlon'] as num).toDouble();
          final maxlat = (relBounds['maxlat'] as num).toDouble();
          final maxlon = (relBounds['maxlon'] as num).toDouble();

          final pseudoWay = OsmWay(
            id: relId,
            nodes: [],
            tags: relTags,
            isBoundsPlaceholder: true,
          );

          _addBoundsRing(
            '_relation/$relId',
            minlat,
            minlon,
            maxlat,
            maxlon,
            pseudoWay,
            nodes,
          );

          ways.add(pseudoWay);
        }

        // Handle center geometry for relation
        if (relCenter != null) {
          centerGeometry(
            'relation',
            relId,
            (relCenter['lat'] as num).toDouble(),
            (relCenter['lon'] as num).toDouble(),
          );
        }

        final rel = OsmRelation(
          id: relId,
          members: relMembers,
          tags: relTags,
          version: (element['version'] as num?)?.toInt(),
          timestamp: element['timestamp'] as String?,
          changeset: (element['changeset'] as num?)?.toInt(),
          user: element['user'] as String?,
          uid: (element['uid'] as num?)?.toInt(),
        );
        rels.add(rel);
        break;

      default:
        // Skip unknown types (e.g., "area")
        break;
    }
  }

  return OsmParsedData(nodes: nodes, ways: ways, rels: rels);
}

/// Parses OSM XML format into element lists.
OsmParsedData parseOsmXml(String xmlString, bool verbose) {
  final nodes = <OsmNode>[];
  final ways = <OsmWay>[];
  final rels = <OsmRelation>[];

  final document = XmlDocument.parse(xmlString);
  final osm = document.rootElement;

  // Helper: extract attribute as string
  String? attr(XmlElement el, String name) {
    final a = el.getAttribute(name);
    return a;
  }

  // Helper: extract attribute as int
  int? attrInt(XmlElement el, String name) {
    final a = el.getAttribute(name);
    if (a == null) return null;
    return int.tryParse(a);
  }

  // Helper: extract attribute as double
  double? attrDouble(XmlElement el, String name) {
    final a = el.getAttribute(name);
    if (a == null) return null;
    return double.tryParse(a);
  }

  // Helper: parse <tag> children into a map
  Map<String, String> parseTags(XmlElement parent) {
    final tags = <String, String>{};
    for (final tag in parent.findElements('tag')) {
      final k = tag.getAttribute('k');
      final v = tag.getAttribute('v');
      if (k != null && v != null) {
        tags[k] = v;
      }
    }
    return tags;
  }

  // Helper: create pseudo-node at center
  void centerGeometry(OsmElement element, XmlElement centroid) {
    final lat = attrDouble(centroid, 'lat');
    final lon = attrDouble(centroid, 'lon');
    if (lat != null && lon != null) {
      final pseudoNode = OsmNode(
        id: element.id,
        lat: lat,
        lon: lon,
        tags: Map<String, String>.from(element.tags),
        version: element.version,
        timestamp: element.timestamp,
        changeset: element.changeset,
        user: element.user,
        uid: element.uid,
        isCenterPlaceholder: true,
      );
      nodes.add(pseudoNode);
    }
  }

  // Helper: create pseudo-way rectangle from bounds
  void boundsGeometry(OsmElement element, XmlElement boundsEl) {
    final minlat = attrDouble(boundsEl, 'minlat');
    final minlon = attrDouble(boundsEl, 'minlon');
    final maxlat = attrDouble(boundsEl, 'maxlat');
    final maxlon = attrDouble(boundsEl, 'maxlon');

    if (minlat == null || minlon == null || maxlat == null || maxlon == null) {
      return;
    }

    final pseudoWay = OsmWay(
      id: element.id,
      nodes: [],
      tags: Map<String, String>.from(element.tags),
      isBoundsPlaceholder: true,
    );

    _addBoundsRing(
      '_${element.type}/${element.id}',
      minlat,
      minlon,
      maxlat,
      maxlon,
      pseudoWay,
      nodes,
    );

    ways.add(pseudoWay);
  }

  // Parse <node> elements
  for (final nodeEl in osm.findElements('node')) {
    final tags = parseTags(nodeEl);
    final node = OsmNode(
      id: attr(nodeEl, 'id') ?? '',
      lat: attrDouble(nodeEl, 'lat'),
      lon: attrDouble(nodeEl, 'lon'),
      tags: tags,
      version: attrInt(nodeEl, 'version'),
      timestamp: attr(nodeEl, 'timestamp'),
      changeset: attrInt(nodeEl, 'changeset'),
      user: attr(nodeEl, 'user'),
      uid: attrInt(nodeEl, 'uid'),
    );
    nodes.add(node);
  }

  // Parse <way> elements
  for (final wayEl in osm.findElements('way')) {
    final tags = parseTags(wayEl);

    // Parse node references
    final wnodes = <String>[];
    var hasFullGeometry = false;
    for (final nd in wayEl.findElements('nd')) {
      final ref = nd.getAttribute('ref');
      if (ref != null) {
        wnodes.add(ref);
      }
      if (nd.getAttribute('lat') != null) {
        hasFullGeometry = true;
      }
    }

    final wayId = attr(wayEl, 'id') ?? '';
    final wayObject = OsmWay(
      id: wayId,
      nodes: wnodes,
      tags: tags,
      version: attrInt(wayEl, 'version'),
      timestamp: attr(wayEl, 'timestamp'),
      changeset: attrInt(wayEl, 'changeset'),
      user: attr(wayEl, 'user'),
      uid: attrInt(wayEl, 'uid'),
    );

    // Check for <center> child
    final centerEl = wayEl.findElements('center').firstOrNull;
    if (centerEl != null) {
      centerGeometry(wayObject, centerEl);
    }

    // Check for full geometry
    if (hasFullGeometry) {
      // Create pseudo-nodes from inline nd coordinates
      if (!(elementHasNodesList(wayObject.nodes))) {
        wayObject.nodes = [];
        final nds = wayEl.findElements('nd').toList();
        for (var i = 0; i < nds.length; i++) {
          final nd = nds[i];
          wayObject.nodes.add(
            '_anonymous@${nd.getAttribute('lat')}/${nd.getAttribute('lon')}',
          );
        }
      }
      final nds = wayEl.findElements('nd').toList();
      for (var i = 0; i < nds.length; i++) {
        final nd = nds[i];
        final lat = attrDouble(nd, 'lat');
        final lon = attrDouble(nd, 'lon');
        if (lat != null && lon != null) {
          final geometryNode = OsmNode(
            id: wayObject.nodes[i],
            lat: lat,
            lon: lon,
            tags: {},
          );
          nodes.add(geometryNode);
        }
      }
    }

    // Check for <bounds> child
    final boundsEl = wayEl.findElements('bounds').firstOrNull;
    if (!hasFullGeometry && boundsEl != null) {
      boundsGeometry(wayObject, boundsEl);
    }

    ways.add(wayObject);
  }

  // Parse <relation> elements
  for (final relEl in osm.findElements('relation')) {
    final tags = parseTags(relEl);

    // Parse members
    final members = <OsmMember>[];
    var hasFullGeometry = false;
    final memberElements = relEl.findElements('member').toList();
    for (final memberEl in memberElements) {
      final member = OsmMember(
        type: attr(memberEl, 'type') ?? '',
        ref: attr(memberEl, 'ref') ?? '',
        role: attr(memberEl, 'role'),
      );
      members.add(member);

      if (!hasFullGeometry &&
          ((member.type == 'node' && memberEl.getAttribute('lat') != null) ||
              (member.type == 'way' &&
                  memberEl.findElements('nd').isNotEmpty))) {
        hasFullGeometry = true;
      }
    }

    final relId = attr(relEl, 'id') ?? '';
    final relObject = OsmRelation(
      id: relId,
      members: members,
      tags: tags,
      version: attrInt(relEl, 'version'),
      timestamp: attr(relEl, 'timestamp'),
      changeset: attrInt(relEl, 'changeset'),
      user: attr(relEl, 'user'),
      uid: attrInt(relEl, 'uid'),
    );

    // Check for <center> child
    final centerEl = relEl.findElements('center').firstOrNull;
    if (centerEl != null) {
      centerGeometry(relObject, centerEl);
    }

    // Full geometry for relation members
    if (hasFullGeometry) {
      for (var i = 0; i < memberElements.length; i++) {
        final memberEl = memberElements[i];
        final member = members[i];

        if (member.type == 'node') {
          final lat = attrDouble(memberEl, 'lat');
          final lon = attrDouble(memberEl, 'lon');
          if (lat != null && lon != null) {
            final geometryNode = OsmNode(
              id: member.ref,
              lat: lat,
              lon: lon,
              tags: {},
            );
            nodes.add(geometryNode);
          }
        } else if (member.type == 'way') {
          final wayNds = memberEl.findElements('nd').toList();
          if (wayNds.isNotEmpty) {
            member.ref = '_fullGeom${member.ref}';
            final geomWayId = member.ref;

            final alreadyExists = ways.any(
              (w) => w.type == 'way' && w.id == geomWayId,
            );
            if (!alreadyExists) {
              final geomWay = OsmWay(id: geomWayId, nodes: []);
              for (final nd in wayNds) {
                final lat = attrDouble(nd, 'lat');
                final lon = attrDouble(nd, 'lon');
                if (lat != null && lon != null) {
                  final pseudoNode = OsmNode(
                    id: '_anonymous@$lat/$lon',
                    lat: lat,
                    lon: lon,
                    tags: {},
                  );
                  geomWay.nodes.add(pseudoNode.id);
                  nodes.add(pseudoNode);
                }
                // Missing lat/lon in full geometry: skip the node
              }
              ways.add(geomWay);
            }
          }
        }
      }
    }

    // Check for <bounds> child
    final boundsEl = relEl.findElements('bounds').firstOrNull;
    if (!hasFullGeometry && boundsEl != null) {
      boundsGeometry(relObject, boundsEl);
    }

    rels.add(relObject);
  }

  return OsmParsedData(nodes: nodes, ways: ways, rels: rels);
}

/// Helper to check if a way has a proper nodes list (not just null/empty).
bool elementHasNodesList(List<String> nodes) {
  return nodes.isNotEmpty;
}

/// Adds a rectangular ring of pseudo-nodes to [pseudoWay] and [allNodes],
/// representing a bounds geometry.
void _addBoundsRing(
  String prefix,
  double minlat,
  double minlon,
  double maxlat,
  double maxlon,
  OsmWay pseudoWay,
  List<OsmNode> allNodes,
) {
  void add(double lat, double lon, int i) {
    final pid = '$prefix+bounds$i';
    final pnode = OsmNode(id: pid, lat: lat, lon: lon, tags: {});
    pseudoWay.nodes.add(pid);
    allNodes.add(pnode);
  }

  add(minlat, minlon, 1);
  add(maxlat, minlon, 2);
  add(maxlat, maxlon, 3);
  add(minlat, maxlon, 4);
  pseudoWay.nodes.add(pseudoWay.nodes[0]); // close ring
}
