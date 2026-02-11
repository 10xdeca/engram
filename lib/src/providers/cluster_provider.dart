import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/cluster_detector.dart';
import '../models/concept_cluster.dart';
import 'graph_structure_provider.dart';

/// Cached cluster detection that only recomputes when the graph's structural
/// elements (concepts or relationships) change.
///
/// Quiz-item-only updates (the most frequent mutation) do NOT trigger
/// recomputation because [graphStructureProvider] uses [IList] value equality
/// to short-circuit on structural identity.
final clusterProvider = Provider<List<ConceptCluster>>((ref) {
  final graph = ref.watch(graphStructureProvider);
  if (graph == null) return [];
  return ClusterDetector(graph).detect();
});
