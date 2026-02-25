import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/highlight_propagation.dart';
import 'graph_structure_provider.dart';
import 'narration_provider.dart';

/// Provides a `{conceptId: intensity}` map for graph glow during narration.
///
/// Combines the active concepts from [narrationProvider] with BFS highlight
/// propagation from [propagateHighlight] using the graph adjacency structure.
///
/// Returns an empty map when no narration is active, allowing the graph to
/// fall back to its existing ingest glow behavior.
final activeConceptsProvider = Provider<Map<String, double>>((ref) {
  final session = ref.watch(narrationProvider);
  final graph = ref.watch(graphStructureProvider);

  // No glow when narration isn't active or graph isn't loaded.
  if (session.activeConcepts.isEmpty || graph == null) {
    return const {};
  }

  // Build undirected adjacency map from graph relationships.
  final adjacencyMap = <String, Set<String>>{};
  for (final r in graph.relationships) {
    adjacencyMap.putIfAbsent(r.fromConceptId, () => {}).add(r.toConceptId);
    adjacencyMap.putIfAbsent(r.toConceptId, () => {}).add(r.fromConceptId);
  }

  return propagateHighlight(
    activeConcepts: session.activeConcepts.toSet(),
    adjacencyMap: adjacencyMap,
  );
});
