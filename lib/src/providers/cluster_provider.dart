import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/cluster_detector.dart';
import '../models/concept.dart';
import '../models/concept_cluster.dart';
import '../models/knowledge_graph.dart';
import '../models/relationship.dart';
import 'knowledge_graph_provider.dart';

/// Cached cluster detection that only recomputes when the graph's structural
/// elements (concepts or relationships) change.
///
/// Quiz-item-only updates (the most frequent mutation) do NOT trigger
/// recomputation because [IList] value equality means the same concepts/
/// relationships reference compares equal after [withUpdatedQuizItem].
final clusterProvider = Provider<List<ConceptCluster>>((ref) {
  // Select only structural fields — quiz item changes won't invalidate.
  final IList<Concept>? concepts = ref.watch(
    knowledgeGraphProvider
        .select((AsyncValue<KnowledgeGraph> av) => av.valueOrNull?.concepts),
  );
  final IList<Relationship>? relationships = ref.watch(
    knowledgeGraphProvider.select(
        (AsyncValue<KnowledgeGraph> av) => av.valueOrNull?.relationships),
  );

  if (concepts == null || concepts.isEmpty) return [];

  // Build a lightweight structural graph for cluster detection.
  final structuralGraph = KnowledgeGraph(
    concepts: concepts.toList(),
    relationships: (relationships ?? const IListConst<Relationship>([])).toList(),
  );
  return ClusterDetector(structuralGraph).detect();
});
