import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:meta/meta.dart';

/// The type of structural gap detected in the knowledge graph.
///
/// Each gap type corresponds to a different detection algorithm in
/// [GapAnalyzer] and suggests a different kind of content to fill it.
enum GapType {
  /// Two concept clusters with no cross-cluster edges.
  clusterIsolation,

  /// An important concept with very few connections (degree <= 1).
  structuralThinness,

  /// A cluster dominated by prerequisite chains with no lateral relationships
  /// (analogy, contrast, enables).
  relationshipTypeGap,

  /// A high out-degree concept with low mastery — the graph needs alternative
  /// paths around this chokepoint.
  criticalBottleneck,
}

/// A detected gap in the knowledge graph that could be filled by learning
/// new material.
///
/// Immutable data class following the [NetworkHealth]/[ConceptCluster] pattern.
/// Gaps are produced by [GapAnalyzer] and consumed by the recommendation
/// pipeline to find Outline documents that would bridge them.
@immutable
class KnowledgeGap {
  KnowledgeGap({
    required this.type,
    required this.description,
    required this.severity,
    required this.bridgePotential,
    List<String> involvedConceptIds = const [],
    List<String> involvedClusterLabels = const [],
    List<String> suggestedSearchTerms = const [],
  }) : involvedConceptIds = IList(involvedConceptIds),
       involvedClusterLabels = IList(involvedClusterLabels),
       suggestedSearchTerms = IList(suggestedSearchTerms);

  const KnowledgeGap._raw({
    required this.type,
    required this.description,
    required this.severity,
    required this.bridgePotential,
    required this.involvedConceptIds,
    required this.involvedClusterLabels,
    required this.suggestedSearchTerms,
  });

  factory KnowledgeGap.fromJson(Map<String, dynamic> json) {
    return KnowledgeGap._raw(
      type: GapType.values.byName(json['type'] as String),
      description: json['description'] as String,
      severity: (json['severity'] as num).toDouble(),
      bridgePotential: (json['bridgePotential'] as num).toDouble(),
      involvedConceptIds:
          (json['involvedConceptIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toIList() ??
          const IListConst([]),
      involvedClusterLabels:
          (json['involvedClusterLabels'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toIList() ??
          const IListConst([]),
      suggestedSearchTerms:
          (json['suggestedSearchTerms'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toIList() ??
          const IListConst([]),
    );
  }

  /// What kind of structural gap this represents.
  final GapType type;

  /// Human-readable description of the gap and why it matters.
  final String description;

  /// How severe this gap is (0.0 = minor, 1.0 = critical).
  final double severity;

  /// How much new connectivity would result from bridging this gap
  /// (0.0 = minimal, 1.0 = transformative).
  final double bridgePotential;

  /// Concept IDs involved in this gap (e.g. both sides of an isolation gap).
  final IList<String> involvedConceptIds;

  /// Cluster labels involved (for gap types that span clusters).
  final IList<String> involvedClusterLabels;

  /// Search terms derived from involved concept names and descriptions.
  /// Used by the recommendation pipeline to query Outline.
  final IList<String> suggestedSearchTerms;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'description': description,
    'severity': severity,
    'bridgePotential': bridgePotential,
    'involvedConceptIds': involvedConceptIds.toList(),
    'involvedClusterLabels': involvedClusterLabels.toList(),
    'suggestedSearchTerms': suggestedSearchTerms.toList(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnowledgeGap &&
          other.type == type &&
          other.description == description &&
          other.severity == severity;

  @override
  int get hashCode => Object.hash(type, description, severity);

  @override
  String toString() =>
      'KnowledgeGap(${type.name}, severity: $severity, '
      '"$description")';
}
