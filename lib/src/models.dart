/// Data models for OSM elements used during conversion.
///
/// Represents a parsed OSM element (node, way, or relation).
///
/// Fields are mutable to allow in-place deduplication during conversion.
class OsmElement {
  final String type; // "node", "way", "relation", "area"

  /// String to handle both numeric and _fullGeom/_anonymous@lat/lon IDs.
  final String id;

  Map<String, String> tags;
  int? version;
  String? timestamp;
  int? changeset;
  String? user;
  int? uid;

  OsmElement({
    required this.type,
    required this.id,
    Map<String, String>? tags,
    this.version,
    this.timestamp,
    this.changeset,
    this.user,
    this.uid,
  }) : tags = tags ?? {};
}

/// Represents an OSM node element.
class OsmNode extends OsmElement {
  double? lat;
  double? lon;
  bool isCenterPlaceholder;

  OsmNode({
    required super.id,
    this.lat,
    this.lon,
    super.tags,
    super.version,
    super.timestamp,
    super.changeset,
    super.user,
    super.uid,
    this.isCenterPlaceholder = false,
  }) : super(type: 'node');
}

/// Represents an OSM way element.
class OsmWay extends OsmElement {
  /// List of node ref IDs. Never contains null entries — missing/invalid refs
  /// are filtered at parse time and flagged via [hasMissingNodeRefs].
  List<String> nodes;

  bool isBoundsPlaceholder;
  bool isSkippableRelationMember;
  bool tainted;
  bool hidden;

  /// Whether any node refs were missing or invalid during parsing.
  bool hasMissingNodeRefs;

  /// Bounding box in GeoJSON order: `[minLon, minLat, maxLon, maxLat]`.
  /// Set from OSM `bounds` data when present on the input element.
  List<double>? bounds;

  OsmWay({
    required super.id,
    List<String>? nodes,
    super.tags,
    super.version,
    super.timestamp,
    super.changeset,
    super.user,
    super.uid,
    this.isBoundsPlaceholder = false,
    this.isSkippableRelationMember = false,
    this.tainted = false,
    this.hidden = false,
    this.hasMissingNodeRefs = false,
    this.bounds,
  }) : nodes = nodes ?? [],
       super(type: 'way');
}

/// Represents an OSM relation element.
class OsmRelation extends OsmElement {
  List<OsmMember>? members;

  /// Bounding box in GeoJSON order: `[minLon, minLat, maxLon, maxLat]`.
  /// Set from OSM `bounds` data when present on the input element.
  List<double>? bounds;

  OsmRelation({
    required super.id,
    this.members,
    super.tags,
    super.version,
    super.timestamp,
    super.changeset,
    super.user,
    super.uid,
    this.bounds,
  }) : super(type: 'relation');
}

/// Represents a member of an OSM relation.
class OsmMember {
  final String type; // "node", "way", "relation"
  String ref; // String ref (may be _fullGeom-prefixed, mutated during parsing)
  final String? role;

  OsmMember({required this.type, required this.ref, this.role});
}

/// Represents a way member during multipolygon/route construction.
class ProcessedWayMember {
  final String id;
  final String role;
  final OsmWay way;
  final List<OsmNode> nodes;

  ProcessedWayMember({
    required this.id,
    required this.role,
    required this.way,
    required this.nodes,
  });
}
