import 'dart:collection';

/// Intensity multipliers at each BFS depth from an active concept.
const _depthIntensity = [1.0, 0.4, 0.15];

/// Propagates glow intensity outward from active concepts via BFS.
///
/// Returns a map of `{conceptId: intensity}` where:
/// - Active (primary) concepts have intensity **1.0**
/// - Depth-1 neighbors have intensity **0.4**
/// - Depth-2 neighbors have intensity **0.15**
/// - Nodes beyond depth 2 are excluded.
///
/// When multiple active concepts produce overlapping propagation, the
/// **maximum** intensity wins (e.g., a node that is depth-1 from concept A
/// and depth-2 from concept B gets 0.4, not 0.15).
///
/// The [adjacencyMap] should be an undirected adjacency list where each
/// concept ID maps to the set of its direct neighbors.
Map<String, double> propagateHighlight({
  required Set<String> activeConcepts,
  required Map<String, Set<String>> adjacencyMap,
}) {
  if (activeConcepts.isEmpty) return const {};

  final result = <String, double>{};

  for (final seed in activeConcepts) {
    _bfsFromSeed(seed, adjacencyMap, result);
  }

  return result;
}

/// BFS from a single seed concept, merging max intensity into [result].
void _bfsFromSeed(
  String seed,
  Map<String, Set<String>> adjacencyMap,
  Map<String, double> result,
) {
  final visited = <String>{};
  final queue = Queue<(String, int)>();

  queue.add((seed, 0));
  visited.add(seed);

  while (queue.isNotEmpty) {
    final (nodeId, depth) = queue.removeFirst();

    if (depth >= _depthIntensity.length) continue;

    final intensity = _depthIntensity[depth];
    final existing = result[nodeId] ?? 0.0;
    if (intensity > existing) {
      result[nodeId] = intensity;
    }

    // Only expand if next depth is still within range.
    if (depth + 1 < _depthIntensity.length) {
      for (final neighbor in adjacencyMap[nodeId] ?? const <String>{}) {
        if (visited.add(neighbor)) {
          queue.add((neighbor, depth + 1));
        }
      }
    }
  }
}
