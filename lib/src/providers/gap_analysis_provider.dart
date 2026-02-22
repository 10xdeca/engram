import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/gap_analyzer.dart';
import '../models/knowledge_gap.dart';
import 'cluster_provider.dart';
import 'graph_structure_provider.dart';

/// Cached gap analysis that only recomputes when the graph's structural
/// elements (concepts or relationships) change.
///
/// Watches [graphStructureProvider] (not the full graph) so quiz-item-only
/// updates do NOT trigger recomputation.
final gapAnalysisProvider = Provider<List<KnowledgeGap>>((ref) {
  final graph = ref.watch(graphStructureProvider);
  if (graph == null) return [];
  final clusters = ref.watch(clusterProvider);
  return GapAnalyzer(graph, clusters: clusters).analyze();
});
