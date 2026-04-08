import '../models/knowledge_graph.dart';

/// Extracts the 1-hop neighborhood of [conceptId] from [graph].
///
/// Returns a [KnowledgeGraph] containing:
/// - The target concept
/// - All concepts directly connected by a relationship
/// - All relationships whose both endpoints are in the neighborhood
///
/// Returns an empty graph if [conceptId] is not found.
KnowledgeGraph neighborhoodOf(String conceptId, KnowledgeGraph graph) {
  final target = graph.concepts.where((c) => c.id == conceptId).firstOrNull;
  if (target == null) return KnowledgeGraph.empty;

  // Find all relationships touching the target concept.
  final directEdges = graph.relationships.where(
    (r) => r.fromConceptId == conceptId || r.toConceptId == conceptId,
  );

  // Collect neighbor IDs from those edges.
  final neighborIds = <String>{};
  for (final r in directEdges) {
    neighborIds.add(r.fromConceptId);
    neighborIds.add(r.toConceptId);
  }
  neighborIds.add(conceptId);

  // Collect all concepts in the neighborhood.
  final concepts =
      graph.concepts.where((c) => neighborIds.contains(c.id)).toList();

  // Include all edges whose both endpoints are in the neighborhood.
  final relationships =
      graph.relationships
          .where(
            (r) =>
                neighborIds.contains(r.fromConceptId) &&
                neighborIds.contains(r.toConceptId),
          )
          .toList();

  return KnowledgeGraph(concepts: concepts, relationships: relationships);
}
