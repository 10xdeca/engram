import '../models/knowledge_graph.dart';
import '../models/recommendation.dart';

/// Evaluate how well a recommendation's predicted edges matched actual
/// edges created by ingesting the document.
///
/// Pure function (follows `difficulty_evaluation.dart` pattern).
/// Compares predicted concept-name pairs against actual relationship
/// endpoints in the post-ingestion graph that weren't in the pre-ingestion
/// graph.
RecommendationEvaluationResult evaluateRecommendation({
  required Recommendation recommendation,
  required KnowledgeGraph graphBefore,
  required KnowledgeGraph graphAfter,
}) {
  final predicted = recommendation.predictedNewEdges;
  if (predicted.isEmpty) {
    return const RecommendationEvaluationResult(
      matchedCount: 0,
      missedCount: 0,
      unexpectedCount: 0,
      totalPredicted: 0,
      totalActualNew: 0,
      accuracy: null,
    );
  }

  // Build concept name lookup for the post-ingestion graph.
  final conceptNames = <String, String>{
    for (final c in graphAfter.concepts) c.id: c.name.toLowerCase(),
  };

  // Find new edges: relationships in graphAfter that weren't in graphBefore.
  final beforeIds = graphBefore.relationships.map((r) => r.id).toSet();
  final newEdges =
      graphAfter.relationships.where((r) => !beforeIds.contains(r.id)).toList();

  // Build a set of actual new edges as normalized name pairs for matching.
  // Use null byte separator (\x00) to avoid collisions with concept names.
  final actualEdgeKeys = <String>{};
  for (final edge in newEdges) {
    final fromName = conceptNames[edge.fromConceptId];
    final toName = conceptNames[edge.toConceptId];
    if (fromName != null && toName != null) {
      actualEdgeKeys.add('$fromName\x00$toName');
      // Also add reverse for undirected matching.
      actualEdgeKeys.add('$toName\x00$fromName');
    }
  }

  // Match predicted edges against actual new edges.
  var matchedCount = 0;
  var missedCount = 0;
  final matchedActualKeys = <String>{};

  for (final pred in predicted) {
    final fromKey = pred.fromConceptName.toLowerCase();
    final toKey = pred.toConceptName.toLowerCase();
    final key = '$fromKey\x00$toKey';
    final reverseKey = '$toKey\x00$fromKey';

    if (actualEdgeKeys.contains(key) || actualEdgeKeys.contains(reverseKey)) {
      matchedCount++;
      matchedActualKeys.add(key);
      matchedActualKeys.add(reverseKey);
    } else {
      missedCount++;
    }
  }

  // Unexpected edges: actual new edges not matching any prediction.
  // Count unique undirected edges.
  final countedActual = <String>{};
  var unexpectedCount = 0;
  for (final edge in newEdges) {
    final fromName = conceptNames[edge.fromConceptId];
    final toName = conceptNames[edge.toConceptId];
    if (fromName == null || toName == null) continue;

    final key = '$fromName\x00$toName';
    final reverseKey = '$toName\x00$fromName';
    if (countedActual.contains(key)) continue;
    countedActual.add(key);
    countedActual.add(reverseKey);

    if (!matchedActualKeys.contains(key)) {
      unexpectedCount++;
    }
  }

  final totalPredicted = predicted.length;
  final accuracy = totalPredicted > 0 ? matchedCount / totalPredicted : null;

  return RecommendationEvaluationResult(
    matchedCount: matchedCount,
    missedCount: missedCount,
    unexpectedCount: unexpectedCount,
    totalPredicted: totalPredicted,
    totalActualNew: newEdges.length,
    accuracy: accuracy,
  );
}

/// Result of evaluating a recommendation's predicted edges vs actual.
class RecommendationEvaluationResult {
  const RecommendationEvaluationResult({
    required this.matchedCount,
    required this.missedCount,
    required this.unexpectedCount,
    required this.totalPredicted,
    required this.totalActualNew,
    required this.accuracy,
  });

  /// Predicted edges that matched actual new edges.
  final int matchedCount;

  /// Predicted edges that did not appear in the actual graph.
  final int missedCount;

  /// Actual new edges that were not predicted.
  final int unexpectedCount;

  /// Total number of predicted edges.
  final int totalPredicted;

  /// Total number of new edges created by ingestion.
  final int totalActualNew;

  /// Fraction of predictions that matched (null if no predictions).
  final double? accuracy;
}
